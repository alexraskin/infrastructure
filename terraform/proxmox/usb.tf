resource "proxmox_hardware_mapping_usb" "node" {
  for_each = { for name, node in local.nodes : name => node if node.usb != null }

  name    = "${each.key}-usb"
  comment = "Passed through to ${each.key}"

  map = [{
    node = var.pve_node
    id   = each.value.usb
  }]
}
