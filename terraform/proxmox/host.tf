resource "proxmox_storage_directory" "local" {
  id      = "local"
  path    = "/var/lib/vz"
  content = ["backup", "iso", "vztmpl"]
  shared  = false
}

resource "proxmox_storage_lvmthin" "local_lvm" {
  id           = "local-lvm"
  volume_group = "pve"
  thin_pool    = "data"
  content      = ["images", "rootdir"]
}

resource "proxmox_network_linux_bridge" "vmbr0" {
  node_name = var.pve_node
  name      = var.network_bridge

  address = var.pve_bridge_address
  gateway = var.pve_bridge_gateway
  ports   = [var.pve_bridge_port]

  vlan_aware = true
  vids       = "2-4094"
  autostart  = true
}

resource "proxmox_apt_standard_repository" "no_subscription" {
  node   = var.pve_node
  handle = "no-subscription"
}
