resource "proxmox_backup_job" "cluster" {
  id      = "talos-nightly"
  node    = var.pve_node
  storage = var.backup_storage
  enabled = var.backup_enabled

  schedule = var.backup_schedule

  vmid = sort([for node in local.nodes : tostring(node.vmid)])

  mode     = "snapshot"
  compress = "zstd"
  zstd     = 0

  notes_template = "{{guestname}} - nightly, managed by Terraform"

  prune_backups = var.backup_retention

  depends_on = [proxmox_storage_nfs.nas]
}
