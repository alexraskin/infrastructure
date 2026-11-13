terraform {
  required_version = ">= 1.12"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6"
    }
    sops = {
      source  = "carlpett/sops"
      version = "~> 1.4"
    }
  }
}

data "sops_file" "admin" {
  source_file = "${path.module}/../sops/admin.sops.yaml"
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      ManagedBy = "terraform"
      Project   = "infrastructure"
    }
  }
}
