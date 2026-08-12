output "nodes" {
  description = "Node name -> address, role and vmid"
  value = {
    for name, node in local.nodes : name => {
      ip   = node.ip
      role = node.role
      vmid = node.vmid
    }
  }
}

output "network" {
  description = "Cluster addressing other Terraform roots consume"
  value = {
    vip     = local.cluster.vip
    gateway = local.cluster.gateway
    subnet  = "${cidrhost("${local.cluster.gateway}/${local.cluster.prefix}", 0)}/${local.cluster.prefix}"
    pve_host = split("/", var.pve_bridge_address)[0]
  }
}

output "control_plane_endpoint" {
  description = "The Talos VIP fronting the API servers"
  value       = local.cluster_endpoint
}

output "talos_endpoints" {
  description = "Talos API endpoints — node addresses, deliberately not the VIP"
  value       = data.talos_client_configuration.this.endpoints
}

output "talos_image" {
  description = "Factory schematic and the installer image the nodes run"
  value = {
    schematic_id = talos_image_factory_schematic.this.id
    extensions   = local.cluster.extensions
    installer    = local.install_image
    iso          = proxmox_virtual_environment_download_file.talos_iso.id
  }
}

output "talosconfig" {
  description = "Client configuration for talosctl"
  value       = data.talos_client_configuration.this.talos_config
  sensitive   = true
}

output "kubeconfig" {
  description = "Cluster admin kubeconfig, pointed at the VIP"
  value       = talos_cluster_kubeconfig.this.kubeconfig_raw
  sensitive   = true
}

output "backup_job" {
  description = "The nightly vzdump job"
  value = {
    id        = proxmox_backup_job.cluster.id
    storage   = proxmox_backup_job.cluster.storage
    schedule  = proxmox_backup_job.cluster.schedule
    enabled   = proxmox_backup_job.cluster.enabled
    vmids     = proxmox_backup_job.cluster.vmid
    retention = proxmox_backup_job.cluster.prune_backups
  }
}
