# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

The repo root is an HA Kubernetes cluster on **Talos Linux**: 3 control plane
nodes (embedded etcd), 3 workers and 3 tainted database workers, running as VMs
on a single Proxmox host. Terraform creates the VMs *and* the cluster — Talos
takes its whole configuration through its own API, so there is no second
configuration-management step. Flux deploys workloads from `apps/`.

It used to be k3s on NixOS. `docs/talos-migration.md` records why it is not.

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
mise run preflight      # validate Proxmox API token, node, datastores, VM IDs, IPs, SSH, capacity
mise run tf:plan        # terraform, from terraform/proxmox/
mise run tf:apply       # VMs, machine configs, bootstrap — the whole cluster
mise run talosconfig    # write secrets/talosconfig from Terraform state
mise run kubeconfig     # write ./kubeconfig, pointed at the VIP
mise run cilium         # install/upgrade the CNI — REQUIRED within ~10min of bootstrap
mise run health         # talosctl health
mise run status         # kubectl get nodes + kube-system pods
mise run upgrade        # talosctl upgrade every node to the pinned talos_version
mise run upgrade-k8s    # talosctl upgrade-k8s to the pinned kubernetes_version
mise run ts:status      # the in-cluster subnet router and the operator's proxies
mise run ts:plan        # terraform, from tailscale/ (the tailnet policy file)
mise run ts:apply       # same, applied — CI does this on push to main
mise run cf:plan        # terraform, from terraform/cloudflare/ (tunnel + DNS)
mise run cf:apply       # same, applied — CI does this on push to main
mise run bootstrap      # tf:apply -> talosconfig -> kubeconfig -> cilium -> status
mise run tf:destroy     # DESTRUCTIVE: the VMs only, targeted (see below)
mise run reset          # DESTRUCTIVE: talosctl reset every node (typed confirmation)
```

From `00-cloud-edge/` (its own mise config, still NixOS):

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
./scripts/nix.sh 'nix eval "path:./00-cloud-edge#nixosConfigurations.cloud-edge.config.system.build.toplevel.drvPath"'
cd apps && mise exec -- kustomize build base/alexraskin-com
cd apps && mise exec -- kustomize build base/monitoring
cd apps && mise exec -- kustomize build base/local-path
cd apps && mise exec -- kustomize build base/tailscale-operator
cd apps && mise exec -- kustomize build base/tailscale-router
cd apps && mise exec -- kustomize build base/loki && mise exec -- kustomize build base/alloy
```

There is no test suite. "Does it work" means `mise run preflight`, a `terraform
plan`, and finally `mise run health` and `mise run status`.

## Architecture

### terraform/proxmox/cluster.auto.tfvars.json is the single source of truth

What used to be `hosts.json` at the repo root is now a **Terraform variables
file**: `cluster` and `nodes` are declared in `variables.tf` with real types and
validations, and `cluster.auto.tfvars.json` is auto-loaded because of the
`.auto.tfvars.json` suffix. No `jsondecode(file(...))`, and a malformed node now
fails at `terraform plan` instead of at apply.

**It is JSON, not HCL, on purpose.** `jq` still reads it, so `scripts/preflight.sh`
and the `upgrade` / `reset` mise tasks work from exactly the same file Terraform
does — an HCL `.tfvars` would have needed a second copy of the node list.

It is tracked in git; `.gitignore` excludes the literal name `terraform.tfvars`
(credentials) and nothing else in that directory. Node IPs, VM IDs, sizes, the
VIP, the install disk, the Talos and Kubernetes versions and the image-factory
extension list all live there. Changing cores/memory/disk is a `tf:apply`;
changing an IP is a `tf:apply` too, because the address is in the machine config
rather than in cloud-init.

### One apply, no second phase

There is no golden image and no deploy step. `tf:apply`:

1. builds the **image factory schematic** from `cluster.extensions`, resolves
   the ISO URL, and downloads it to the Proxmox ISO store,
2. creates the VMs — blank disk, ISO in the CD-ROM, no cloud-init drive,
3. applies a per-node machine configuration over the Talos API,
4. bootstraps etcd on `cluster.bootstrap` and pulls out the kubeconfig.

`machine.install.image` points back at the same schematic ID: the installed
system has to carry the extensions the ISO booted with, or the qemu guest agent
vanishes on first reboot.

### The bootstrap window is real

With `cluster.network.cni.name: none`, nodes come up **NotReady** and Talos
reboots to retry after roughly ten minutes. `tf:apply` still finishes — the API
server is a static pod on the host network and the kubeconfig comes over the
Talos API — so the sequence is `tf:apply` then **`mise run cilium`, promptly**.
Missing the window is not damaging, just a reboot loop until the CNI lands.

### Cilium is bootstrap infrastructure, not a workload

`talos/cilium-values.yaml` + `mise run cilium` (`helm template | kubectl
apply`). It is deliberately **not** a Flux HelmRelease: nothing that reconciles
from inside the cluster can install the reason the cluster has a pod network.
Flux also cannot adopt helm-templated resources without ownership conflicts, so
there is exactly one owner. Upgrades are a bump of `CILIUM_VERSION` in
`mise.toml` and a re-run.

Three values are load-bearing and all three are Talos-specific: `k8sServiceHost:
localhost` / `k8sServicePort: 7445` (KubePrism, the node-local apiserver load
balancer — this is what lets a CNI that needs the API server start before there
is a pod network), `cgroup.autoMount.enabled: false` (Talos already mounts
cgroupv2 and bpffs), and `SYS_MODULE` dropped from `ciliumAgent` (Talos does not
let workloads load kernel modules).

### The VIP is Talos', not kube-vip's

`machine.network.interfaces[].vip.ip` on the control plane nodes only. It is
layer-2 and etcd-elected, so it needs the three CPs on the same switched
network — they are — and it only answers once etcd is healthy.

- **It is the Kubernetes endpoint, never the Talos endpoint.**
  `data.talos_client_configuration.endpoints` is the three node addresses on
  purpose: the VIP is bound to etcd and apiserver health, and a cluster broken
  badly enough to need `talosctl` is exactly a cluster whose VIP is gone.
- **In-cluster traffic does not use it.** kubelet, Cilium and everything else on
  the node talk to KubePrism on `localhost:7445`.
- Failover is near-instant on a graceful shutdown and up to a minute on a hard
  failure, which is etcd's election timeout doing its job.

### The db workers

Three nodes labelled `dedicated=database` and tainted
`dedicated=database:NoSchedule` via `machine.kubelet.extraArgs`
(`register-with-taints`) — nothing schedules there without a toleration and a
selector. Each has a second Proxmox disk claimed by a `UserVolumeConfig`
document, which Talos partitions, labels `u-db` and mounts at **`/var/mnt/db`**.
That path survives a reinstall or `talosctl upgrade --wipe`; `/var` itself, on
the EPHEMERAL partition, does not. The `db-local` StorageClass in
`apps/base/local-path/` is what claims it.

### Three StorageClasses, and only one provisions

| class | backing | shape |
|---|---|---|
| `local-path` | a Talos `directory` user volume per claim, on the EPHEMERAL partition | static, node-pinned, `claimRef`-reserved |
| `db-local` | the db nodes' second disk, a real partition at `/var/mnt/db` | static, node-pinned, claimed by CNPG |
| `nfs` | the LXC in `terraform/proxmox/nfs.tf` | dynamic, RWX, not node-pinned |

`nfs` is **not** the NAS — the cluster subnet has no route to it. See
`apps/base/csi-driver-nfs/CLAUDE.md`.

### Storage is static

Talos ships no StorageClass and no provisioner; k3s' `local-path` was a freebie
that is now hand-written in `apps/base/local-path/` — a `no-provisioner`
StorageClass with `WaitForFirstConsumer`, plus one **`local`** PV per claim,
pinned with `nodeAffinity`. **A new PVC needs a new PV committed first**;
nothing provisions on demand. PodSecurity is not in the way — a pod spec only
ever names the PVC.

**Every PV path is a Talos user volume**, declared in
`terraform/proxmox/talos.tf` and mounted at `/var/mnt/<name>`:

- one `volumeType: directory` volume per claim (`prometheus`, `grafana`,
  `loki`) on every non-control-plane node, carved out of the EPHEMERAL
  partition, needing no extra disk;
- `/var/mnt/db`, a `volumeType: disk` volume on the db nodes — a real partition
  on their second disk.

So adding a claim is **two** changes: a PV here, and a user volume there. The
volume is a `tf:apply`, not a Flux reconcile.

Two Talos facts make that the only shape that works, and both were learned by
watching it fail:

- **`/var/mnt` is read-only.** A `hostPath` PV with `DirectoryOrCreate` cannot
  make its own directory — kubelet fails with `mkdir /var/mnt/…: read-only file
  system` and the pod sits in ContainerCreating forever.
- **kubelet applies `fsGroup` to `local` volumes but not to `hostPath` ones.** A
  hostPath PV stays root-owned, so every chart running as a non-root uid fails
  on it: Prometheus exits with `open /prometheus/queries.active: permission
  denied`. This is why one shared parent directory is not enough either — a
  `local` PV binds a directory, and two claims cannot share one.

### Tailnet access is the operator's job now

The nodes are not on the tailnet at all — Talos has no systemd unit to run
tailscaled in, and the subnet-router model went with it.

- **`apps/base/tailscale-router/`** holds a `Connector` advertising
  `10.0.200.0/24`, so off-LAN kubectl still reaches the VIP. This is circular
  and accepted: the route into the cluster's subnet lives in the cluster. On-LAN
  and the Proxmox console are the break-glass path.
- **`apps/base/gatus/egress.yaml`** holds egress proxies for the two off-cluster
  probes. Under k3s those dialled tailnet addresses directly, because pod egress
  was SNAT'd to the node's tailnet address; there is no such path now.
- The ACL follows: `tag:k3s` is gone, `tag:k8s-router` owns the route in
  `autoApprovers`, and the gatus grants are `src: tag:k8s`.
  `tailscale/policy.hujson`, applied by its own Terraform root.
- traefik and servicelb were k3s' to disable; Talos ships neither. Traffic still
  enters only through the cloudflared tunnel in `apps/`, whose ingress rules and
  CNAMEs are `terraform/cloudflare/`.

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

**The cluster PKI is in that state.** `talos_machine_secrets` is a resource, so
the machine secrets and the client CA live in R2 exactly like the ACME plugin
token does. Treat R2 state as a secret store; keep `secrets/talosconfig` as the
copy that matters if state is ever lost.

Terraform 1.9 is pinned, which predates `use_lockfile` (1.10+), so there is **no
state locking** — two concurrent applies would corrupt state. Single operator, so
this is accepted rather than solved; bumping the pin and setting
`use_lockfile = true` is the fix if that stops being true.

## Where the rest of the docs live

This file covers the cluster as a whole: the pieces below own their own
`CLAUDE.md`, loaded when you work in them.

| directory | what it documents |
|---|---|
| `terraform/proxmox/` | the nine VMs, the Talos resources, the nightly vzdump job, and the Proxmox provider's sharp edges |
| `terraform/cloudflare/` | the cloudflared tunnel, its ingress rules and DNS |
| `tailscale/` | the tailnet policy file and the Terraform root that applies it |
| `apps/` | Flux GitOps, SOPS, image automation |
| `apps/base/monitoring/` | Prometheus + Grafana |
| `apps/base/tailscale-operator/` | the `tailscale` IngressClass and proxy tags |
| `apps/base/loki/` | Loki + Alloy, R2 chunk storage, the edge's push path |
| `apps/base/gatus/` | the tailnet-only status page and what it probes |
| `apps/base/cnpg/` | CloudNativePG: the operator and the three-instance cluster on the db nodes |
| `apps/base/csi-driver-nfs/` | RWX storage, and why it is not the NAS |
| `00-cloud-edge/` | the public Oracle edge: HAProxy, ACME, its own flake |
| `docs/talos-migration.md` | how this stopped being k3s on NixOS |

## Gotchas discovered the hard way

- **`mise run tf:destroy` is targeted, and has to stay that way.**
  `terraform/proxmox/` owns the PVE host as well as the VMs — the ACME
  certificate, the NFS storages, the management bridge. A bare `terraform
  destroy` in that directory takes the host apart, not the cluster.
- **Nothing names the NIC.** The machine config matches it with
  `deviceSelector: {driver: virtio_net}`. Under NixOS this was `eth0` vs `ens18`
  and getting it wrong stranded a node with no route and no SSH; a selector
  removes the question. Talos would also have no SSH to recover over.
- **Talos has no SSH.** Recovery is `talosctl` or the Proxmox console, and
  `talosctl` needs `secrets/talosconfig`. Fetch it (`mise run talosconfig`)
  before you need it.
- **kube-proxy is gone for good.** `kubeProxy.enabled: false` in the monitoring
  chart is permanent, not a workaround — Cilium replaces it, and a ServiceMonitor
  for it would sit DOWN forever.
- **The service CIDR moved.** Talos defaults to `10.96.0.0/12`, where k3s used
  `10.43.0.0/16`; CoreDNS is at `10.96.0.10`. Anything with a hard-coded cluster
  IP — the gatus DNS probe was the only one — has to move with it.
- **Adding a PVC means adding a PV.** See "Storage is static" above. The symptom
  is a pod Pending forever on a claim that never binds.
- **A `Retain` PV never rebinds after its claim is deleted.** It goes `Released`
  and keeps a `claimRef` to the dead PVC's UID, so even a new claim of the
  identical name will not bind — the pod stays Pending with "didn't find
  available persistent volumes to bind". This is not hypothetical: a HelmRelease
  whose *install* fails is uninstalled before retry (`install.remediation`), and
  Helm deletes the PVCs it created on the way out, stranding all three PVs at
  once. Recovery is to clear the reference:
  `kubectl patch pv <name> --type=merge -p '{"spec":{"claimRef":null}}'`.
- **A `tf:apply` that changes the user-volume list breaks running pods.**
  Talos reconciles `/var/mnt/*` when the machine config changes and resets the
  mountpoint directories to `root:root 0755`. kubelet applies `fsGroup` to a
  `local` volume **only when the pod starts**, so nothing puts the ownership
  back and a non-root workload silently loses the ability to *create* files in
  its volume root — it can still write files that already exist, which is why
  this does not look like a permissions failure. Grafana surfaced it within
  seconds (sqlite needs a `-journal` file per write transaction, so login
  returns a 500 while the page still loads); Loki did not notice at all,
  because it only writes inside `wal/` and `chunks/`, whose ownership the
  reconcile leaves alone. The fix is to roll every workload holding one of
  these PVs after the apply — the chart's chown initContainer and kubelet's
  fsGroup both run again on start:

  ```bash
  kubectl -n monitoring rollout restart deploy/kube-prometheus-stack-grafana
  kubectl -n monitoring rollout restart sts/prometheus-kube-prometheus-stack-prometheus
  kubectl -n logging rollout restart sts/loki
  ```

- **`mise run cilium` is not optional and not deferrable.** Ten minutes after
  bootstrap, nodes start rebooting to retry.
- **The backend key moved** from `promox-k3-nix/` to `talos-proxmox/` at the
  Talos rebuild. `terraform init` notices and offers to migrate; take it. Refuse,
  and the root starts from empty state — which does not just forget the VMs, it
  forgets the eight *adopted* host resources (ACME plugin and certificate, the
  two storages, the NFS exports, the bridge, the apt repository, the backup job)
  and the next apply tries to create things that already exist. Re-importing them
  by hand is the recovery, and `terraform/proxmox/CLAUDE.md` lists the ID shapes.
