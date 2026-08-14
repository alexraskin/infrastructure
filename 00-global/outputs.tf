output "namespace" {
  description = "Object Storage namespace the bucket lives in"
  value       = oci_objectstorage_bucket.tfstate.namespace
  sensitive   = true
}

output "bucket" {
  description = "State bucket name, repeated in the backend block of every root"
  value       = oci_objectstorage_bucket.tfstate.name
}

output "region" {
  description = "Region the state bucket lives in"
  value       = local.admin["oci_region"]
  sensitive   = true
}

output "ci_user_ocid" {
  description = "OCID of the terraform-ci user — backend_user_ocid in sops/terraform.sops.yaml"
  value       = oci_identity_user.ci.id
  sensitive   = true
}

output "ci_fingerprint" {
  description = "Fingerprint of the terraform-ci signing key — backend_fingerprint in sops/terraform.sops.yaml"
  value       = oci_identity_api_key.ci.fingerprint
  sensitive   = true
}

output "ci_private_key" {
  description = "PEM body of the terraform-ci signing key — backend_private_key in sops/terraform.sops.yaml"
  value       = tls_private_key.ci.private_key_pem
  sensitive   = true
}

output "tenancy_ocid" {
  description = "Tenancy OCID — backend_tenancy_ocid in sops/terraform.sops.yaml"
  value       = local.admin["oci_tenancy_ocid"]
  sensitive   = true
}
