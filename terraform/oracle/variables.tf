# The six OCI variables are the same ones 00-cloud-edge/terraform/ takes, and
# arrive the same way: as TF_VAR_* from secrets/oci.env, via scripts/oci-env.sh.
# Nothing here is a tfvars entry, so nothing reaches a plan output or a diff.

variable "oci_tenancy_ocid" {
  description = "Tenancy OCID"
  type        = string
}

variable "oci_user_ocid" {
  description = "OCID of the user whose API key signs these requests"
  type        = string
}

variable "oci_fingerprint" {
  description = "Fingerprint of that user's API signing key"
  type        = string
}

variable "oci_private_key_path" {
  description = "Path to the API signing key; defaults to secrets/oci_api_key.pem"
  type        = string
}

variable "oci_region" {
  description = "Region the bucket lives in — also the region in the S3 endpoint"
  type        = string
}

variable "oci_compartment_ocid" {
  description = "Compartment the bucket is created in"
  type        = string
}

variable "backup_user_email" {
  description = "Primary email for the cnpg-backup IAM user — required in an Identity Domains tenancy"
  type        = string
}

variable "bucket_name" {
  description = "Object Storage bucket holding the CloudNativePG backups"
  type        = string
  default     = "cnpg-backups"

  validation {
    # The bucket name ends up in an IAM policy statement and in destinationPath.
    condition     = can(regex("^[a-zA-Z0-9._-]{1,256}$", var.bucket_name))
    error_message = "bucket_name must be 1-256 chars of [a-zA-Z0-9._-]."
  }
}
