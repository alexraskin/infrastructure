terraform {
  required_version = ">= 1.12"

  backend "s3" {
    bucket       = "alexraskin-tfstate"
    key          = "infrastructure/proxmox/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6"
    }
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.111"
    }
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5"
    }
    talos = {
      source  = "siderolabs/talos"
      version = "~> 0.9"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.12"
    }
  }
}

# Secrets come from SSM, put there by 00-global. Same SSO session as the backend.
provider "aws" {
  region = "us-east-1"
}

data "aws_ssm_parameter" "pve_api_token" {
  name = "/infrastructure/proxmox/pve_api_token"
}

provider "proxmox" {
  endpoint  = var.pve_endpoint
  api_token = data.aws_ssm_parameter.pve_api_token.value
  insecure  = var.pve_insecure

  ssh {
    username    = var.pve_ssh_username
    agent       = var.pve_ssh_private_key_path == ""
    private_key = var.pve_ssh_private_key_path == "" ? null : file(pathexpand(var.pve_ssh_private_key_path))
  }
}
