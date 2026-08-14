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
