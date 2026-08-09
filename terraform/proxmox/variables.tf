variable "pve_endpoint" {
  description = "Proxmox VE API endpoint, e.g. https://pve2.lan:8006/"
  type        = string
}

variable "pve_api_token" {
  description = "API token in the form user@realm!tokenid=uuid"
  type        = string
  sensitive   = true
}

variable "pve_insecure" {
  description = "Skip TLS verification (self-signed PVE cert)"
  type        = bool
  default     = true
}

variable "pve_node" {
  description = "Proxmox node the VMs are created on"
  type        = string
}

variable "pve_ssh_username" {
  description = "SSH user on the Proxmox node, used by the provider for disk operations"
  type        = string
  default     = "root"
}

variable "pve_ssh_private_key_path" {
  description = "Private key the provider uses for SSH to the node. Empty string falls back to ssh-agent."
  type        = string
  default     = "~/.ssh/id_ed25519"
}

variable "image_datastore" {
  description = "Datastore holding the uploaded NixOS disk image (needs 'iso' content type)"
  type        = string
  default     = "local"
}

variable "vm_datastore" {
  description = "Datastore for VM disks and cloud-init drives"
  type        = string
  default     = "local-lvm"
}

variable "nixos_image_path" {
  description = "Path to the qcow2 built by `mise run image`"
  type        = string
  default     = "../../build/nixos.qcow2"
}

variable "upload_image" {
  description = "Let Terraform push the image through the PVE HTTP API. Set false and use `mise run push-image` for large images or slow links."
  type        = bool
  default     = true
}

variable "image_upload_timeout" {
  description = "Seconds allowed for the API upload of the image (a 2GB image over a WAN link needs well over the 1800s default)"
  type        = number
  default     = 7200
}

variable "disk_format" {
  description = "On-datastore disk format: raw for LVM/ZFS/Ceph, qcow2 for directory storage"
  type        = string
  default     = "raw"

  validation {
    condition     = contains(["raw", "qcow2"], var.disk_format)
    error_message = "disk_format must be raw or qcow2."
  }
}

variable "network_bridge" {
  description = "Proxmox bridge to attach VMs to"
  type        = string
  default     = "vmbr0"
}

variable "vlan_id" {
  description = "VLAN tag for the VM NIC, null for untagged"
  type        = number
  default     = null
}

variable "ssh_public_key_path" {
  description = "Public key injected via cloud-init for first-boot access"
  type        = string
  default     = "~/.ssh/id_ed25519.pub"
}

variable "cpu_type" {
  description = "QEMU CPU model"
  type        = string
  default     = "host"
}
