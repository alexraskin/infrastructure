# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

The repo root is an HA k3s cluster: 3 servers (control plane + embedded etcd) and
3 agents, running as NixOS VMs on a single Proxmox host. Terraform creates the
VMs, NixOS owns everything inside them, Flux deploys workloads from `apps/`.

## Where explanations go

**This file, not code comments.** Inline comments stay to a line or two —
enough to flag the non-obvious at the call site. Background, tradeoffs, why a
setting is load-bearing and what breaks if it changes belong in the nearest
`CLAUDE.md` — this one, or the directory's own. Two copies of the same reasoning drift, and the configs here are
short enough that a comment block twice the length of the config is noise.

## Commands

`mise` runs everything. Three separate configs: `mise.toml` at the root
(cluster), `apps/mise.toml` (GitOps) and `00-cloud-edge/mise.toml` (the Oracle
edge). `mise trust` is needed once per directory.

```bash
mise run preflight      # validate Proxmox API token, node, datastores, VM IDs, IPs, SSH — do this first
mise run image          # build the golden NixOS qcow2 into build/
mise run tf:plan        # terraform, from terraform/proxmox/
mise run tf:apply       # create the six VMs
mise run push-token     # generate secrets/k3s-token and scp it to every node
mise run push-tailscale-key   # scp secrets/tailscale-authkey to every node (no-op without one)
mise run deploy         # nixos-rebuild every node in the right order
mise run deploy-node k3s-agent-2   # one node
mise run kubeconfig     # fetch ./kubeconfig, rewritten to point at the VIP
mise run status         # kubectl get nodes + kube-system pods
mise run ts:status      # tailnet name/address/primary routes per node
mise run ts:plan        # terraform, from tailscale/ (the tailnet policy file)
mise run ts:apply       # same, applied — CI does this on push to main
mise run cf:plan        # terraform, from terraform/cloudflare/ (tunnel + DNS)
mise run cf:apply       # same, applied
mise run reset          # DESTRUCTIVE: wipe k3s state cluster-wide (typed confirmation)
```

From `00-cloud-edge/` (its own mise config):

```bash
mise run tf:apply       # Oracle instance, public IP, DNS records — retries every AD on capacity errors
mise run install        # nixos-anywhere: kexec + disko + install. One shot, erases the box
mise run deploy         # push the flake and switch; repeatable
mise run status         # tailscale, haproxy, certs, backend reachability
```

Validation without touching infrastructure:

```bash
terraform -chdir=terraform/proxmox validate && terraform fmt -recursive terraform/
terraform -chdir=terraform/cloudflare validate
terraform -chdir=00-cloud-edge/terraform validate
terraform -chdir=tailscale init -backend=false && terraform -chdir=tailscale validate
./scripts/nix.sh 'nix eval ".#nixosConfigurations.k3s-server-1.config.networking.hostName"'
# path:, or nix resolves to the enclosing git repo — which is the cluster flake
./scripts/nix.sh 'nix eval "path:./00-cloud-edge#nixosConfigurations.edge-1.config.system.build.toplevel.drvPath"'
cd apps && mise exec -- kustomize build base/alexraskin-com
cd apps && mise exec -- kustomize build base/monitoring
cd apps && mise exec -- kustomize build base/tailscale-operator
cd apps && mise exec -- kustomize build base/loki && mise exec -- kustomize build base/alloy
```

There is no test suite. "Does it work" means `mise run preflight`, a `terraform
plan`, a `nix eval` of the affected node, and finally `mise run status`.

## Architecture

### hosts.json is the single source of truth

Both `flake.nix` (`builtins.fromJSON`) and `terraform/proxmox/main.tf` (`jsondecode`) read
it. Node IPs, VM IDs, sizes, the VIP, the NIC name and the disk device all live
there. Changing a node's cores/memory/disk is a `tf:apply`; changing its IP needs
both `tf:apply` and `deploy`.

### Two-phase node lifecycle

1. **Golden image** — `base.nix` + `image.nix`, built by nixos-generators into a
   compressed qcow2. Carries no node identity; gets hostname, IP and SSH key from
   the Proxmox cloud-init drive Terraform configures.
2. **Per-node config** — `nixosConfigurations.<host>` = `base` + `hardware` +
   `network` + `tools` + a role module. Pushed by `scripts/deploy-node.sh`, which
   replaces the generic system with a static one. cloud-init is off afterwards.

`image.nix` is deliberately **not** in the node configs, which is why
`hardware.nix` exists: it re-states the root filesystem, `boot.growPartition` and
grub settings that nixos-generators' qcow format supplies to the image. Without
it node configs fail to evaluate with "The 'fileSystems' option does not specify
your root file system".

### scripts/nix.sh — the Nix entry point

The build host (Debian) has no Nix, so this wrapper runs the given shell script
against the host's `nix` if present, otherwise inside the `nixos/nix` container
with a persistent `k3s-nix-store` volume. Every Nix invocation in the repo goes
through it. Three things it handles that are easy to break:

- **Flakes evaluate from the git tree**, which is what keeps `secrets/` and the
  ~600MB `build/` out of the nix store. Untracked files are invisible to
  evaluation, so the script refuses to run when `flake.nix`, `flake.lock`,
  `hosts.json` or `nix/` have untracked changes. **`git add` before deploying.**
- `/dev/kvm` is passed through and `system-features = kvm` declared — the qcow2 is
  assembled inside a qemu VM and the build fails without it.
- A generated gitconfig with `safe.directory = /work` is mounted, because the
  container is root, the repo is not, and libgit2 (which Nix uses) ignores
  `GIT_CONFIG_*` environment variables.

### Deploying is not nixos-rebuild

`scripts/deploy-node.sh` spells out what `nixos-rebuild switch --target-host`
does — build the closure, `nix copy --to ssh://`, `nix-env -p
/nix/var/nix/profiles/system --set`, `switch-to-configuration switch` — so it
works from a build host whose Nix lives in a container.

`mise run deploy` orders it: bootstrap server (`--cluster-init`) → wait for
`/readyz` → remaining servers (joining the bootstrap's IP directly) → wait for
the VIP → agents (joining the VIP). Waits are bounded; they fail rather than hang.

### Cluster wiring

- The k3s join token is **not** in the Nix config. It is generated into
  `secrets/k3s-token` and scp'd to `/var/lib/k3s-token` before the first deploy;
  k3s will not start without it, which is why `deploy` depends on `push-token`.
- kube-vip provides the control-plane VIP, installed via
  `services.k3s.manifests` on the bootstrap server only. Do not use
  systemd-tmpfiles for this — `/var/lib/rancher/k3s/server/manifests` does not
  exist yet when tmpfiles runs on a fresh node, so the rule silently no-ops.
- Remote access is Tailscale as a **subnet router**, not per-node tailnet
  addresses: the three servers advertise `cluster.tailscale.advertise_routes`
  (`10.0.200.0/24`), so an off-LAN kubectl still targets the VIP and stays HA.
  `nix/modules/tailscale.nix` is in the node configs but deliberately *not* in
  the golden image — the image has no identity to log in with, and the closure
  would be pushed to Proxmox for nothing. `useRoutingFeatures = "server"` on
  servers only (it enables IP forwarding); routes go in both `extraUpFlags` and
  `extraSetFlags` or they vanish after the first `tailscale up`. The module sets
  `package = unstable.tailscale`, and that line is **the only consumer of the
  `nixpkgs-unstable` input** in the whole repo — 25.05 ships 1.82.5, which the
  admin console flags as vulnerable. Only the package comes from unstable;
  everything else on the node stays on 25.05. The pre-auth
  key follows the k3s-token pattern: `secrets/tailscale-authkey` →
  `/var/lib/tailscale-authkey`, pushed before `deploy` because
  `tailscaled-autoconnect` runs during activation. **That key must be a tagged
  one** (`tag:k3s`): the tag is what the ACL's `autoApprovers` matches to approve
  `10.0.200.0/24` on its own, and — more importantly — tagged devices have no key
  expiry, where user-owned ones expire together ~180 days after they were
  enrolled and take the subnet route with them. Tags come from the auth key or
  from the admin console, never from the module: `tailscale set` has no
  `--advertise-tags`, so the flag cannot be handled the way routes are. Clients
  still need `--accept-routes`, and `--accept-dns` too if they want MagicDNS
  names like the Grafana Ingress. The tailnet policy file itself is
  `tailscale/policy.hujson` in this repo, applied by a third Terraform root —
  `tailscale/CLAUDE.md`.
- traefik and servicelb are disabled. Traffic enters only through the cloudflared
  tunnel in `apps/`, which dials out and forwards to Services by cluster DNS.
  The tunnel itself — its ingress rules and the CNAMEs pointing at it — is a
  second Terraform root, `terraform/cloudflare/` (`mise run cf:plan` /
  `cf:apply`), documented there.

### Terraform state lives in R2

Both roots — `terraform/proxmox/` and `terraform/cloudflare/`, one per set of
credentials — use the `s3` backend against Cloudflare R2 (`bucket = "terraform"`,
one `key` each). The backend block is deliberately **partial**: `access_key`,
`secret_key` and `endpoints.s3` are absent from it, because a backend block takes
no variables and this repo is public — the endpoint alone carries the account ID.
They come from `secrets/r2.tfbackend`, which `mise run tf:init` / `cf:init` pass
with `-backend-config`. `terraform init` run by hand, without that flag, will
prompt for the missing values and then write them into `.terraform/` — use the
tasks.

The R2 credential is an **R2 API token** (dashboard -> R2 -> Manage API tokens),
not the `cloudflare-api-token` the provider uses; the two are unrelated and
neither works in place of the other. `skip_*` and `use_path_style` are there
because R2 is S3-compatible but not AWS.

Terraform 1.9 is pinned, which predates `use_lockfile` (1.10+), so there is **no
state locking** — two concurrent applies would corrupt state. Single operator, so
this is accepted rather than solved; bumping the pin and setting
`use_lockfile = true` is the fix if that stops being true.

## Where the rest of the docs live

This file covers the cluster as a whole: the pieces below own their own
`CLAUDE.md`, loaded when you work in them.

| directory | what it documents |
|---|---|
| `terraform/proxmox/` | the six VMs, and the Proxmox provider's sharp edges |
| `terraform/cloudflare/` | the cloudflared tunnel, its ingress rules and DNS |
| `tailscale/` | the tailnet policy file and the Terraform root that applies it |
| `apps/` | Flux GitOps, SOPS, image automation |
| `apps/base/monitoring/` | Prometheus + Grafana |
| `apps/base/tailscale-operator/` | the `tailscale` IngressClass and proxy tags |
| `apps/base/loki/` | Loki + Alloy, R2 chunk storage, the edge's push path |
| `apps/base/gatus/` | the tailnet-only status page and what it probes |
| `00-cloud-edge/` | the public Oracle edge: HAProxy, ACME, its own flake |

## Gotchas discovered the hard way

- **The NIC is `eth0`**, not `ens18`. `network.nix` matches `"en* eth*"`; getting
  this wrong strands a node with no route and no SSH, recoverable only from the
  Proxmox console.
- **k3s node names are pinned with `--node-name`.** `networking.hostName` only
  writes `/etc/hostname`, which systemd reads at boot — a `switch` leaves the live
  hostname stale, so without the flag every node registers as `nixos` and the
  second one dies with "duplicate node name found". An activation script also
  writes `/proc/sys/kernel/hostname` so the live name matches immediately.
- **Never pass `--node-label=node-role.kubernetes.io/*`.** kubelet rejects
  self-assigned labels in that namespace and refuses to start. Set roles with
  `kubectl label` instead.
- **Plumbing a package set into `specialArgs` changes nothing on its own.**
  `flake.nix` passed `unstable` to every node, with a comment explaining that
  tailscale comes from it because 25.05's 1.82.5 is vulnerable — but no module
  ever took the argument or set `services.tailscale.package`, so all six nodes
  quietly ran 1.82.5 until the admin console flagged them. Docs describing a fix
  are not the fix. The check is an eval, not a grep:
  `./scripts/nix.sh 'nix eval --raw ".#nixosConfigurations.k3s-server-1.config.services.tailscale.package.version"'`
