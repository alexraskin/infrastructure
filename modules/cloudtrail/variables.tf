variable "name" {
  description = "Trail name; the bucket is <name>-<account_id>"
  type        = string
}

variable "retention_days" {
  description = "Days log objects are kept in S3"
  type        = number
  default     = 90
}

variable "discord_webhook_url" {
  description = "Discord webhook that security-relevant events are posted to"
  type        = string
  sensitive   = true
}
