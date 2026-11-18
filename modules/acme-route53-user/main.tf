# Keys are created out of band (`aws iam create-access-key`), never by Terraform.
resource "aws_iam_user" "this" {
  name = var.name
}

locals {
  challenge_names = distinct([for d in var.domains : "_acme-challenge.${trimprefix(d, "*.")}"])
}

data "aws_iam_policy_document" "this" {
  statement {
    sid = "Find"
    actions = [
      "route53:GetChange",
      "route53:ListHostedZones",
      "route53:ListHostedZonesByName",
    ]
    resources = ["*"]
  }

  statement {
    sid       = "Read"
    actions   = ["route53:ListResourceRecordSets"]
    resources = ["arn:aws:route53:::hostedzone/${var.zone_id}"]
  }

  statement {
    sid       = "WriteOwnChallenges"
    actions   = ["route53:ChangeResourceRecordSets"]
    resources = ["arn:aws:route53:::hostedzone/${var.zone_id}"]
    condition {
      test     = "ForAllValues:StringEquals"
      variable = "route53:ChangeResourceRecordSetsNormalizedRecordNames"
      values   = local.challenge_names
    }
    condition {
      test     = "ForAllValues:StringEquals"
      variable = "route53:ChangeResourceRecordSetsRecordTypes"
      values   = ["TXT"]
    }
    condition {
      test     = "Null"
      variable = "route53:ChangeResourceRecordSetsNormalizedRecordNames"
      values   = ["false"]
    }
  }
}

# CIS (Trivy AWS-0143): permissions go on a group, never on the user.
# AWS-0123 (MFA) can't apply: the only member is a key-only machine user.
#trivy:ignore:AWS-0123
resource "aws_iam_group" "this" {
  name = var.name
}

resource "aws_iam_group_policy" "this" {
  name   = "acme-dns-01"
  group  = aws_iam_group.this.name
  policy = data.aws_iam_policy_document.this.json
}

resource "aws_iam_user_group_membership" "this" {
  user   = aws_iam_user.this.name
  groups = [aws_iam_group.this.name]
}
