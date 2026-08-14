data "oci_objectstorage_namespace" "this" {
  compartment_id = local.admin["oci_compartment_ocid"]
}

resource "oci_objectstorage_bucket" "cnpg" {
  compartment_id = local.admin["oci_compartment_ocid"]
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
