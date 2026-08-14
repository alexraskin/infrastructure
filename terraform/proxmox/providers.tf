terraform {
  required_version = ">= 1.12"

  backend "oci" {
    bucket = "infrastructure-terraform-state"
    key    = "talos-proxmox/terraform.tfstate"
  }

  required_providers {
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

provider "proxmox" {
  endpoint  = var.pve_endpoint
  api_token = var.pve_api_token
  insecure  = var.pve_insecure

  ssh {
    username    = var.pve_ssh_username
    agent       = var.pve_ssh_private_key_path == ""
    private_key = var.pve_ssh_private_key_path == "" ? null : file(pathexpand(var.pve_ssh_private_key_path))
  }
}
