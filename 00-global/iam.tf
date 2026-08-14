data "oci_identity_compartment" "this" {
  id = local.admin["oci_compartment_ocid"]
}

locals {
  policy_scope = (
    local.admin["oci_compartment_ocid"] == local.admin["oci_tenancy_ocid"]
    ? "in tenancy"
    : "in compartment ${data.oci_identity_compartment.this.name}"
  )
}

resource "oci_identity_user" "ci" {
  compartment_id = local.admin["oci_tenancy_ocid"]
  name           = "terraform-ci"
  description    = "GitHub Actions Terraform state access — managed by Terraform"

  email = local.admin["ci_user_email"]

  freeform_tags = {
    managed-by = "terraform"
  }
}

resource "oci_identity_group" "ci" {
  compartment_id = local.admin["oci_tenancy_ocid"]
  name           = "terraform-ci"
  description    = "Read/write on the Terraform state bucket only"

  freeform_tags = {
    managed-by = "terraform"
  }
}

resource "oci_identity_user_group_membership" "ci" {
  user_id  = oci_identity_user.ci.id
  group_id = oci_identity_group.ci.id
}

resource "oci_identity_policy" "ci" {
  compartment_id = local.admin["oci_tenancy_ocid"]
  name           = "terraform-ci"
  description    = "GitHub Actions Terraform state access — managed by Terraform"

  statements = [
    "Allow group ${oci_identity_group.ci.name} to read buckets ${local.policy_scope} where target.bucket.name = '${oci_objectstorage_bucket.tfstate.name}'",
    "Allow group ${oci_identity_group.ci.name} to manage objects ${local.policy_scope} where target.bucket.name = '${oci_objectstorage_bucket.tfstate.name}'",
  ]

  freeform_tags = {
    managed-by = "terraform"
  }
}

resource "tls_private_key" "ci" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "oci_identity_api_key" "ci" {
  user_id   = oci_identity_user.ci.id
  key_value = tls_private_key.ci.public_key_pem
}
