locals {
  wildcards = try(local.edge.wildcards, [])

  site_parents = {
    for site in local.edge.sites :
    site.domain => join(".", slice(split(".", site.domain), 1, length(split(".", site.domain))))
  }

  standalone_sites = {
    for site in local.edge.sites : site.domain => site
    if !contains(local.wildcards, local.site_parents[site.domain])
  }
}

data "aws_route53_zone" "this" {
  name = local.edge.zone
}

module "dns" {
  source = "../../modules/route53-records"

  zone_id = data.aws_route53_zone.this.zone_id

  records = merge(
    { for w in local.wildcards : "*.${w}" => { name = "*.${w}", type = "A", records = [oci_core_instance.edge.public_ip] } },
    { for d, _ in local.standalone_sites : d => { name = d, type = "A", records = [oci_core_instance.edge.public_ip] } },
  )
}

module "acme_user" {
  source = "../../modules/acme-route53-user"

  name    = "acme-edge"
  zone_id = data.aws_route53_zone.this.zone_id
  domains = concat([for w in local.wildcards : "*.${w}"], keys(local.standalone_sites))
}
