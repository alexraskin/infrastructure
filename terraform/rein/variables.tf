variable "hetzner_token" {
  description = "The Hetzner Cloud API token"
  type        = string
}

variable "ssh_public_key_name" {
  description = "The SSH public key to use for the server"
  type        = string
}

variable "server_username" {
  description = "The username to create on the server"
  type        = string
}

variable "server_type" {
  description = "The server type to use"
  type        = string
  default     = "cpx21"
}

variable "location" {
  description = "The location to create the server in"
  type        = string
}

variable "image" {
  description = "The image to use for the server"
  type        = string
  default     = "debian-12"
}

variable "server_name" {
  description = "The name of the server"
  type        = string
}

variable "cloudflare_api_key" {
  description = "The Cloudflare API key"
  type        = string

}

variable "tailscale_auth_key" {
  description = "The Tailscale auth key"
  type        = string
}
