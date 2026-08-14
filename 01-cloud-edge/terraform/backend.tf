terraform {
  backend "oci" {
    bucket = "infrastructure-terraform-state"
    key    = "edge-compute/terraform.tfstate"
  }
}
