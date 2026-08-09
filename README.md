# infrastructure

Home lab infrastructure. The repo root is an HA k3s cluster: **3 servers**
(control plane, embedded etcd) + **3 agents** (workers), running NixOS VMs on
Proxmox VE. Terraform builds the VMs, NixOS owns everything inside them, kube-vip
floats a control-plane VIP across the three servers, and `apps/` is reconciled
into the cluster by Flux.

```
hosts.json            single source of truth (IPs, VM IDs, sizes, VIP) — read by both nix and terraform
flake.nix             golden image + one nixosConfiguration per node
nix/modules/          base, hardware, network, tailscale, k3s-server, k3s-agent, image (cloud-init)
nix/kube-vip.yaml.in  control-plane VIP DaemonSet, templated with the VIP/interface
terraform/            bpg/proxmox: uploads the image, creates the six VMs
apps/                 GitOps: what Flux deploys into the cluster (see apps/README.md)
mise.toml             the task runner — everything below is a mise task
```

## How it fits together

1. `nix build .#image` produces one generic NixOS qcow2: SSH key, qemu-guest-agent,
   cloud-init. No node identity.
2. Terraform uploads it once and clones it into six VMs, handing each its hostname,
   IP and SSH key through the Proxmox cloud-init drive.
3. `scripts/deploy-node.sh` replaces that generic system with the real per-node
   config (static IP identical to the cloud-init one, k3s server or agent): build
   the closure, `nix copy` it over SSH, set the system profile, run
   `switch-to-configuration switch`. That is `nixos-rebuild --target-host` spelled
   out, so it works from a build host that only has Nix in a container. From then
   on cloud-init is off and the flake is authoritative.

Deploy order matters and `mise run deploy` handles it: bootstrap server
(`--cluster-init`) → remaining servers (join the bootstrap directly) → agents (join
the VIP). Agents point at the VIP so any single control-plane node can die.

## Prerequisites

- **Nix, or Docker.** `scripts/nix.sh` uses the host's `nix` when it exists and
  otherwise runs everything in the `nixos/nix` container against a persistent
  `k3s-nix-store` volume. Nothing else here needs Nix installed. `/dev/kvm` is
  passed through when present — the qcow2 is assembled inside a qemu VM, so
  without it the image build fails with `required system or feature not available`.
- **The tree must be committed (or at least `git add`ed).** The flake is evaluated
  from the git tree, which is what keeps `secrets/` and the 2GB `build/` out of the
  nix store. `scripts/nix.sh` refuses to run with untracked files and tells you what
  to add.
- A Proxmox API token, **with privilege separation off**:

  ```bash
  pveum user token add root@pam terraform --privsep 0
  # already created with privsep on? note the two separate args, not root@pam!terraform:
  pveum user token modify root@pam terraform --privsep 0
  ```

  `pve_api_token` is the token id and the secret joined with `=`, e.g.
  `root@pam!terraform=<uuid>`. The secret is displayed once, at creation.

  A privsep token with no ACL of its own authenticates fine and then sees
  *nothing* — the API filters lists by permission instead of returning 403, so
  storages, bridges and permissions all come back as empty arrays rather than an
  error. `mise run preflight` calls this out.
- SSH access to the Proxmox node itself — the provider shells out for disk import
  and **ignores `~/.ssh/config`**. It uses `pve_ssh_private_key_path`
  (`~/.ssh/id_ed25519` by default); set it to `""` to use a loaded ssh-agent
  instead. Without either you get `attempted methods [none password]` partway
  through apply, after the VMs already exist.
- `mise trust` in this directory.

## Preflight

```bash
mise run preflight
```

Checks, against the real API, before anything is created: token authenticates,
token can actually see things, node is online, both datastores exist with the
right content types, VM IDs are free, the bridge exists, SSH to the node works,
none of the cluster IPs or the VIP already answer, image is built.

It cannot check that the switch port trunks your `vlan_id` — if VMs come up with
no network, that is the first thing to look at.

## Setup

Edit `hosts.json` first — it is currently `10.0.200.0/24`, VIP `.40`, servers
`.41-.43`, agents `.51-.53`, VM IDs 141-143 / 151-153. Check `cluster.interface`
matches what the VMs actually get (`eth0` on this Proxmox; verify with `qm agent <id> network-get-interfaces`); kube-vip binds to it.

```bash
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
$EDITOR terraform/terraform.tfvars   # endpoint, token, node, datastores

mise trust
mise run bootstrap        # image -> tf apply -> deploy -> kubeconfig -> status
```

Or step by step:

```bash
mise run image            # build the qcow2
mise run tf:plan
mise run tf:apply         # six VMs, booted with cloud-init identity
mise run push-token       # generates secrets/k3s-token and scps it to all nodes
mise run push-tailscale-key   # optional, see below
mise run deploy           # nixos-rebuild every node, in the right order
mise run kubeconfig       # ./kubeconfig, pointed at the VIP
mise run status
```

`mise run deploy-node k3s-agent-2` rebuilds a single machine.

The image lands in `build/nixos.qcow2` (~590MB, compressed qcow2 — qemu-img
decompresses it on import) and Terraform uploads it from there.

### Slow or failing image upload

`iso` content always goes through the PVE HTTP API — no SSH, no resume. A big
image on a WAN link fails like this:

```
proxmox_virtual_environment_file.nixos_image: Still creating... [19m50s elapsed]
Error: error listing files from datastore local: context deadline exceeded
```

`image_upload_timeout` (default 7200s here, vs the provider's 1800s) covers the
slow-but-working case. When the API path is hopeless, skip it:

```bash
mise run push-image                              # rsync --partial, resumable
echo 'upload_image = false' >> terraform/terraform.tfvars
mise run tf:apply
```

Terraform then references `local:iso/nixos-k3s-base.img` in place of a file it
manages itself.

## Remote access (Tailscale)

Every node joins the tailnet, and the three servers advertise `10.0.200.0/24`
into it. That keeps remote `kubectl` pointed at the kube-vip VIP instead of a
single named node, so control-plane HA survives leaving the LAN. Tailscale moves
a subnet route to another advertiser by itself when one server goes away.

Configured under `cluster.tailscale` in `hosts.json`; set `enable: false` there
and the module drops out entirely.

```json
"tailscale": {
  "enable": true,
  "advertise_routes": ["10.0.200.0/24"]
}
```

Nodes log in unattended from a pre-auth key, the same shape as the k3s token:

```bash
# reusable key from https://login.tailscale.com/admin/settings/keys
umask 077 && echo 'tskey-auth-...' > secrets/tailscale-authkey
mise run push-tailscale-key    # /var/lib/tailscale-authkey on all six nodes
mise run deploy
mise run ts:status             # tailnet name, address and primary routes per node
```

`deploy` depends on this task, and the task is a no-op with a hint when there is
no key file — the key has to be on disk before the switch, because
`tailscaled-autoconnect` runs during activation. The key is only read while a
node is logged out, so re-deploying is harmless.

Then **approve the subnet route once** at
`https://login.tailscale.com/admin/machines` (the route shows up under one of
the servers as pending; approve it on all three for failover).

On the Mac:

```bash
brew install --cask tailscale
brew install kubectl
tailscale up --accept-routes     # without this the 10.0.200.0/24 route is ignored
```

Copy `./kubeconfig` over from the build host as described above — it already
points at `https://10.0.200.40:6443`, the VIP is in the API server's `--tls-san`,
and the subnet route makes it reachable. Nothing about the file changes between
LAN and tailnet.

- Subnet routes are SNATed by default, so packets reach the VIP with the routing
  server's LAN address as source and match the existing eth0 firewall rules.
- `tailscale0` is a trusted firewall interface on every node, so `ssh root@<node
  tailnet name>` works too — add the Mac's public key to `nix/modules/base.nix`
  first, that list is the only authorized one.
- MagicDNS is off on the nodes (`--accept-dns=false`). It rewrites
  `/etc/resolv.conf`, which puts the tailnet resolver in front of the one k3s
  hands to containers. Node names still resolve fine *from* the Mac.

## Notes

- The join token lives in `secrets/k3s-token` (gitignored) and is pushed to
  `/var/lib/k3s-token` on every node. k3s will not start without it — that is why
  `push-token` runs before `deploy`. Swap in sops-nix if you want it in the repo.
- Traefik and servicelb are disabled. Bring your own ingress; kube-vip here only
  does the control plane (`svc_enable=false`), flip that on if you want LB services.
- `disk[0].file_id` is in `lifecycle.ignore_changes`, so rebuilding the image does
  not recreate live VMs. Node changes ship via `deploy`, not Terraform.
- Firewall is on: 6443/2379/2380/10250 + UDP 8472 on servers, 10250 + 8472 on agents,
  UDP 41641 and a trusted `tailscale0` everywhere.
- Changing a node's `cores`/`memory`/`disk` in `hosts.json` is a `tf:apply`; changing
  its IP means both `tf:apply` and `deploy`.
