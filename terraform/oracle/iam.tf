# A dedicated user for the backup credential, not the API user in secrets/oci.env.
#
# The Customer Secret Key created here ends up in a Kubernetes Secret, which
# anything with pod-exec in the cluster can read — the same reasoning that scopes
# Loki's R2 token to one bucket (apps/base/loki/CLAUDE.md). Handing that out with
# the Terraform user's rights would mean handing out the edge instance too.
#
# IAM lives in the tenancy, not in a compartment, so the user, group and policy
# are all created against var.oci_tenancy_ocid regardless of where the bucket is.

data "oci_identity_compartment" "this" {
  id = var.oci_compartment_ocid
}

locals {
  # A policy statement scopes to a compartment by *name*, except at the root:
  # the tenancy is a compartment but "in compartment <tenancy name>" is rejected
  # with "does not exist or is not part of the policy compartment subtree".
  # `in tenancy` is the only form that works there.
  policy_scope = (
    var.oci_compartment_ocid == var.oci_tenancy_ocid
    ? "in tenancy"
    : "in compartment ${data.oci_identity_compartment.this.name}"
  )
}

resource "oci_identity_user" "cnpg_backup" {
  compartment_id = var.oci_tenancy_ocid
  name           = "cnpg-backup"
  description    = "CloudNativePG backups — managed by Terraform"

  email = var.backup_user_email

  freeform_tags = {
    managed-by = "terraform"
  }
}

resource "oci_identity_group" "cnpg_backup" {
  compartment_id = var.oci_tenancy_ocid
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

# Policy statements name the compartment by *name*, not OCID, which is why the
# data source above exists. `manage objects` covers put/get/delete inside the
# bucket; `read buckets` is what lets barman-cloud check the bucket exists before
# its first upload. Both are constrained to this one bucket.
resource "oci_identity_policy" "cnpg_backup" {
  compartment_id = var.oci_tenancy_ocid
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

# The S3-compatible credential. `key` is returned only when the resource is
# created, so it exists in state and nowhere else — see CLAUDE.md.
resource "oci_identity_customer_secret_key" "cnpg_backup" {
  display_name = "cnpg-backup"
  user_id      = oci_identity_user.cnpg_backup.id
}
