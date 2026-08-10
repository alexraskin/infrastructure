resource "proxmox_acme_dns_plugin" "cloudflare" {
  plugin = "cloudflare-dns"
  api    = "cf"
  data   = var.acme_dns_plugin_data

  validation_delay = 30
}

resource "proxmox_acme_certificate" "host" {
  node_name = var.pve_node
  account   = var.acme_account

  domains = [
    {
      domain = var.pve_fqdn
      plugin = proxmox_acme_dns_plugin.cloudflare.plugin
    },
  ]
}
