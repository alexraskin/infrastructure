terraform {
  required_version = ">= 1.12"

  backend "s3" {
    bucket       = "alexraskin-tfstate"
    key          = "infrastructure/tailscale/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }

  required_providers {
    tailscale = {
      source  = "tailscale/tailscale"
      version = "~> 0.29"
    }
  }
}

provider "tailscale" {}

