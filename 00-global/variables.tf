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
