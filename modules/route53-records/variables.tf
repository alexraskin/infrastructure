variable "zone_id" {
  description = "Hosted zone the records go in"
  type        = string
}

variable "records" {
  description = "Key => record set. Names are FQDNs. Give records (with ttl) or alias, not both."
  type = map(object({
    name    = string
    type    = string
    ttl     = optional(number, 300)
    records = optional(list(string))
    alias = optional(object({
      name    = string
      zone_id = string
    }))
  }))

  validation {
    condition     = alltrue([for r in var.records : (r.records == null) != (r.alias == null)])
    error_message = "Each record needs exactly one of records or alias."
  }
}

variable "dnssec" {
  description = "Sign the zone (the root that owns it sets this once). publish_ds adds the registry DS record: only after the zone has been signed for its max TTL, 48h for the apex NS."
  type = object({
    domain     = string
    publish_ds = optional(bool, false)
  })
  default = null
}
