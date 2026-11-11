resource "proxmox_virtual_environment_user" "metrics_exporter" {
  user_id = var.pve_exporter_user_id
  enabled = true
  comment = "Managed by Terraform for the Prometheus PVE exporter"
}

resource "proxmox_acl" "metrics_exporter" {
  user_id   = proxmox_virtual_environment_user.metrics_exporter.user_id
  path      = var.pve_exporter_acl_path
  role_id   = var.pve_exporter_role_id
  propagate = true
}

resource "proxmox_user_token" "metrics_exporter" {
  user_id    = proxmox_virtual_environment_user.metrics_exporter.user_id
  token_name = var.pve_exporter_token_name
  comment    = "Managed by Terraform for the Prometheus PVE exporter"

  privileges_separation = false
}

moved {
  from = proxmox_virtual_environment_user_token.metrics_exporter
  to   = proxmox_user_token.metrics_exporter
}
