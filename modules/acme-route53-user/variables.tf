variable "name" {
  description = "IAM user name"
  type        = string
}

variable "zone_id" {
  description = "Hosted zone the challenges are written to"
  type        = string
}

variable "domains" {
  description = "Names the user may answer DNS-01 for; a leading *. is the wildcard's base"
  type        = list(string)
}
