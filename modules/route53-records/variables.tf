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
