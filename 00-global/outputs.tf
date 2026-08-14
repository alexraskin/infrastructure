# `mise run global:backend` prints these: what every backend block in the repo
# has to be initialised against.

output "namespace" {
  description = "Object Storage namespace the bucket lives in"
  value       = oci_objectstorage_bucket.tfstate.namespace
}

output "bucket" {
  description = "State bucket name, repeated in the backend block of every root"
  value       = oci_objectstorage_bucket.tfstate.name
}

output "region" {
  description = "Region the state bucket lives in"
  value       = var.oci_region
}

# The GitHub environment secrets for the cloudflare and tailscale workflows.
# `mise run global:ci-creds` prints them in the order the workflows read them.

output "ci_user_ocid" {
  description = "OCID of the terraform-ci user — the OCI_USER_OCID secret"
  value       = oci_identity_user.ci.id
}

output "ci_fingerprint" {
  description = "Fingerprint of the terraform-ci signing key — the OCI_FINGERPRINT secret"
  value       = oci_identity_api_key.ci.fingerprint
}

output "ci_private_key" {
  description = "PEM body of the terraform-ci signing key — the OCI_API_KEY secret"
  value       = tls_private_key.ci.private_key_pem
  sensitive   = true
}

output "tenancy_ocid" {
  description = "The OCI_TENANCY_OCID secret"
  value       = var.oci_tenancy_ocid
}
