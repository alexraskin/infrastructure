resource "aws_route53_zone" "this" {
  name = var.domain

  lifecycle {
    prevent_destroy = true
  }
}

locals {
  d = var.domain

  fastmail_mx = ["10 in1-smtp.messagingengine.com", "20 in2-smtp.messagingengine.com"]
}

module "dns" {
  source = "../modules/route53-records"

  zone_id = aws_route53_zone.this.zone_id
  dnssec  = { domain = var.domain, publish_ds = var.dnssec_publish_ds }

  records = {
    mx          = { name = local.d, type = "MX", ttl = 3600, records = local.fastmail_mx }
    mx_wildcard = { name = "*.${local.d}", type = "MX", ttl = 3600, records = local.fastmail_mx }
    dkim1       = { name = "fm1._domainkey.${local.d}", type = "CNAME", records = ["fm1.${local.d}.dkim.fmhosted.com"] }
    dkim2       = { name = "fm2._domainkey.${local.d}", type = "CNAME", records = ["fm2.${local.d}.dkim.fmhosted.com"] }
    dkim3       = { name = "fm3._domainkey.${local.d}", type = "CNAME", records = ["fm3.${local.d}.dkim.fmhosted.com"] }

    caa = { name = local.d, type = "CAA", records = ["0 issue \"amazon.com\"", "0 issue \"letsencrypt.org\""] }
  }
}

resource "aws_route53domains_registered_domain" "this" {
  domain_name = var.domain
  auto_renew  = true

  dynamic "name_server" {
    for_each = aws_route53_zone.this.name_servers
    content {
      name = name_server.value
    }
  }
}
