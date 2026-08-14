# Set by scripts/tf.sh out of the SOPS file it decrypted. A remote-state config
# takes no -backend-config, so these arrive as ordinary variables.

variable "backend_namespace" {
  description = "Object Storage namespace holding the state bucket"
  type        = string
}

variable "backend_region" {
  description = "Region the state bucket lives in"
  type        = string
}

variable "backend_tenancy_ocid" {
  description = "Tenancy the state credentials belong to"
  type        = string
}

variable "backend_user_ocid" {
  description = "User the state credentials belong to"
  type        = string
}

variable "backend_fingerprint" {
  description = "Fingerprint of that user's API signing key"
  type        = string
}

variable "backend_private_key_path" {
  description = "Where scripts/tf.sh decrypted that signing key"
  type        = string
}
