terraform {
  required_providers {
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = "1.45.0"
    }
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 4"
    }
  }
  required_version = ">= 1.6.6"
}

provider "hcloud" {
  token = var.hetzner_token
}

provider "cloudflare" {
  token = var.cloudflare_token
}