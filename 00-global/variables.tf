# The OCI variables are the ones every other Oracle root takes, and arrive the
# same way: as TF_VAR_* from secrets/oci.env, via scripts/oci-env.sh.

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
  description = "Region the state bucket lives in — also the region every backend block resolves against"
  type        = string
}

variable "oci_compartment_ocid" {
  description = "Compartment the state bucket is created in"
  type        = string
}

variable "oci_namespace" {
  description = "Object Storage namespace — Console: Tenancy details, or `oci os ns get`"
  type        = string
}

variable "ci_user_email" {
  description = "Primary email for the terraform-ci IAM user — required in an Identity Domains tenancy"
  type        = string
}

variable "bucket_name" {
  description = "Object Storage bucket holding the Terraform state of every root"
  type        = string
  default     = "infrastructure-terraform-state"

  validation {
    # The name is repeated in each backend block, which takes no variables.
    condition     = can(regex("^[a-zA-Z0-9._-]{1,256}$", var.bucket_name))
    error_message = "bucket_name must be 1-256 chars of [a-zA-Z0-9._-]."
  }
}
