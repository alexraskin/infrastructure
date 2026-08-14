terraform {
  required_version = ">= 1.12"

  backend "oci" {
    bucket = "infrastructure-terraform-state"
    key    = "cloudflare-k3s/terraform.tfstate"
  }

  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5.0"
    }
  }
}

provider "cloudflare" {}

