data "terraform_remote_state" "proxmox" {
  backend = "oci"

  config = {
    auth             = "APIKey"
    bucket           = "infrastructure-terraform-state"
    key              = "talos-proxmox/terraform.tfstate"
    namespace        = var.backend_namespace
    region           = var.backend_region
    tenancy_ocid     = var.backend_tenancy_ocid
    user_ocid        = var.backend_user_ocid
    fingerprint      = var.backend_fingerprint
    private_key_path = var.backend_private_key_path
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

  # The grants and the policy tests name svc:status, which has to exist first.
  depends_on = [tailscale_service.status]
}

import {
  to = tailscale_acl.policy
  id = "acl"
}
