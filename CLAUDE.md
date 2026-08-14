# CLAUDE.md

Guidance for Claude Code (claude.ai/code) working in this repository.

## What this is

An HA Kubernetes cluster on **Talos Linux**: 3 control plane nodes (embedded
etcd), 3 workers, 3 tainted database workers, as VMs on one Proxmox host
(`bunker`). Terraform creates the VMs *and* the cluster — Talos takes its whole
configuration through its own API, so there is no second configuration step.
Flux deploys everything in `apps/`.

## Where things live

| path | owns |
| --- | --- |
| `00-global/` | the Object Storage bucket every root keeps its Terraform state in, and the `terraform-ci` user CI authenticates as |
| `terraform/proxmox/` | the nine VMs, the cluster, **and** the PVE host itself (ACME cert, storages, management bridge, nightly vzdump, the NFS LXC) |
| `terraform/cloudflare/` | tunnel + DNS |
| `terraform/oracle/` | the CNPG backup bucket |
| `tailscale/` | the tailnet policy file |
| `01-cloud-edge/` | the NixOS edge box — its own flake, mise config and Terraform root |
| `apps/base/` | one directory per workload, deployed by Flux |
| `apps/clusters/talos/` | the Flux Kustomizations that point at `apps/base/` |
| `talos/cilium-values.yaml` | CNI values, applied outside Flux |
| `scripts/` | preflight, backend init, the root list both CI and mise read |
| `docs/` | runbooks (PVE 8→9, CNPG backups, the R2→OCI state move) |
| `secrets/` | gitignored — `talosconfig`, `oci.env`, `oci_api_key.pem`, the age key |
| `01-pve/plex/` | a docker-compose stack, not deployed anywhere right now — Plex runs on the workstation, and Docker is deliberately off the PVE host |

## Commands

`mise` runs everything. Three configs: root (cluster), `apps/` (GitOps),
`01-cloud-edge/` (the edge). `mise trust` once per directory.

```bash
mise run preflight       # validate Proxmox token, node, datastores, VM IDs, IPs, capacity
mise run tf:plan|tf:apply    # terraform/proxmox — VMs, machine configs, bootstrap
mise run talosconfig     # write secrets/talosconfig from state
mise run kubeconfig      # write ./kubeconfig, pointed at the VIP
mise run cilium          # install/upgrade the CNI — REQUIRED within ~10min of bootstrap
mise run health|status   # talosctl health; kubectl get nodes + kube-system
mise run upgrade         # talosctl upgrade every node to the pinned talos_version
mise run upgrade-k8s     # kubernetes version, separately
mise run bootstrap       # tf:apply -> talosconfig -> kubeconfig -> cilium -> status
mise run cf:plan|cf:apply    # terraform/cloudflare — tunnel + DNS (CI does this on main)
mise run ts:plan|ts:apply|ts:status   # tailscale policy (CI too)
mise run oci:plan|oci:apply|oci:creds # terraform/oracle
mise run global:plan|global:apply     # 00-global — the state bucket itself
mise run global:backend|global:ci-creds   # backend coordinates; the CI user's OCI_* secrets
mise run nfs:status      # the NFS LXC
mise run tf:destroy      # DESTRUCTIVE, and targeted on purpose — see the vault
mise run reset           # DESTRUCTIVE: talosctl reset every node
```

From `01-cloud-edge/`: `tf:apply`, `install` (nixos-anywhere, one shot, erases
the box), `deploy`, `status`, `secrets:edit`.

There is no test suite. "Does it work" is `mise run preflight`, a `terraform
plan`, then `mise run health` and `mise run status`. `mise run tflint` and
`mise run tfdocs` cover every Terraform root at once, which is also what
`.github/workflows/terraform_checks.yml` runs on a PR; `scripts/tf-roots.sh` is
the list both read.

**Every root initialises itself.** `scripts/tf-init.sh` checks the secrets the
root needs and inits it against R2, but returns immediately once
`.terraform/terraform.tfstate` exists — so `plan` and `apply` call it every time
without a registry round trip, and `*:init` passes `--force` when providers
should actually be re-resolved.

## Source of truth

`terraform/proxmox/cluster.auto.tfvars.json` holds every node IP, VM ID, size,
the VIP, the install disk, and the Talos/Kubernetes versions. It is **JSON on
purpose**: `jq` reads it in shell scripts and Terraform auto-loads it as typed,
validated variables, so there is no second copy. A malformed node fails at
`plan`, not at apply.

Changing cores/memory/disk *or an IP* is a `tf:apply` — the address lives in the
machine config, not in cloud-init.

## How the pieces fit

**Cilium is bootstrap infrastructure, not a workload.** `helm template | kubectl
apply`, deliberately not a Flux HelmRelease: nothing reconciling from inside the
cluster can install the reason the cluster has a pod network. Three values are
load-bearing and Talos-specific — `k8sServiceHost: localhost` / `k8sServicePort:
7445` (KubePrism, the node-local apiserver LB), `cgroup.autoMount.enabled:
false`, and `SYS_MODULE` dropped from `ciliumAgent`.

**The VIP is Talos', not kube-vip's.** Layer-2, etcd-elected, on the control
plane interfaces only. It is the *Kubernetes* endpoint and never the *Talos*
endpoint — `talos_client_configuration.endpoints` is the three node addresses.
In-cluster traffic uses KubePrism on `localhost:7445` instead.

**kube-proxy is gone for good** (Cilium replaces it), and the service CIDR is
Talos' `10.96.0.0/12`, not k3s' `10.43.0.0/16`. CoreDNS is at `10.96.0.10`.

**Talos has no SSH.** Recovery is `talosctl` or the Proxmox console, and
`talosctl` needs `secrets/talosconfig`. Fetch it before you need it.

### Storage is static

Talos ships no provisioner. `apps/base/local-path/` hand-writes a
`no-provisioner` StorageClass plus one **`local`** PV per claim, pinned with
`nodeAffinity`. Three classes; only `nfs` (an LXC, *not* the NAS) provisions on
demand.

**Every PV path is a Talos user volume** declared in `terraform/proxmox/`, so
adding a claim is **two** changes: a PV in `apps/`, and a user volume there — and
the second is a `tf:apply`, not a Flux reconcile.

### Flux and secrets

Each directory under `apps/base/` gets a Kustomization in
`apps/clusters/talos/apps.yaml`. **A CRD and a CR using it need separate
Kustomizations** — which is why `cnpg` / `cnpg-cluster` and `tailscale-operator`
/ `tailscale-router` are split.

**Image tags are owned by image-automation-controller**, not by hand. Pin by
narrowing the ImagePolicy range.

**SOPS is the only way secrets reach the cluster.** One age key opens
everything, kept in 1Password (the password manager — there is no operator in
the cluster any more). `apps/` decrypts via the `sops-age` Secret; the edge
decrypts with sops-nix using the same key. `apps/.sops.yaml` sets
`encrypted_regex: ^(data|stringData)$`, so SOPS only works on Kubernetes
Secrets there. Use `mise run sops-encrypt <file>` and `sops-edit` from `apps/`,
and `mise run secrets:edit` from `01-cloud-edge/`.

Every app that needs a secret carries a `*.sops.yaml` next to its manifests, an
`*.example.yaml` beside it showing the shape, and a `decryption` block on its
Kustomization in `apps/clusters/talos/apps.yaml`.

### Terraform state

Six roots, one per credential set, all on the `oci` backend against one Object
Storage bucket — `infrastructure-terraform-state`, one object per root. That backend locks:
it PUTs `<key>.lock` with `If-None-Match: *`, which Object Storage refuses if
the object is already there. It needs **Terraform 1.12+**, which is why
`mise.toml` pins 1.15 and `required_version` is `>= 1.12`.

Backend blocks are deliberately **partial** — bucket and key are in the config,
the namespace and the API signing key are credentials and come from
`secrets/oci.env` as `-backend-config` flags assembled by `scripts/tf-init.sh`,
because this repo is public. `auth=APIKey` is one of those flags and has to
stay one: in the backend block it makes every request 404, and without it the
backend never reaches the API key. That script also retries the spurious
`BucketNotFound` Object Storage returns now and then, and
`OCI_SDK_DEFAULT_RETRY_ENABLED` is set for the same reason. CI runs `plan` and
`apply` through `scripts/tf-run.sh`, which retries the same two errors —
`BucketNotFound` and the `NotAuthenticated` a freshly created API key returns
while it propagates — and refuses to retry once an apply has started changing
things.

**CI does not use the API key in `secrets/oci.env`.** `00-global/iam.tf` creates
a `terraform-ci` user whose policy is `read buckets` + `manage objects` on the
state bucket and nothing else; its signing key is generated by Terraform, so the
private half lives in that state. `mise run global:ci-creds` prints the six
`OCI_*` values the `cloudflare` and `tailscale` environments need. Use the `*:init` tasks; a bare `terraform init`
prompts and then writes the values into `.terraform/`.

**`00-global/` owns that bucket**, and its own state lives in it. That is
circular, so creating it again would mean moving `backend.tf` aside, applying on
local state and migrating in — a one-off with no task behind it.
`docs/terraform-state-migration.md` has that path, and the record of the R2 move.

**The cluster PKI is in that state.** `talos_machine_secrets` is a resource, so
machine secrets and the client CA live in the bucket. Treat it as a secret
store, and keep `secrets/talosconfig` as the copy that matters.

**`terraform/cloudflare/` and `tailscale/` read the Proxmox root's state** so the
VIP, subnet and PVE host address are declared once. A `terraform_remote_state`
data source takes no `-backend-config`, so its credentials are ordinary
variables — `TF_VAR_oci_*` from `scripts/oci-env.sh`, and from repository
secrets in CI.

## Conventions

**Explanations do not go in code comments, and they do not go here.** Inline
comments stay to a line or two — enough to flag the non-obvious at the call
site. This file covers layout and setup only.

**Everything learned the hard way lives in the Obsidian vault**, under
`Talos Homelab/` — one note per subsystem, plus `Talos Gotchas Index.md`
grouping every failure mode by what you were doing when it bit. Read it before
changing anything load-bearing, and write new findings back to it: the detail
into the subsystem note, a bullet into the index linking there.
