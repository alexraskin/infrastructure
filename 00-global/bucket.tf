resource "oci_objectstorage_bucket" "tfstate" {
  compartment_id = local.admin["oci_compartment_ocid"]
  namespace      = local.admin["oci_namespace"]
  name           = var.bucket_name

  access_type           = "NoPublicAccess"
  storage_tier          = "Standard"
  versioning            = "Enabled"
  auto_tiering          = "Disabled"
  object_events_enabled = false

  freeform_tags = {
    managed-by = "terraform"
    purpose    = "terraform-state"
  }

  lifecycle {
    prevent_destroy = true
  }
}
