data "cloudflare_zone" "this" {
  filter = {
    name = local.edge.zone
  }
}

resource "cloudflare_dns_record" "site" {
  for_each = { for site in local.edge.sites : site.domain => site }

  zone_id = data.cloudflare_zone.this.id
  name    = each.key
  type    = "A"
  content = oci_core_instance.edge.public_ip
  ttl     = 300
  proxied = false
  comment = "terraform: oci edge"
}
