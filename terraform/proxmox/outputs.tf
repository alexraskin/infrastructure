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

output "servers" {
  description = "Control-plane node names, bootstrap first (deploy order)"
  value = concat(
    [local.cluster.bootstrap],
    sort([for n, v in local.nodes : n if v.role == "server" && n != local.cluster.bootstrap])
  )
}

output "agents" {
  description = "Worker node names"
  value       = sort([for n, v in local.nodes : n if v.role == "agent"])
}

output "control_plane_endpoint" {
  description = "kube-vip VIP fronting the API servers"
  value       = "https://${local.cluster.vip}:6443"
}

output "backup_job" {
  description = "The nightly vzdump job: what it covers, where it lands, how long it is kept"
  value = {
    id        = proxmox_backup_job.cluster.id
    storage   = proxmox_backup_job.cluster.storage
    schedule  = proxmox_backup_job.cluster.schedule
    enabled   = proxmox_backup_job.cluster.enabled
    vmids     = proxmox_backup_job.cluster.vmid
    retention = proxmox_backup_job.cluster.prune_backups
  }
}
