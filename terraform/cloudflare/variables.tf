variable "account_id" {
  description = "Cloudflare account ID that owns the tunnel"
  type        = string
}

variable "tunnel_name" {
  description = "Name of the existing tunnel, as it appears in Zero Trust -> Networks -> Tunnels"
  type        = string
  default     = "k3s"
}

# Used by imports.tf, which is gitignored — invisible to CI, hence the ignore.
# tflint-ignore: terraform_unused_declarations
variable "tunnel_id" {
  description = "UUID of the existing tunnel, used by the import blocks in imports.tf"
  type        = string
}

variable "zones" {
  description = "Zone name -> zone ID. Every ingress hostname must fall under one of these."
  type        = map(string)
}

variable "ingress" {
  type = list(object({
    hostname = string
    service  = string
    path     = optional(string)
  }))
}

variable "catch_all_service" {
  description = "What the tunnel answers with for a hostname no rule matched."
  type        = string
  default     = "http_status:404"
}

variable "cluster_dns_records" {
  type = map(object({
    zone    = string
    name    = string
    source  = string
    ttl     = optional(number, 1)
    comment = optional(string, "terraform: cluster address")
  }))
  default = {}
}

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
