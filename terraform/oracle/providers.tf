terraform {
  required_version = ">= 1.6"

  # Partial on purpose, like every other root here: a backend block takes no
  # variables and this repo is public, so the endpoint (which carries the
  # Cloudflare account id) and the keys come from secrets/r2.tfbackend via
  # `-backend-config`. Use `mise run oci:init`, never a bare `terraform init`.
  backend "s3" {
    bucket                      = "terraform"
    key                         = "oracle/terraform.tfstate"
    region                      = "auto"
    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
    skip_s3_checksum            = true
    use_path_style              = true
  }

  required_providers {
    oci = {
      source  = "oracle/oci"
      version = "~> 6"
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
