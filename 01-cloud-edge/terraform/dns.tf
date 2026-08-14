data "cloudflare_zone" "this" {
  filter = {
    name = local.edge.zone
  }
}

locals {
  wildcards = try(local.edge.wildcards, [])

  site_parents = {
    for site in local.edge.sites :
    site.domain => join(".", slice(split(".", site.domain), 1, length(split(".", site.domain))))
  }

  # Sites a wildcard already answers for need no record of their own.
  standalone_sites = {
    for site in local.edge.sites : site.domain => site
    if !contains(local.wildcards, local.site_parents[site.domain])
  }
}

resource "cloudflare_dns_record" "wildcard" {
  for_each = toset(local.wildcards)

  zone_id = data.cloudflare_zone.this.id
  name    = "*.${each.key}"
  type    = "A"
  content = oci_core_instance.edge.public_ip
  ttl     = 300
  proxied = false
  comment = "terraform: oci edge (wildcard)"
}

resource "cloudflare_dns_record" "site" {
  for_each = local.standalone_sites

  zone_id = data.cloudflare_zone.this.id
  name    = each.key
  type    = "A"
  content = oci_core_instance.edge.public_ip
  ttl     = 300
  proxied = false
  comment = "terraform: oci edge"
}
