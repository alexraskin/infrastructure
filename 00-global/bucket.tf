# The bucket every Terraform root in this repo keeps its state in, one object
# per root. Locking is the backend's own: it PUTs <key>.lock with
# `If-None-Match: *`, which Object Storage rejects if the object already exists.
#
# Versioning is on because this bucket holds the cluster PKI as well as state —
# a bad apply or a botched migration is recoverable from a previous version.

# The namespace is a variable, not a `data.oci_objectstorage_namespace` lookup
# like terraform/oracle/ uses: this root has to work before any backend does,
# and secrets/oci.env has to carry TF_VAR_oci_namespace regardless — every
# backend block in the repo is initialised with it.
resource "oci_objectstorage_bucket" "tfstate" {
  compartment_id = var.oci_compartment_ocid
  namespace      = var.oci_namespace
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

  # Deleting this bucket orphans every other root at once.
  lifecycle {
    prevent_destroy = true
  }
}
