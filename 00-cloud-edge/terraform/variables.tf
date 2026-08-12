# ------------------------------------------------------------------ oracle ---

variable "oci_tenancy_ocid" {
  description = "OCID of the tenancy"
  type        = string
}

variable "oci_user_ocid" {
  description = "OCID of the user the API signing key belongs to"
  type        = string
}

variable "oci_fingerprint" {
  description = "Fingerprint of the API signing key, as shown under User -> API keys"
  type        = string
}

variable "oci_private_key_path" {
  description = "Path to the PEM API signing key (~ is expanded)"
  type        = string
}

variable "oci_region" {
  description = "OCI region. Pick the one nearest home — every Plex byte crosses it twice."
  type        = string
}

variable "oci_compartment_ocid" {
  description = "Compartment for the instance and its network. The tenancy OCID (the root compartment) works."
  type        = string
}

# --------------------------------------------------------------- placement ---

variable "instance_availability_domain" {
  type        = string
  default     = ""
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

# ---------------------------------------------------------------- networking --

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

variable "ssh_ingress_cidr" {
  type        = string
  default     = "0.0.0.0/0"
}

# ---------------------------------------------------------------------- ssh ---

variable "ssh_public_key" {
  type        = string
}

# --------------------------------------------------------------- cloudflare ---

variable "cloudflare_api_token" {
  type        = string
  sensitive   = true
}
