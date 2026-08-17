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
