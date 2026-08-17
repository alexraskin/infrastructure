variable "instance_availability_domain" {
  type    = string
  default = ""
}

variable "instance_availability_domain_index" {
  description = "Zero-based AD index used when no explicit AD is given"
  type        = number
  default     = 0

  validation {
    condition     = var.instance_availability_domain_index >= 0
    error_message = "instance_availability_domain_index must be >= 0."
  }
}

variable "vcn_cidr" {
  description = "CIDR for the VCN. Must not overlap 10.0.200.0/24 (the home LAN reached over Tailscale) or the flannel range."
  type        = string
  default     = "10.80.0.0/16"
}

variable "public_subnet_cidr" {
  description = "CIDR for the public subnet"
  type        = string
  default     = "10.80.1.0/24"
}

# variable "ssh_ingress_cidr" {
#   type        = string
#   default     = "0.0.0.0/0"
# }
