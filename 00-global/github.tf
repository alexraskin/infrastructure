# Owned by the alexraskin.com project: an account has one provider per URL.
data "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"
}

locals {
  proxmox_state = "infrastructure/proxmox/terraform.tfstate"

  # One role per GitHub environment. Terraform roots get their own state;
  # edge runs no Terraform, so it gets none.
  ci_roots = {
    cloudflare = { state = true, read_state_keys = [local.proxmox_state], secrets = ["cloudflare"] }
    tailscale  = { state = true, read_state_keys = [local.proxmox_state], secrets = [] }
    edge       = { state = false, read_state_keys = [], secrets = ["edge"] }
  }
}

module "ci_role" {
  source   = "../modules/github-oidc-role"
  for_each = local.ci_roots

  name              = "github-infrastructure-${each.key}"
  oidc_provider_arn = data.aws_iam_openid_connect_provider.github.arn
  repository        = var.repository
  environment       = each.key
  state_bucket      = var.state_bucket
  state_key         = each.value.state ? "infrastructure/${each.key}/terraform.tfstate" : null
  read_state_keys   = each.value.read_state_keys

  ssm_parameter_arns = flatten([for g in each.value.secrets : module.secrets[g].read_arns])
}
