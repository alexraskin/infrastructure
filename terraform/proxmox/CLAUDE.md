# terraform/proxmox/ — the nine cluster VMs, and the cluster

Creates the VMs **and** the Kubernetes cluster inside them. Node identity comes
from `cluster.auto.tfvars.json` and reaches the guest as a Talos machine
configuration applied over Talos' own API — there is no cloud-init drive and no
second configuration-management step. `mise run tf:apply` is the whole thing.

The root also owns the PVE host itself: its ACME certificate, storages, bridge
and apt repositories, adopted from a host that already existed. **That is why
`mise run tf:destroy` is targeted at the VM and Talos resources** — a bare
`terraform destroy` here dismantles the host, not the cluster.

State is in R2 — see "Terraform state lives in R2" in the root `CLAUDE.md`, and
use `mise run tf:init` rather than a bare `terraform init`. Note that the
cluster PKI (`talos_machine_secrets`) is in there too.

## The Talos half

- **`image.tf`** — `talos_image_factory_schematic` turns `cluster.extensions`
  into a schematic ID, `data.talos_image_factory_urls` resolves the ISO, and
  `proxmox_virtual_environment_download_file` pulls it onto the node. The same
  schematic ID goes into `machine.install.image` in `talos.tf`: the installed
  system has to carry the extensions the ISO booted with, or the qemu guest
  agent disappears at the first reboot.
- **`main.tf`** — a blank system disk, the ISO in the CD-ROM, `boot_order =
  ["scsi0", "ide3"]` so an installed node prefers its disk and a fresh one falls
  through to the ISO. The db nodes get a second disk from a `dynamic "disk"`
  block keyed on `data_disk` in `cluster.auto.tfvars.json`.
- **`talos.tf`** — the machine configs are assembled as `yamlencode` patches in
  `locals`, one list per node: identity and addressing, then the cluster-wide
  CNI/proxy/metrics settings, then the db-only label, taint and
  `UserVolumeConfig`. The last of those is a *separate configuration document*,
  passed as its own element of `config_patches`.
- `replace_triggered_by` on the ISO means bumping `talos_version` recreates the
  VMs. That is a rebuild of the cluster, not an upgrade — for an upgrade in
  place use `mise run upgrade`, which is `talosctl upgrade` node by node.
- **The VIP is only on the control plane nodes**, and the Talos client endpoints
  are deliberately the node addresses instead. Reasoning is in the root
  `CLAUDE.md` under "The VIP is Talos', not kube-vip's".

## nfs.tf — the NFS server LXC

A privileged Debian LXC on the cluster bridge, exporting a second disk to the
Kubernetes nodes. `apps/base/csi-driver-nfs/` consumes it; that directory's
`CLAUDE.md` covers why this exists instead of the NAS.

- **`unprivileged = false` and `features.mount = ["nfs"]` are both required.**
  The kernel NFS server loads `nfsd` and manipulates mounts, which an
  unprivileged container cannot do. This is the only guest here that is not
  locked down, which is why the export is restricted to the cluster subnet.
- **Provisioning runs through `pct exec` on the PVE host**, not SSH into the
  container: `scripts/nfs-provision.sh`, called from a `local-exec` provisioner.
  The provider already needs that SSH access, so the container needs no
  authorized key, no sshd, and no wait for one to come up. The tradeoff is that
  a provisioner only runs at **create** — changing the export means re-running
  the script by hand, or tainting the container.
- **`mount_point[0].volume` is in `ignore_changes`.** The config names a
  datastore (`local-lvm`) and the provider reads back an allocated volume id
  (`local-lvm:vm-130-disk-1`), so every plan would otherwise want to replace the
  container — which would discard the data.
- Its VMID is in the nightly backup job (`backups.tf`) explicitly. Unlike the
  Talos nodes, this container is not reproducible from git: the data is only
  here.

## What is adopted, and what cannot be

Most of this root was written against a host that already existed, so the
config was made to match `/etc/pve` and then imported. Import ID formats are
per-resource and inconsistent — `local`, `bunker:vmbr0`,
`bunker,no-subscription`, `cloudflare-dns` — the error message tells you the
expected shape when you get it wrong.

Three things the API token **cannot** manage, and no config change fixes:

- **The ACME account.** `proxmox_acme_account` fails with
  `Permission check failed (user != root@pam)` — PVE reserves the account
  endpoints for the real root user, and an API token, even root's own with
  privsep off, is not it. The account (`default`) stays hand-made; the plugin
  and the certificate that reference it are managed. Recreating a host from
  scratch means one `pvenode acme account register default <email>` first.
- **Feature flags on a privileged container.** Creating the NFS LXC is fine;
  passing `features { nesting mount }` with it is not —
  `Permission check failed (changing feature flags for privileged container is
  only allowed for root@pam)`. PVE compares the username exactly, and a token is
  `root@pam!terraform`, not `root@pam`; nesting on a *privileged* container is
  considered dangerous enough to reserve for the real root. So `nfs.tf` omits the
  block and `scripts/nfs-provision.sh` runs `pct set --features` over SSH, where
  root is genuinely root. `features` is in `ignore_changes` so Terraform does not
  try to take it back.
- **Individual apt repository lines.** `proxmox_apt_repository` has everything
  but `enabled` marked computed — it can toggle a line that exists, not declare
  one. Only `proxmox_apt_standard_repository` actually creates, so
  `no-subscription` is adopted through that and the Debian base lines are not
  managed. Both go stale at the PVE 9 upgrade anyway, which rewrites every
  source file to deb822 Trixie — see `docs/proxmox-8-to-9.md`.

## acme.tf — the host certificate

`bunker` serves its web UI with a Let's Encrypt certificate, ordered through
DNS-01 against Cloudflare, so no port has to be open to the internet.

- **The node had a malformed `acme:` key** — empty string — which made the
  provider fail every read of the node config with
  `invalid key-value pair:`. `pvenode config set --acme account=default` writes
  the value the UI would have, and the import works after that. Nothing else
  changed on the host.
- **`proxmox_acme_certificate` owns the domain list**, which PVE stores as
  `acmedomain0` on the node. `proxmox_node_config` cannot do this; it carries
  only `description`.
- **The plugin's `data` map is a live Cloudflare API token** and it goes into
  Terraform state in R2 as well as into `terraform.tfvars`. Write-only
  attributes (`data_wo`) would keep it out of state, but they need Terraform
  1.11 and this repo is pinned to 1.9. Treat R2 state as a secret store, and
  rotate the token if it is ever read out of PVE — `pvesh get
  /cluster/acme/plugins` prints it in cleartext to anyone with the API.
- `validation_delay = 30` is set explicitly. Unset, PVE stores nothing and the
  provider reads back 0, so every plan wanted to write 30 — 30 is PVE's own
  default and the value DNS-01 propagation actually needs.

## host.tf — storages, bridge, apt

- **`shared = false` on `local` is load-bearing.** Left unset the provider
  proposes `shared = true` on every plan, which would tell PVE a node-local
  directory is cluster-wide.
- **The bridge is the dangerous one.** `proxmox_network_linux_bridge.vmbr0`
  imported with no drift, and its values live in `terraform.tfvars` because a
  typo applied here strands the host — `vmbr0` carries the management address
  *and* every VM's traffic. Change it from the console, or with someone at the
  box.

## nas.tf — the two NFS storages

`proxmox_storage_nfs.nas` declares the NAS exports the host mounts: `backups`
(`/volume1/proxmox_backups`) and `iso` (`/volume1/ios-images`), both from
`var.nas_server`. PVE mounts them at `/mnt/pve/<id>`; the path is derived, not
configurable.

- **These were created by hand and adopted, not built by Terraform.** The
  config was written to match `/etc/pve/storage.cfg` exactly and then imported
  (`terraform import 'proxmox_storage_nfs.nas["backups"]' backups`). Importing
  does not populate the nested `backups {}` block or the computed `nodes` /
  `shared`, so the first plan after an import shows an in-place update that
  writes back values the storage already had. Apply it; the second plan is
  clean. Applying also materialises `create-base-path 1` / `create-subdirs 1`
  in storage.cfg, which were previously implicit defaults.
- **`keep_all = true` stays.** It is the storage-level prune fallback, and the
  backup job overrides it with its own policy. Turning it into a real retention
  here would prune *every* guest's dumps on this export, including the ones
  another host writes.
- **`nodes` is deliberately unset.** Setting it would pin the storage to
  `bunker` — true today, but it is a restriction PVE does not currently have,
  and writing it makes the import no longer a no-op.
- The NAS is only reachable from the host's own subnet (`10.0.54.0/24`). The
  cluster VMs are on VLAN 200 and cannot see it at all — see
  `apps/base/gatus/CLAUDE.md`, which probes it over the tailnet for that reason.
- Use the short resource name. `proxmox_virtual_environment_storage_nfs` exists
  but the provider deprecates it, and it goes away in v1.0.

## backups.tf — the nightly vzdump

`proxmox_backup_job.cluster` is a PVE *backup job* (`/etc/pve/jobs.cfg`), not a
backup: Terraform declares the schedule and PVE runs it. Nightly at **02:30 in
the host's timezone** (`America/Denver` — a systemd calendar event carries no
zone of its own), covering exactly the guests in `cluster.auto.tfvars.json`, to the `backups`
storage, which is an NFS export on the NAS.

Things worth knowing before changing it:

- **`vmid` is an explicit, sorted list, not `all = true`.** The same NFS export
  already holds dumps from another host, and `all` would silently pull in any
  future guest on `bunker` that has nothing to do with this cluster. Sorting is
  what keeps the list from producing a spurious diff on every plan, since
  `local.nodes` is a map.
- **`prune_backups` has to be set here, on the job.** Without a job-level
  policy vzdump falls back to the storage's, and `backups` is configured
  `prune-backups keep-all=1` — nothing would ever be pruned. Retention prunes
  per-guest as each guest finishes, so it only ever touches the nine VMIDs in
  this job, never the other host's dumps sharing the export.
- **`mode = "snapshot"` costs no downtime** because the guest agent is enabled
  on every VM (`agent { enabled = true }` in `main.tf`). etcd is consistent
  across it — this is a qemu-level snapshot with the guest fsfrozen, not a
  crash-consistent copy. `stop` mode would be a nightly cluster outage.
- **Restores are manual and stay that way.** `qmrestore <dump> <vmid>` from the
  PVE side, or throw the VM away and rebuild it: `tf:apply` re-applies the
  machine config and Flux repopulates it. Only node-local PV data (Loki WAL,
  gatus history, Prometheus TSDB) has no other copy, which is the whole reason
  the job exists.
- `mailnotification` is deliberately unset. PVE 8.3+ routes backup results
  through the notification system (`/etc/pve/notifications.cfg`), and setting
  the old field invites drift against whatever PVE normalises it to.
- Import is by job id, which is ours rather than PVE's generated one:
  `terraform import proxmox_backup_job.cluster talos-nightly`.
- **Destroying every guest in the job destroys the job.** PVE prunes vmids from
  `jobs.cfg` as their guests go away and deletes the entry once the list is
  empty, so a full cluster teardown takes the backup job with it. The provider
  does not treat that as "gone, recreate" — it reads by the id in state and
  fails the whole apply with `received an HTTP 400 response - Reason: Parameter
  verification failed. (id: No such job '<id>')`. Recovery is
  `terraform state rm proxmox_backup_job.cluster` and then apply, which creates
  it fresh. Check what PVE actually has first:
  `pvesh get /cluster/backup --output-format json`.
- **Keep `notes_template` ASCII.** An em dash in it fails the apply with
  "Provider produced inconsistent result after apply" — the provider writes
  UTF-8 and reads the response back double-encoded, so the value it returns
  never matches the plan. The job is still created on PVE when this happens,
  with mojibake in the notes; a re-apply with plain ASCII repairs it.

`proxmox_backup_job` has no `proxmox_virtual_environment_*` twin — it is the
short-named resource or nothing.

## Gotchas

- **The Proxmox provider ignores `~/.ssh/config`** and needs either
  `pve_ssh_private_key_path` or a loaded ssh-agent. Missing credentials fail
  *partway* through apply, after the VMs exist.
- **A privsep API token authenticates and then sees nothing** — Proxmox filters
  lists by permission rather than returning 403, so datastores and bridges come
  back as empty arrays. `pveum user token modify <userid> <tokenid> --privsep 0`
  (two separate arguments, not `user!token`).
- **The ISO is downloaded by the node, not uploaded by Terraform.**
  `proxmox_virtual_environment_download_file` makes PVE fetch it from
  factory.talos.dev, so the build host's uplink is irrelevant — but the PVE host
  needs egress to the internet, which the old image-upload path did not require.
- **`overwrite = false` on the ISO** keeps a re-apply from re-downloading it.
  The file name carries the Talos version and a schematic prefix, so a genuine
  change is a new file rather than a mutation of the old one.
