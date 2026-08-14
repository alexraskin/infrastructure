# A dedicated user for the backup credential, not the admin API user.
#
# The Customer Secret Key created here ends up in a Kubernetes Secret, which
# anything with pod-exec in the cluster can read — the same reasoning that scopes
# Loki's R2 token to one bucket. Handing that out with
# the Terraform user's rights would mean handing out the edge instance too.
#
# IAM lives in the tenancy, not in a compartment, so the user, group and policy
# are all created against local.admin["oci_tenancy_ocid"] regardless of where the bucket is.

data "oci_identity_compartment" "this" {
  id = local.admin["oci_compartment_ocid"]
}

locals {
  # A policy statement scopes to a compartment by *name*, except at the root:
  # the tenancy is a compartment but "in compartment <tenancy name>" is rejected
  # with "does not exist or is not part of the policy compartment subtree".
  # `in tenancy` is the only form that works there.
  policy_scope = (
    local.admin["oci_compartment_ocid"] == local.admin["oci_tenancy_ocid"]
    ? "in tenancy"
    : "in compartment ${data.oci_identity_compartment.this.name}"
  )
}

resource "oci_identity_user" "cnpg_backup" {
  compartment_id = local.admin["oci_tenancy_ocid"]
  name           = "cnpg-backup"
  description    = "CloudNativePG backups — managed by Terraform"

  email = local.admin["backup_user_email"]

  freeform_tags = {
    managed-by = "terraform"
  }
}

resource "oci_identity_group" "cnpg_backup" {
  compartment_id = local.admin["oci_tenancy_ocid"]
  name           = "cnpg-backup"
  description    = "Write access to the CloudNativePG backup bucket only"

  freeform_tags = {
    managed-by = "terraform"
  }
}

resource "oci_identity_user_group_membership" "cnpg_backup" {
  user_id  = oci_identity_user.cnpg_backup.id
  group_id = oci_identity_group.cnpg_backup.id
}

resource "oci_identity_policy" "cnpg_backup" {
  compartment_id = local.admin["oci_tenancy_ocid"]
  name           = "cnpg-backup"
  description    = "CloudNativePG backups — managed by Terraform"

  statements = [
    "Allow group ${oci_identity_group.cnpg_backup.name} to read buckets ${local.policy_scope} where target.bucket.name = '${var.bucket_name}'",
    "Allow group ${oci_identity_group.cnpg_backup.name} to manage objects ${local.policy_scope} where target.bucket.name = '${var.bucket_name}'",
  ]

  freeform_tags = {
    managed-by = "terraform"
  }
}

resource "oci_identity_customer_secret_key" "cnpg_backup" {
  display_name = "cnpg-backup"
  user_id      = oci_identity_user.cnpg_backup.id
}
