# The bucket CloudNativePG archives WAL and base backups into.
#
# No lifecycle policy, deliberately. CNPG's own `backup.retentionPolicy` deletes
# expired backups and the WAL they no longer need; a second expiry mechanism
# working off object age would eventually delete WAL segments that a still-valid
# base backup depends on, and the failure only shows up at restore time.

data "oci_objectstorage_namespace" "this" {
  compartment_id = var.oci_compartment_ocid
}

resource "oci_objectstorage_bucket" "cnpg" {
  compartment_id = var.oci_compartment_ocid
  namespace      = data.oci_objectstorage_namespace.this.namespace
  name           = var.bucket_name

  access_type           = "NoPublicAccess"
  storage_tier          = "Standard"
  versioning            = "Disabled"
  auto_tiering          = "Disabled"
  object_events_enabled = false

  freeform_tags = {
    managed-by = "terraform"
    purpose    = "cloudnativepg-backups"
  }
}
