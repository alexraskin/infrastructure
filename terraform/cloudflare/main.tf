locals {
  hostname_zone = {
    for rule in var.ingress : rule.hostname => one([
      for zone_name, _ in var.zones : zone_name
      if rule.hostname == zone_name || endswith(rule.hostname, ".${zone_name}")
    ])
  }

  tunnel_hostnames = distinct([for rule in var.ingress : rule.hostname])
}

# Say which hostname is unroutable, instead of failing later on a null zone_id.
check "every_hostname_has_a_zone" {
  assert {
    condition     = alltrue([for h, z in local.hostname_zone : z != null])
    error_message = "No zone in var.zones covers: ${join(", ", [for h, z in local.hostname_zone : h if z == null])}"
  }
}

resource "cloudflare_zero_trust_tunnel_cloudflared" "this" {
  account_id = var.account_id
  name       = var.tunnel_name

  config_src = "cloudflare"
}

resource "cloudflare_zero_trust_tunnel_cloudflared_config" "this" {
  account_id = var.account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.this.id

  config = {
    ingress = concat(
      [
        for rule in var.ingress : {
          hostname = rule.hostname
          path     = rule.path
          service  = rule.service
        }
      ],
      [{ service = var.catch_all_service }],
    )
  }
}

data "cloudflare_zero_trust_tunnel_cloudflared_token" "this" {
  account_id = var.account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.this.id
}

resource "cloudflare_dns_record" "tunnel" {
  for_each = toset(local.tunnel_hostnames)

  zone_id = var.zones[local.hostname_zone[each.value]]
  name    = each.value
  type    = "CNAME"
  content = "${cloudflare_zero_trust_tunnel_cloudflared.this.id}.cfargotunnel.com"
  proxied = true
  ttl     = 1
  comment = "terraform: k3s tunnel"
}

resource "cloudflare_dns_record" "extra" {
  for_each = var.extra_dns_records

  zone_id = var.zones[each.value.zone]
  name    = each.value.name
  type    = each.value.type
  content = each.value.content
  ttl     = each.value.ttl
  proxied = each.value.proxied
  comment = each.value.comment
}
