terraform {
  # backend "oci" is Terraform 1.12+.
  required_version = ">= 1.12"

  # Partial on purpose — scripts/tf.sh supplies the credentials. See CLAUDE.md.
  backend "oci" {
    bucket = "infrastructure-terraform-state"
    key    = "tailscale/terraform.tfstate"
  }

  required_providers {
    tailscale = {
      source  = "tailscale/tailscale"
      version = "~> 0.29"
    }
  }
}

provider "tailscale" {}

