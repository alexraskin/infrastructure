terraform {
  required_version = ">= 1.6"

  required_providers {
    oci = {
      source  = "oracle/oci"
      version = "~> 6"
    }
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5"
    }
  }
}

# Both providers in one root, unlike terraform/cloudflare/ which is split off
# from terraform/proxmox/ precisely to keep DNS away from the VMs. The reason it
# is different here: the A record's whole content is
# `oci_core_instance.edge.public_ip`. Splitting them would mean copying an
# ephemeral address between two states by hand every time the instance is
# replaced — which is exactly the thing that goes stale silently.
provider "oci" {
  tenancy_ocid     = var.oci_tenancy_ocid
  user_ocid        = var.oci_user_ocid
  fingerprint      = var.oci_fingerprint
  private_key_path = pathexpand(var.oci_private_key_path)
  region           = var.oci_region
}

provider "cloudflare" {
  api_token = var.cloudflare_api_token
}
