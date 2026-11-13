terraform {
  required_version = ">= 1.12"

  backend "s3" {
    bucket       = "alexraskin-tfstate"
    key          = "infrastructure/cloudflare/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }

  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5.0"
    }
  }
}

provider "cloudflare" {}

