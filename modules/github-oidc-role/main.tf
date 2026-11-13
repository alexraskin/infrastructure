data "aws_iam_policy_document" "trust" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.repository}:environment:${var.environment}"]
    }
  }
}

resource "aws_iam_role" "this" {
  name                 = var.name
  description          = "GitHub Actions, ${var.repository} environment ${var.environment}, managed by Terraform"
  assume_role_policy   = data.aws_iam_policy_document.trust.json
  max_session_duration = 3600
}

data "aws_iam_policy_document" "state" {
  count = var.state_key == null ? 0 : 1

  statement {
    sid       = "ListStateBucket"
    actions   = ["s3:ListBucket"]
    resources = ["arn:aws:s3:::${var.state_bucket}"]

    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = concat([var.state_key, "${var.state_key}.tflock"], var.read_state_keys)
    }
  }

  statement {
    sid     = "OwnState"
    actions = ["s3:GetObject", "s3:PutObject"]
    resources = [
      "arn:aws:s3:::${var.state_bucket}/${var.state_key}",
      "arn:aws:s3:::${var.state_bucket}/${var.state_key}.tflock",
    ]
  }

  statement {
    sid       = "Unlock"
    actions   = ["s3:DeleteObject"]
    resources = ["arn:aws:s3:::${var.state_bucket}/${var.state_key}.tflock"]
  }

  dynamic "statement" {
    for_each = length(var.read_state_keys) > 0 ? [1] : []

    content {
      sid       = "RemoteState"
      actions   = ["s3:GetObject"]
      resources = [for k in var.read_state_keys : "arn:aws:s3:::${var.state_bucket}/${k}"]
    }
  }
}

resource "aws_iam_role_policy" "state" {
  count = var.state_key == null ? 0 : 1

  name   = "terraform-state"
  role   = aws_iam_role.this.id
  policy = data.aws_iam_policy_document.state[0].json
}

# SecureStrings under aws/ssm: that key's policy already lets the account
# decrypt through SSM, so no kms statement is needed.
data "aws_iam_policy_document" "ssm" {
  count = length(var.ssm_parameter_arns) > 0 ? 1 : 0

  statement {
    actions   = ["ssm:GetParameter", "ssm:GetParameters", "ssm:GetParametersByPath"]
    resources = var.ssm_parameter_arns
  }
}

resource "aws_iam_role_policy" "ssm" {
  count = length(var.ssm_parameter_arns) > 0 ? 1 : 0

  name   = "ssm-parameters"
  role   = aws_iam_role.this.id
  policy = data.aws_iam_policy_document.ssm[0].json
}
