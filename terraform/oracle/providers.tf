terraform {
  required_version = ">= 1.12"

  backend "oci" {
    bucket = "infrastructure-terraform-state"
    key    = "oracle/terraform.tfstate"
  }

  required_providers {
    sops = {
      source  = "carlpett/sops"
      version = "~> 1.4"
    }
    oci = {
      source  = "oracle/oci"
      version = "~> 6"
    }
  }
}

data "sops_file" "admin" {
  source_file = "${path.module}/../../sops/admin.sops.yaml"
}

locals {
  admin = data.sops_file.admin.data
}

provider "oci" {
  tenancy_ocid = local.admin["oci_tenancy_ocid"]
  user_ocid    = local.admin["oci_user_ocid"]
  fingerprint  = local.admin["oci_fingerprint"]
  private_key  = local.admin["oci_private_key"]
  region       = local.admin["oci_region"]
}
