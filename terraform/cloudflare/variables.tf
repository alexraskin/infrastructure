variable "account_id" {
  description = "Cloudflare account ID that owns the tunnel"
  type        = string
}

variable "tunnel_name" {
  description = "Name of the existing tunnel, as it appears in Zero Trust -> Networks -> Tunnels"
  type        = string
  default     = "k3s"
}

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

variable "oci_namespace" {
  description = "Object Storage namespace holding the state bucket"
  type        = string
}

variable "oci_region" {
  description = "Region the state bucket lives in"
  type        = string
}

variable "oci_tenancy_ocid" {
  description = "Tenancy OCID"
  type        = string
}

variable "oci_user_ocid" {
  description = "OCID of the user whose API key signs the state read"
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
