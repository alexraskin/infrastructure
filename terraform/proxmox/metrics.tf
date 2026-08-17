resource "proxmox_virtual_environment_user" "metrics_exporter" {
  user_id = var.pve_exporter_user_id
  enabled = true
  comment = "Managed by Terraform for the Prometheus PVE exporter"

  acl {
    path      = var.pve_exporter_acl_path
    role_id   = var.pve_exporter_role_id
    propagate = true
  }
}

resource "proxmox_virtual_environment_user_token" "metrics_exporter" {
  user_id    = proxmox_virtual_environment_user.metrics_exporter.user_id
  token_name = var.pve_exporter_token_name
  comment    = "Managed by Terraform for the Prometheus PVE exporter"

  # The token inherits the user's ACL instead of needing one of its own.
  privileges_separation = false
}
