# The identity GitHub Actions authenticates the state backend as. Deliberately
# not the API user in secrets/oci.env: that one can create and destroy the edge
# instance, the buckets and the IAM around them, and CI only ever needs to read
# and write objects in one bucket.
#
# IAM lives in the tenancy, not in a compartment, so the user, group and policy
# are all created against var.oci_tenancy_ocid regardless of where the bucket is.

data "oci_identity_compartment" "this" {
  id = var.oci_compartment_ocid
}

locals {
  # A policy statement scopes to a compartment by *name*, except at the root:
  # the tenancy is a compartment but "in compartment <tenancy name>" is rejected.
  # `in tenancy` is the only form that works there.
  policy_scope = (
    var.oci_compartment_ocid == var.oci_tenancy_ocid
    ? "in tenancy"
    : "in compartment ${data.oci_identity_compartment.this.name}"
  )
}

resource "oci_identity_user" "ci" {
  compartment_id = var.oci_tenancy_ocid
  name           = "terraform-ci"
  description    = "GitHub Actions Terraform state access — managed by Terraform"

  email = var.ci_user_email

  freeform_tags = {
    managed-by = "terraform"
  }
}

resource "oci_identity_group" "ci" {
  compartment_id = var.oci_tenancy_ocid
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

# `manage objects` covers get/put/delete — the last one matters, because that is
# how the backend releases a lock. `read buckets` is what the backend's workspace
# listing needs before it touches any object. Both constrained to this bucket, so
# these credentials cannot reach the CNPG backup bucket.
resource "oci_identity_policy" "ci" {
  compartment_id = var.oci_tenancy_ocid
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

# The signing key. Its private half exists in state and nowhere else — the same
# posture as the cnpg Customer Secret Key and the Cloudflare tunnel token, and
# the reason CLAUDE.md calls this state a secret store. `mise run global:ci-creds`
# prints it for the GitHub environment secrets.
resource "tls_private_key" "ci" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "oci_identity_api_key" "ci" {
  user_id   = oci_identity_user.ci.id
  key_value = tls_private_key.ci.public_key_pem
}
