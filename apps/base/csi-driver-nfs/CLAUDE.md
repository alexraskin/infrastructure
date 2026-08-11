# apps/base/csi-driver-nfs/ — RWX storage

The only StorageClass here that provisions on demand and the only one whose
volumes are not pinned to a node. `local-path` and `db-local` are static PVs
written by hand; this one mounts an export, creates a subdirectory per volume
and hands it out.

## It is not the NAS

The obvious reading of "NFS storage" in this homelab is the NAS at
`10.0.54.235`. It is not that, and cannot be:

- the NAS is on `10.0.54.0/24`, the cluster on `10.0.200.0/24`, with no route
  between them. Verified, not assumed: `nc 10.0.54.235 2049` from a pod fails.
- Tailscale does not rescue it either, even though `chronos` is on the tailnet.
  An NFS mount is performed by the **CSI node plugin in the node's own network
  namespace**, so an in-cluster egress proxy (a ClusterIP) is not on the path.
  The nodes themselves run no tailscaled — see the root `CLAUDE.md`.

So the server is an LXC on the cluster's own bridge, built by
`terraform/proxmox/nfs.tf` and provisioned by `scripts/nfs-provision.sh`. Its
disk is Proxmox storage, and its only backup is the nightly vzdump job, which
covers it because `backups.tf` adds its VMID explicitly.

Pointing this at the real NAS instead needs a route and firewall rule on the
router permitting VLAN 200 → `10.0.54.235` on 111/2049. Nothing in this repo can
do that. If it is ever done, only `server` in `storageclass.yaml` changes.

## The address is written twice

`storageclass.yaml` repeats the `server` and `share` from `nfs` in
`terraform/proxmox/cluster.auto.tfvars.json`. Flux cannot read Terraform
variables, so this is unavoidable; `mise run nfs:status` prints both and is the
check that they still agree.

## Gotchas

- **The namespace is `privileged`.** The node plugin mounts in the host's
  namespace, which Talos' default PodSecurity `baseline` forbids. Without the
  label the DaemonSet sits at DESIRED n / CURRENT 0 with FailedCreate events and
  no pod ever starts — no crash, no logs.
- **`node.tolerations: operator: Exists`** so the plugin also runs on the three
  control plane nodes and the three tainted db nodes. A pod cannot mount a
  volume on a node with no driver, and a database is exactly the thing that
  might want one.
- **`onDelete: archive`.** A deleted PVC leaves its data on the server under
  `archived-<pvc>` rather than removing it. Space is reclaimed by hand, on
  purpose — the reclaim policy is `Delete`, so without this a deleted claim
  would take the data with it.
- **`no_root_squash` is set on the export** (`scripts/nfs-provision.sh`), because
  charts routinely write as root on first start. Combined with an export
  restricted to the cluster subnet, that is the access control: NFSv4 without
  Kerberos authenticates nothing, so anything that can reach 2049 can read
  everything.
