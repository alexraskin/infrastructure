data "aws_route53_zone" "this" {
  name = "alexraskin.com"
}

module "dns" {
  source = "../../modules/route53-records"

  zone_id = data.aws_route53_zone.this.zone_id

  records = {
    pve = { name = var.pve_fqdn, type = "A", records = [split("/", var.pve_bridge_address)[0]] }
    k8s = { name = "k8s.lan.${data.aws_route53_zone.this.name}", type = "A", records = [local.cluster.vip] }
  }
}
