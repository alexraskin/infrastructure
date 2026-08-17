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

variable "waf_enabled" {
  description = "Whether to manage the WAF rulesets of every zone in var.zones."
  type        = bool
  default     = true
}

variable "waf_extra_hosts" {
  description = "Hostnames the read-only rule covers beyond the tunnel's own. Only a proxied hostname ever reaches the WAF."
  type        = list(string)
  default     = []
}

variable "waf_blocked_paths" {
  description = "Path substrings that get a 403. Matched against lower(path); the Free plan has no regex."
  type        = list(string)
  default = [
    "/wp-admin",
    "/wp-login",
    "/wp-content",
    "/wp-includes",
    "/xmlrpc.php",
    "/.env",
    "/.git/",
    "/.aws/",
    "/.ssh/",
    "/phpmyadmin",
    "/vendor/phpunit",
    "/cgi-bin/",
    "/administrator/",
  ]
}

variable "waf_blocked_user_agents" {
  description = "User-Agent substrings that get a 403. Matched against lower(user_agent)."
  type        = list(string)
  default = [
    "ahrefsbot",
    "amazonbot",
    "bytespider",
    "ccbot",
    "dataforseobot",
    "dotbot",
    "gptbot",
    "imagesiftbot",
    "mj12bot",
    "petalbot",
    "semrushbot",
  ]
}

variable "waf_rate_limit" {
  description = "Per-IP flood control. The Free plan fixes the period and the mitigation timeout at 10s, allows one rule, and takes no action other than block."
  type = object({
    enabled             = optional(bool, true)
    requests_per_period = optional(number, 100)
    action              = optional(string, "block")
  })
  default = {}

  validation {
    condition     = contains(["block", "managed_challenge", "js_challenge", "challenge"], var.waf_rate_limit.action)
    error_message = "action must be block, managed_challenge, js_challenge or challenge, and everything but block needs a paid plan: the API answers with \"not entitled to use the <action> action in ratelimiting\"."
  }
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
