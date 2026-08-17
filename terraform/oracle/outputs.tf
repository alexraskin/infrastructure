output "endpoint_url" {
  description = "S3-compatible endpoint — goes in cluster.yaml as barmanObjectStore.endpointURL"
  value       = "https://${data.oci_objectstorage_namespace.this.namespace}.compat.objectstorage.${local.admin["oci_region"]}.oraclecloud.com"
  sensitive   = true
}

output "destination_path" {
  description = "barmanObjectStore.destinationPath"
  value       = "s3://${oci_objectstorage_bucket.cnpg.name}/"
}

output "region" {
  description = "The `region` key of the cnpg-backup-oci Secret"
  value       = local.admin["oci_region"]
  sensitive   = true
}

output "access_key_id" {
  description = "The `access-key-id` key of the cnpg-backup-oci Secret"
  value       = oci_identity_customer_secret_key.cnpg_backup.id
  sensitive   = true
}

output "secret_access_key" {
  description = "The `secret-access-key` key of the cnpg-backup-oci Secret"
  value       = oci_identity_customer_secret_key.cnpg_backup.key
  sensitive   = true
}

output "namespace" {
  description = "Object Storage namespace, for `oci os object list --namespace`"
  value       = data.oci_objectstorage_namespace.this.namespace
  sensitive   = true
}
