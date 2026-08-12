data "terraform_remote_state" "proxmox" {
  backend = "s3"

  config = {
    bucket                      = "terraform"
    key                         = "talos-proxmox/terraform.tfstate"
    region                      = "auto"
    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
    skip_s3_checksum            = true
    use_path_style              = true
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
