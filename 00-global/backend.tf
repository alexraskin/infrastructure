terraform {
  backend "oci" {
    bucket = "infrastructure-terraform-state"
    key    = "global/terraform.tfstate"
  }
}
