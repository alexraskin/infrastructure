# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

The repo root is an HA k3s cluster: 3 servers (control plane + embedded etcd) and
3 agents, running as NixOS VMs on a single Proxmox host. Terraform creates the
VMs, NixOS owns everything inside them, Flux deploys workloads from `apps/`.

## Commands

`mise` runs everything. Two separate configs: `mise.toml` at the root (cluster)
and `apps/mise.toml` (GitOps). `mise trust` is needed once per directory.

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
mise run cf:plan        # terraform, from terraform/cloudflare/ (tunnel + DNS)
mise run cf:apply       # same, applied
mise run reset          # DESTRUCTIVE: wipe k3s state cluster-wide (typed confirmation)
```

Validation without touching infrastructure:

```bash
terraform -chdir=terraform/proxmox validate && terraform fmt -recursive terraform/
terraform -chdir=terraform/cloudflare validate
./scripts/nix.sh 'nix eval ".#nixosConfigurations.k3s-server-1.config.networking.hostName"'
cd apps && mise exec -- kustomize build base/alexraskin-com
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
  `extraSetFlags` or they vanish after the first `tailscale up`. The pre-auth
  key follows the k3s-token pattern: `secrets/tailscale-authkey` →
  `/var/lib/tailscale-authkey`, pushed before `deploy` because
  `tailscaled-autoconnect` runs during activation. The route needs one-time
  approval in the Tailscale admin console, and clients need `--accept-routes`.
- traefik and servicelb are disabled. Traffic enters only through the cloudflared
  tunnel in `apps/`, which dials out and forwards to Services by cluster DNS.
  The tunnel itself — its ingress rules and the CNAMEs pointing at it — is a
  second Terraform root, `terraform/cloudflare/` (`mise run cf:plan` /
  `cf:apply`), covered below.

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

### terraform/cloudflare/ — the tunnel and DNS

A second root on purpose: different credentials, different blast radius. A DNS
change should not plan against the VMs. State holds the tunnel token in
cleartext, so the R2 bucket must stay private.

Auth is `CLOUDFLARE_API_TOKEN`, read from `secrets/cloudflare-api-token` by the
`cf:*` tasks — never a tfvars entry, never in state. The token needs exactly
three rows on a *custom* token: Account/Cloudflare Tunnel/Edit, Zone/DNS/Edit,
Zone/Zone/Read. DNS/Edit does **not** imply Zone/Read, and a token missing it
gets an empty zone list rather than a 403 — the same permission-filtering
behaviour as a privsep Proxmox token.

It **adopts** the pre-existing tunnel rather than creating one: `imports.tf`
holds `import` blocks for the tunnel, its config and every CNAME, so the
connector token already in `apps/base/cloudflared/token.sops.yaml` stays valid
and cloudflared never restarts. A correct plan is "N to import, 0 to add, 0 to
destroy". If it wants to *create* the tunnel, an import block is missing or
`tunnel_id` is wrong — applying then builds a second tunnel and moves the CNAMEs
to one with no connectors, which is the outage case.

`var.ingress` is the whole tunnel config. Order only matters for overlapping
rules (paths, wildcards), so a plan that merely reorders distinct hostnames is
inert; a rule that disappears from the list is deleted on apply. The catch-all
is appended automatically — Cloudflare requires the list to end with a rule that
has no hostname. `origin_request = {} -> null` on an adopted config is the
provider's round-trip noise, not a change. The config resource has no DELETE
endpoint, hence the standing "cannot be destroyed" warning.

Zones are matched by longest suffix, so `go.example.com` finds `example.com` in
`var.zones` with no per-entry zone. Only externally reachable apps need an entry
at all — `lhbotgo` has none, it dials Discord out.

One-time recipes, kept here rather than as tasks nobody runs twice:

```bash
# account + tunnel ID, without the dashboard: the connector token is base64 JSON
# {"a": account, "t": tunnel, "s": secret}
cd apps && SOPS_AGE_KEY_FILE=../secrets/age.key sops -d base/cloudflared/token.sops.yaml \
  | sed -n 's/.*token: //p' | base64 -d | jq '{account: .a, tunnel: .t}'

# zone name -> zone ID
curl -fsS "https://api.cloudflare.com/client/v4/zones?per_page=50" \
  -H "Authorization: Bearer $(cat secrets/cloudflare-api-token)" \
  | jq -r '.result[] | "\(.name) \(.id)"'

# the tunnel's live ingress rules, to transcribe into tfvars
curl -fsS "https://api.cloudflare.com/client/v4/accounts/$ACCT/cfd_tunnel/$TUN/configurations" \
  -H "Authorization: Bearer $(cat secrets/cloudflare-api-token)" | jq '.result.config.ingress'

# import blocks for CNAMEs that already exist
curl -fsS "https://api.cloudflare.com/client/v4/zones/$ZONE/dns_records?type=CNAME&per_page=100" \
  -H "Authorization: Bearer $(cat secrets/cloudflare-api-token)" \
  | jq -r --arg z "$ZONE" '.result[] | select(.content | endswith(".cfargotunnel.com"))
      | "import {\n  to = cloudflare_dns_record.tunnel[\"\(.name)\"]\n  id = \"\($z)/\(.id)\"\n}"'
```

If the tunnel is ever replaced, the new token has to reach the cluster:
`terraform output -raw tunnel_token` into a copy of
`apps/base/cloudflared/token.example.yaml`, then `mise run sops-encrypt`.

### apps/ — Flux GitOps

`apps/clusters/k3s/apps.yaml` lists what Flux reconciles; `apps/base/*` holds the
manifests. Secrets are SOPS-encrypted to an age key in `secrets/age.key`
(gitignored, outside `apps/`) and decrypted in-cluster via the `sops-age` secret.
The repo is public — encrypted `*.sops.yaml` is meant to be committed; the age
key is not. `flux bootstrap` pushes commits, so do not run it casually.

Image tags in `apps/base/*/deployment.yaml` are **owned by
image-automation-controller**, not by hand: `apps/base/image-automation/` scans
GHCR, picks the newest semver tag and pushes a commit rewriting the line marked
`# {"$imagepolicy": "flux-system:<app>"}`. Editing a tag manually is undone on
the next 5m scan; pin by narrowing the ImagePolicy range instead. This is why
the GitRepository is SSH with the `flux-git-auth` deploy key (`mise run
git-deploy-key`, needs write access on GitHub) rather than anonymous HTTPS, and
why `install` passes `--components-extra=image-reflector-controller,image-automation-controller`.
Only our own images are automated; `cloudflared` is still pinned by hand.

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
- **The Proxmox provider ignores `~/.ssh/config`** and needs either
  `pve_ssh_private_key_path` or a loaded ssh-agent. Missing credentials fail
  *partway* through apply, after the VMs exist.
- **A privsep API token authenticates and then sees nothing** — Proxmox filters
  lists by permission rather than returning 403, so datastores and bridges come
  back as empty arrays. `pveum user token modify <userid> <tokenid> --privsep 0`
  (two separate arguments, not `user!token`).
- `iso` content always uploads over the PVE HTTP API — no SSH, no resume. For a
  slow link use `mise run push-image root@<pve-host>` (rsync, resumable) plus
  `upload_image = false`.
- `disk[0].file_id` is in `lifecycle.ignore_changes`, so rebuilding the image does
  not recreate running VMs. Node changes ship via `deploy`, never Terraform.
