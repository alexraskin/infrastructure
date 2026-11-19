resource "aws_route53_record" "this" {
  for_each = var.records

  zone_id = var.zone_id
  name    = each.value.name
  type    = each.value.type
  ttl     = each.value.alias == null ? each.value.ttl : null
  records = each.value.alias == null ? each.value.records : null

  dynamic "alias" {
    for_each = each.value.alias == null ? [] : [each.value.alias]
    content {
      name                   = alias.value.name
      zone_id                = alias.value.zone_id
      evaluate_target_health = false
    }
  }
}

# DNSSEC, only for the caller that owns the zone.
locals {
  dnssec = var.dnssec != null
}

data "aws_caller_identity" "current" {
  count = local.dnssec ? 1 : 0
}

# Route 53 signs with an asymmetric KMS key, which must live in us-east-1.
resource "aws_kms_key" "dnssec" {
  count = local.dnssec ? 1 : 0

  description              = "DNSSEC key-signing key for ${var.dnssec.domain}"
  customer_master_key_spec = "ECC_NIST_P256"
  key_usage                = "SIGN_VERIFY"
  deletion_window_in_days  = 30
  policy                   = data.aws_iam_policy_document.dnssec_kms[0].json
}

data "aws_iam_policy_document" "dnssec_kms" {
  count = local.dnssec ? 1 : 0

  statement {
    sid       = "Route53Sign"
    actions   = ["kms:DescribeKey", "kms:GetPublicKey", "kms:Sign"]
    resources = ["*"]
    principals {
      type        = "Service"
      identifiers = ["dnssec-route53.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current[0].account_id]
    }
    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = ["arn:aws:route53:::hostedzone/*"]
    }
  }

  statement {
    sid       = "Route53Grant"
    actions   = ["kms:CreateGrant"]
    resources = ["*"]
    principals {
      type        = "Service"
      identifiers = ["dnssec-route53.amazonaws.com"]
    }
    condition {
      test     = "Bool"
      variable = "kms:GrantIsForAWSResource"
      values   = ["true"]
    }
  }

  statement {
    sid       = "AccountAdmin"
    actions   = ["kms:*"]
    resources = ["*"]
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current[0].account_id}:root"]
    }
  }
}

resource "aws_kms_alias" "dnssec" {
  count = local.dnssec ? 1 : 0

  name          = "alias/dnssec-${replace(var.dnssec.domain, ".", "-")}"
  target_key_id = aws_kms_key.dnssec[0].key_id
}

resource "aws_route53_key_signing_key" "this" {
  count = local.dnssec ? 1 : 0

  hosted_zone_id             = var.zone_id
  key_management_service_arn = aws_kms_key.dnssec[0].arn
  name                       = "ksk1"
}

resource "aws_route53_hosted_zone_dnssec" "this" {
  count = local.dnssec ? 1 : 0

  hosted_zone_id = aws_route53_key_signing_key.this[0].hosted_zone_id
}

# The chain of trust. Off until signing has run for the zone's max TTL (48h, the apex NS).
resource "aws_route53domains_delegation_signer_record" "this" {
  count = local.dnssec && try(var.dnssec.publish_ds, false) ? 1 : 0

  domain_name = var.dnssec.domain

  signing_attributes {
    algorithm  = aws_route53_key_signing_key.this[0].signing_algorithm_type
    flags      = aws_route53_key_signing_key.this[0].flag
    public_key = aws_route53_key_signing_key.this[0].public_key
  }

  depends_on = [aws_route53_hosted_zone_dnssec.this]
}
