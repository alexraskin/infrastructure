# CLAUDE.md

Guidance for Claude Code (claude.ai/code) working in this repository.

## What this is

An HA Kubernetes cluster on **Talos Linux**: 3 control plane nodes (embedded
etcd), 3 workers, 3 tainted database workers, as VMs on one Proxmox host.
Terraform creates the VMs *and* the cluster — Talos takes its whole
configuration through its own API, so there is no second configuration step.
Flux deploys everything in `apps/`. It used to be k3s on NixOS;
`docs/talos-migration.md` records why it is not.

**Explanations belong here, not in code comments.** Inline comments stay to a
line or two — enough to flag the non-obvious at the call site. Background,
tradeoffs and what breaks belong in this file.

## Commands

`mise` runs everything. Three configs: root (cluster), `apps/` (GitOps),
`00-cloud-edge/` (the edge). `mise trust` once per directory.

```bash
mise run preflight       # validate Proxmox token, node, datastores, VM IDs, IPs, capacity
mise run tf:plan|tf:apply    # terraform/proxmox — VMs, machine configs, bootstrap
mise run talosconfig     # write secrets/talosconfig from state
mise run kubeconfig      # write ./kubeconfig, pointed at the VIP
mise run cilium          # install/upgrade the CNI — REQUIRED within ~10min of bootstrap
mise run health|status   # talosctl health; kubectl get nodes + kube-system
mise run upgrade         # talosctl upgrade every node to the pinned talos_version
mise run bootstrap       # tf:apply -> talosconfig -> kubeconfig -> cilium -> status
mise run cf:plan|cf:apply    # terraform/cloudflare — tunnel + DNS (CI does this on main)
mise run ts:plan|ts:apply    # tailscale — the tailnet policy file (CI too)
mise run oci:plan|oci:apply  # terraform/oracle — the CNPG backup bucket
mise run tf:destroy      # DESTRUCTIVE, targeted — see below
mise run reset           # DESTRUCTIVE: talosctl reset every node
```

From `00-cloud-edge/`: `tf:apply`, `install` (nixos-anywhere, one shot, erases
the box), `deploy`, `status`, `secrets:edit`.

There is no test suite. "Does it work" is `mise run preflight`, a `terraform
plan`, then `mise run health` and `mise run status`.

## Source of truth

`terraform/proxmox/cluster.auto.tfvars.json` holds every node IP, VM ID, size,
the VIP, the install disk, and the Talos/Kubernetes versions. It is **JSON on
purpose**: `jq` reads it in shell scripts and Terraform auto-loads it as typed,
validated variables, so there is no second copy. A malformed node fails at
`plan`, not at apply.

Changing cores/memory/disk *or an IP* is a `tf:apply` — the address lives in the
machine config, not in cloud-init.

## The rules that matter

**`mise run tf:destroy` is targeted, and must stay that way.**
`terraform/proxmox/` also owns the PVE host — ACME certificate, storages, the
management bridge. A bare `terraform destroy` there takes the host apart, not
the cluster.

**The bootstrap window is real.** With `cni.name: none`, nodes come up NotReady
and Talos reboots to retry after ~10 minutes. `tf:apply` finishes anyway (the
API server is a static pod on the host network), so the sequence is `tf:apply`
then **`mise run cilium`, promptly**.

**Cilium is bootstrap infrastructure, not a workload.** `helm template | kubectl
apply`, deliberately not a Flux HelmRelease: nothing reconciling from inside the
cluster can install the reason the cluster has a pod network. Three values are
load-bearing and Talos-specific — `k8sServiceHost: localhost` / `k8sServicePort:
7445` (KubePrism, the node-local apiserver LB), `cgroup.autoMount.enabled:
false`, and `SYS_MODULE` dropped from `ciliumAgent`.

**The VIP is Talos', not kube-vip's.** Layer-2, etcd-elected, on the control
plane interfaces only. It is the *Kubernetes* endpoint and never the *Talos*
endpoint — `talos_client_configuration.endpoints` is the three node addresses,
because a cluster broken enough to need `talosctl` is one whose VIP is gone.
In-cluster traffic uses KubePrism on `localhost:7445` instead.

**Talos has no SSH.** Recovery is `talosctl` or the Proxmox console, and
`talosctl` needs `secrets/talosconfig`. Fetch it before you need it.

**kube-proxy is gone for good** (Cilium replaces it), and the service CIDR is
Talos' `10.96.0.0/12`, not k3s' `10.43.0.0/16`. CoreDNS is at `10.96.0.10`.

### Storage is static

Talos ships no provisioner. `apps/base/local-path/` hand-writes a
`no-provisioner` StorageClass plus one **`local`** PV per claim, pinned with
`nodeAffinity`. Three classes; only `nfs` (an LXC, *not* the NAS) provisions on
demand.

**Every PV path is a Talos user volume** declared in `terraform/proxmox/`, so
adding a claim is **two** changes: a PV in `apps/`, and a user volume there — and
the second is a `tf:apply`, not a Flux reconcile. Two Talos facts force this:

- `/var/mnt` is read-only, so a hostPath PV with `DirectoryOrCreate` cannot
  create its own directory.
- kubelet applies `fsGroup` to `local` volumes but **not** hostPath ones, so a
  hostPath PV stays root-owned and every non-root chart fails on it.

### Flux and secrets

**A CRD and a CR using it need separate Kustomizations.** Flux dry-runs the
whole resource set before applying, so a CR whose CRD arrives in the same
Kustomization fails with `no matches for kind`. This is why `cnpg` /
`cnpg-cluster` and `tailscale-operator` / `tailscale-router` are split.

**Image tags are owned by image-automation-controller**, not by hand. Editing a
tag manually is undone within 5 minutes; pin by narrowing the ImagePolicy range.

**One age key opens everything**, kept in 1Password. `apps/` decrypts via the
`sops-age` Secret; the edge decrypts with sops-nix using the same key. Two traps:

- `apps/.sops.yaml` sets `encrypted_regex: ^(data|stringData)$`, so **SOPS only
  works on Kubernetes Secrets** there.
- **`sops` resolves `.sops.yaml` from the working directory, not from the file.**
  Running it from `apps/` against a path in `00-cloud-edge/` picks the wrong
  config, matches nothing, and writes **plaintext** with a `sops:` block that
  makes it look encrypted. Use `mise run secrets:edit` from `00-cloud-edge/`.
- `mise run sops-encrypt <file>` is broken (does not receive its argument). Use
  `cd apps && mise exec -- sops --encrypt --in-place <file>`.

**The 1Password operator is the second way in, not a replacement.**
`apps/base/onepassword/` runs the operator alone — no Connect server — against a
service account token that is itself a `*.sops.yaml`, so SOPS still bootstraps
it and stays the only thing that works on a rebuild. A `OnePasswordItem` names a
vault item and the operator writes the Secret; because the CRD ships with that
HelmRelease, the CRs belong with the consuming app and `dependsOn: [onepassword]`.
`docs/onepassword-operator.md` has the rest, including why no Connect server.

### Terraform state

Five roots, one per credential set, all on the `s3` backend against Cloudflare
R2. Backend blocks are deliberately **partial** — credentials and the endpoint
(which carries the account ID) come from `secrets/r2.tfbackend` via
`-backend-config`, because this repo is public. Use the `*:init` tasks; a bare
`terraform init` prompts and then writes the values into `.terraform/`.

**The cluster PKI is in that state.** `talos_machine_secrets` is a resource, so
machine secrets and the client CA live in R2. Treat it as a secret store, and
keep `secrets/talosconfig` as the copy that matters.

Terraform 1.9 is pinned, which predates `use_lockfile`, so there is **no state
locking**. Single operator, accepted.

**`terraform/cloudflare/` and `tailscale/` read the Proxmox root's state** so the
VIP, subnet and PVE host address are declared once. A `terraform_remote_state`
data source takes no `-backend-config`, so credentials arrive as `AWS_*`
environment variables from `scripts/r2-env.sh` (CI already exported them).
**Outputs reach a consumer only through `apply`, never `plan`** — add an output
and the other roots keep seeing the old state until `tf:apply` runs.

## Gotchas found the hard way

- **A `tf:apply` that changes the user-volume list breaks running pods.** Talos
  reconciles `/var/mnt/*` and resets the mountpoints to `root:root 0755`, but
  kubelet only applies `fsGroup` at pod *start* — so a non-root workload
  silently loses the ability to *create* files while still being able to write
  existing ones. Grafana surfaced it in seconds (sqlite needs a `-journal` file,
  so login 500s); Loki never noticed. Roll every workload holding one of these
  PVs after the apply.
- **A `Retain` PV never rebinds after its claim is deleted.** It goes `Released`
  keeping a `claimRef` to the dead UID, so even an identically-named claim will
  not bind. A HelmRelease whose *install* fails is uninstalled before retry,
  which deletes its PVCs and strands every PV at once. Fix:
  `kubectl patch pv <name> --type=merge -p '{"spec":{"claimRef":null}}'`.
- **Nothing names the NIC.** Machine configs match it with `deviceSelector:
  {driver: virtio_net}` — under NixOS, `eth0` vs `ens18` stranded a node.
- **A privsep Proxmox API token authenticates and then sees nothing.** Proxmox
  filters lists by permission rather than returning 403, so datastores and
  bridges come back as empty arrays. `pveum user token modify <userid> <tokenid>
  --privsep 0`. The provider also ignores `~/.ssh/config` and fails *partway*
  through an apply, after the VMs exist.
- **`proxmox_acme_certificate` needs `force = true`.** PVE will not order over a
  certificate it did not place itself, and fails the apply with `Parameter
  verification failed. (force: Custom certificate exists but 'force' is not
  set.)`. "Custom" means anything at `/etc/pve/nodes/<node>/pveproxy-ssl.pem`
  that ACME did not write — including the installer's self-signed one, so this
  bites on the very first order as well as after any manual cert.
- **Three things the Proxmox token cannot manage at all**: the ACME account,
  feature flags on a privileged container, and individual apt repository lines.
  PVE reserves them for the real `root@pam`, and a token is not it.
- **CNPG backups can fill the database disks.** Once `barmanObjectStore` is set,
  Postgres will not recycle a WAL segment until `archive_command` succeeds — a
  bad credential grows `pg_wal` until the volume is full and Postgres stops.
  Check the `ContinuousArchiving` condition immediately after any change.
  Oracle's S3 also rejects botocore's default `aws-chunked` checksums, which is
  what the two `AWS_*_CHECKSUM_*` values in `spec.env` disable.
- **Traffic reaches Cilium's socket-LB only on locally-originated connections.**
  Forwarded or DNAT'd traffic has no socket, so a ClusterIP is never translated
  on that path and `bpf-lb-external-clusterip` does not change it.
- **Keep `notes_template` on the backup job ASCII.** An em dash fails the apply
  with "Provider produced inconsistent result after apply".
