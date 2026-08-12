# k3s-on-NixOS → Talos Linux

The plan this migration was executed from, kept for the reasoning rather than
as a checklist. What the cluster *is* now lives in the root `CLAUDE.md`.

## Why

The cluster was six NixOS VMs running k3s: a golden qcow2 built by
nixos-generators, per-node `nixosConfigurations`, `scripts/deploy-node.sh`
pushing closures over SSH, kube-vip for the control-plane VIP, and tailscaled on
every node as a subnet router. A lot of machinery whose only product is a
Kubernetes node.

Talos replaces all of it with one machine config document applied by the
`siderolabs/talos` Terraform provider. `terraform apply` went from "creates six
VMs" to "creates nine VMs and a bootstrapped cluster". `00-cloud-edge/` stays
NixOS and was not touched.

## Decisions

| | |
|---|---|
| Cutover | In-place. Same VM IDs, same IPs, cluster destroyed and rebuilt. |
| CNI | Cilium, `cni: none` + `proxy.disabled`, kube-proxy replacement over KubePrism. |
| Tailscale | Dropped from the nodes. Everything tailnet goes through the operator. |
| Storage | Static `local-path`, no provisioner, hand-written PVs. |
| Topology | 3 control plane, 3 workers, 3 tainted db workers with a second disk. |

Versions: Talos v1.13.8 (Kubernetes 1.36.2), Cilium 1.20.0 — 1.20 is the line
e2e-tested against 1.36, which ruled out the 1.18 the plan originally named.

## What changed, file by file

- **`hosts.json` → `terraform/proxmox/cluster.auto.tfvars.json`** — nine nodes
  (`talos-cp-{1,2,3}` .41–.43, `talos-worker-*` .51–.53, `talos-db-*` .61–.63
  with `data_disk`), Talos/Kubernetes versions, `install_disk`, factory
  `extensions`. `kube_vip_version` and the `tailscale` block are gone. It is a
  typed Terraform variable now rather than a file read with `jsondecode`, and
  stayed JSON so `jq` consumers did not need a second copy.
- **`terraform/proxmox/image.tf`** — factory schematic → ISO → Proxmox download.
- **`terraform/proxmox/main.tf`** — VMs with no cloud-init, a blank system disk,
  an optional `scsi1` for the db nodes, booting the factory ISO.
- **`terraform/proxmox/talos.tf`** — secrets, per-node machine configs, apply,
  and the sleep before bootstrap. The role patches, the bootstrap and the
  kubeconfig are in `talos-controlplane.tf`, `talos-workers.tf` and
  `talos-db-worker.tf`.
- **`talos/cilium-values.yaml`** + `mise run cilium`.
- **`apps/base/local-path/`** — two StorageClasses and the static PVs.
- **`apps/base/tailscale-router/`** — the Connector that replaces the node
  subnet router.
- **`apps/base/gatus/egress.yaml`** — operator egress proxies for the two
  tailnet probes.
- **`apps/clusters/k3s/` → `apps/clusters/talos/`**.
- **Deleted** — `flake.nix`, `flake.lock`, `nix/`, `scripts/deploy-node.sh`.
  `scripts/nix.sh` stays; `00-cloud-edge/` still uses it, and its untracked-file
  guard now watches that directory instead of the deleted root flake.

## Cutover order

1. Back up anything node-local worth keeping — Grafana's DB, the gatus sqlite,
   Prometheus' TSDB. The PVs do not survive.
2. Commit everything. Nothing here evaluates untracked files.
3. `mise run ts:apply` — policy first, so `autoApprovers` is ready for the
   Connector's `tag:k8s-router`. Then delete the old cluster's devices in the
   admin console; a stale device holding a hostname pushes the new one to
   `name-1`.
4. `mise run tf:destroy` — **targeted**, and it has to stay that way: this root
   also owns the PVE host's ACME certificate, its NFS storages and the
   management bridge. A bare `terraform destroy` would take those too.
5. `mise run tf:apply`. The backend key changed to `talos-proxmox/` in the same
   pass, so the first `tf:init` offers a state migration — accept it, or the
   eight adopted PVE host resources have to be re-imported.
6. `mise run talosconfig && mise run kubeconfig && mise run cilium`, inside ten
   minutes of bootstrap.
7. Re-bootstrap Flux against `apps/clusters/talos`, re-apply the SOPS age key
   and `flux-git-auth`.

## Verification

```bash
mise run preflight
mise run tf:plan
mise run health
talosctl -n 10.0.200.41 get members            # nine, and only nine
talosctl -n 10.0.200.61 get volumestatus u-db  # and: get mountstatus u-db
kubectl get nodes -o wide
kubectl get nodes -l dedicated=database
kubectl get pvc -A                             # every claim Bound
flux get all -A
```

End to end: `ping 10.0.200.40` while rebooting `talos-cp-1` (the VIP should move
within ~60s), `curl` a cloudflared-fronted site, confirm the edge's journal is
still landing in Loki, and check the gatus page's tailnet probes are green
through the new egress proxies.

## Known costs

- **All PV data was lost at the cutover.** Loki's chunks are in R2 and survived;
  Prometheus history, Grafana's DB and the gatus sqlite did not.
- **The cluster PKI is in Terraform state in R2**, the same posture already
  accepted for the Cloudflare ACME token. `secrets/talosconfig` is the copy that
  matters if state is lost.
- **The subnet route now lives in the cluster it routes to.** Off-LAN kubectl
  depends on the cluster being up; on-LAN and the Proxmox console are the
  break-glass path.
- **Nine VMs, not six** — 30 vCPU and 60GB of RAM asked for, plus 3 × 140GB of
  disk. `mise run preflight` checks the host has it.
