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
