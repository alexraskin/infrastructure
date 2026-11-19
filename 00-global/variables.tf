variable "region" {
  description = "Region the state bucket lives in"
  type        = string
  default     = "us-east-1"
}

variable "state_bucket" {
  description = "S3 bucket holding every root's state, under infrastructure/"
  type        = string
  default     = "alexraskin-tfstate"
}

variable "repository" {
  description = "GitHub repository whose workflows assume the CI roles"
  type        = string
  default     = "alexraskin/infrastructure"
}

variable "domain" {
  description = "The hosted zone this root owns"
  type        = string
  default     = "alexraskin.com"
}

variable "dnssec_publish_ds" {
  description = "Publish the DS record at the registry (modules/route53-records). Only after the zone has been signed for 48h."
  type        = bool
  default     = false
}
