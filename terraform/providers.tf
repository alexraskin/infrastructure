terraform {
  required_version = ">= 1.6"

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.111"
    }
  }
}

provider "proxmox" {
  endpoint  = var.pve_endpoint
  api_token = var.pve_api_token
  insecure  = var.pve_insecure

  # bpg falls back to SSH for operations the API cannot do (disk import, resize).
  # It does not read ~/.ssh/config, so it needs either a loaded ssh-agent or an
  # explicit key. Set pve_ssh_private_key_path = "" to use the agent instead.
  ssh {
    username    = var.pve_ssh_username
    agent       = var.pve_ssh_private_key_path == ""
    private_key = var.pve_ssh_private_key_path == "" ? null : file(pathexpand(var.pve_ssh_private_key_path))
  }
}
