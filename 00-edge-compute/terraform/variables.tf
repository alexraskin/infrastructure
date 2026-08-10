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
  description = <<-EOT
    Explicit AD name, overriding the index below. Always-free A1 capacity is
    scarce and uneven across ADs; "Out of host capacity" at apply time is the
    normal failure, not a misconfiguration. `mise run tf:apply` retries each AD
    in turn on that error.
  EOT
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
  description = <<-EOT
    Who may reach port 22 on the public IP. 0.0.0.0/0 by default because the
    box has to be installable before Tailscale exists on it. Narrow it once
    `mise run deploy` has run — trustedInterfaces = [ "tailscale0" ] keeps
    tailnet SSH working.
  EOT
  type        = string
  default     = "0.0.0.0/0"
}

# ---------------------------------------------------------------------- ssh ---

variable "ssh_public_key" {
  description = <<-EOT
    Installed for root by cloud-init, before NixOS exists, and used by
    `mise run install`. Must match nixos/hosts/edge-1/ssh-keys.nix, or the
    install succeeds and then locks you out.
  EOT
  type        = string
}

# --------------------------------------------------------------- cloudflare ---

variable "cloudflare_api_token" {
  description = <<-EOT
    Read from secrets/cloudflare-api-token — the same custom token the tunnel
    root uses (Zone/DNS/Edit + Zone/Zone/Read are what matter here). It is also
    pushed to the instance for ACME DNS-01, which is the one place it leaves
    this machine.
  EOT
  type        = string
  sensitive   = true
}
