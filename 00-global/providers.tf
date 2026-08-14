terraform {
  # backend "oci" is Terraform 1.12+. The block itself lives in backend.tf, so
  # it can be moved aside if this bucket ever has to be created again.
  required_version = ">= 1.12"

  required_providers {
    oci = {
      source  = "oracle/oci"
      version = "~> 6"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4"
    }
  }
}

provider "oci" {
  tenancy_ocid     = var.oci_tenancy_ocid
  user_ocid        = var.oci_user_ocid
  fingerprint      = var.oci_fingerprint
  private_key_path = pathexpand(var.oci_private_key_path)
  region           = var.oci_region
}
