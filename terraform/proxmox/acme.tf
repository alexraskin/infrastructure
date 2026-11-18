resource "proxmox_acme_dns_plugin" "route53" {
  plugin = "route53"
  api    = "aws"
  data   = var.acme_dns_plugin_data

  validation_delay = 30
}

resource "proxmox_acme_certificate" "host" {
  node_name = var.pve_node
  account   = var.acme_account

  force = true

  domains = [
    {
      domain = var.pve_fqdn
      plugin = proxmox_acme_dns_plugin.route53.plugin
    },
  ]
}

module "acme_user" {
  source = "../../modules/acme-route53-user"

  name    = "acme-pve"
  zone_id = data.aws_route53_zone.this.zone_id
  domains = [var.pve_fqdn]
}
