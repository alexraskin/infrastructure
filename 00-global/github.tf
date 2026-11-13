# Owned by the alexraskin.com project: an account has one provider per URL.
data "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"
}

locals {
  proxmox_state = "infrastructure/proxmox/terraform.tfstate"

  # One role per root CI runs Terraform in, keyed by its GitHub environment.
  ci_roots = {
    cloudflare = { read_state_keys = [local.proxmox_state] }
    tailscale  = { read_state_keys = [local.proxmox_state] }
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
  state_key         = "infrastructure/${each.key}/terraform.tfstate"
  read_state_keys   = each.value.read_state_keys
}
