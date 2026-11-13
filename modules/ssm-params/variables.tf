variable "group" {
  description = "Path segment under /infrastructure/ — one per consumer"
  type        = string
}

variable "parameters" {
  description = "Parameter name => description"
  type        = map(string)
}
