# Host's own input chain only — bridged VM traffic on VLAN var.vlan_id is
# untouched. depends_on below must not be removed; see CLAUDE.md gotchas.
resource "proxmox_virtual_environment_firewall_rules" "host" {
  node_name = var.pve_node

  rule {
    type    = "in"
    action  = "ACCEPT"
    proto   = "tcp"
    dport   = "8006"
    source  = var.pve_trusted_cidr
    comment = "PVE web UI - mgmt LAN"
  }

  rule {
    type    = "in"
    action  = "ACCEPT"
    proto   = "tcp"
    dport   = "22"
    source  = var.pve_trusted_cidr
    comment = "SSH - mgmt LAN; the provider's own ssh block needs this for disk ops"
  }

  rule {
    type    = "in"
    action  = "ACCEPT"
    macro   = "Ping"
    source  = var.pve_trusted_cidr
    comment = "ICMP - mgmt LAN"
  }
}

resource "proxmox_node_firewall" "this" {
  node_name = var.pve_node
  enabled   = true

  depends_on = [proxmox_virtual_environment_firewall_rules.host]
}

resource "proxmox_virtual_environment_cluster_firewall" "this" {
  enabled       = true
  input_policy  = "DROP"
  output_policy = "ACCEPT"

  depends_on = [proxmox_virtual_environment_firewall_rules.host]
}
