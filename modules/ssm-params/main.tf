# Values are set with `aws ssm put-parameter --overwrite`, never by Terraform.
resource "aws_ssm_parameter" "this" {
  for_each = var.parameters

  name        = "/infrastructure/${var.group}/${each.key}"
  description = each.value
  type        = "SecureString"
  value       = "set with aws ssm put-parameter"

  lifecycle {
    ignore_changes = [value]
  }
}

data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

locals {
  path_arn = "arn:aws:ssm:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:parameter/infrastructure/${var.group}"
}
