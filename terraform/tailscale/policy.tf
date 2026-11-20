data "terraform_remote_state" "proxmox" {
  backend = "s3"

  config = {
    bucket = "alexraskin-tfstate"
    key    = "infrastructure/proxmox/terraform.tfstate"
    region = "us-east-1"
  }
}

resource "tailscale_acl" "policy" {
  acl = templatefile("${path.module}/policy.hujson", {
    cluster_subnet = data.terraform_remote_state.proxmox.outputs.network.subnet
    cluster_vip    = data.terraform_remote_state.proxmox.outputs.network.vip
    node = {
      for name, node in data.terraform_remote_state.proxmox.outputs.nodes :
      name => node.ip
    }
  })
}

import {
  to = tailscale_acl.policy
  id = "acl"
}
