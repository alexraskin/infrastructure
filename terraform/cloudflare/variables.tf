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
  description = <<-EOT
    Public hostname -> in-cluster origin, in order. This is the whole tunnel
    config: the last rule is generated automatically as the required catch-all,
    so do not add one. `service` is what cloudflared dials, normally the cluster
    DNS name of a Service: http://<service>.<namespace>.svc.cluster.local:<port>.
    Each entry also gets its proxied CNAME in the matching zone.
  EOT
  type = list(object({
    hostname = string
    service  = string
    path     = optional(string)
  }))
}

variable "catch_all_service" {
  description = "What the tunnel answers with for a hostname no rule matched. http_status:404 refuses; a URL would make every unrouted host hit that origin."
  type        = string
  default     = "http_status:404"
}

variable "extra_dns_records" {
  description = <<-EOT
    Records that have nothing to do with the tunnel (MX, verification TXT, an
    apex A record elsewhere) but should still live in code. Keyed by an
    arbitrary name used only in state.
  EOT
  type = map(object({
    zone    = string
    name    = string
    type    = string
    content = string
    ttl     = optional(number, 1)
    proxied = optional(bool, false)
    comment = optional(string)
  }))
  default = {}
}
