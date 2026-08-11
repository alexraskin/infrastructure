# The cluster itself, in cluster.auto.tfvars.json — auto-loaded, and JSON rather
# than HCL so `jq` can still read it: mise tasks and preflight.sh work from the
# same file Terraform does, exactly as they did when it was hosts.json.
variable "cluster" {
  description = "Cluster-wide settings: addressing, versions, install disk, image extensions"
  type = object({
    name               = string
    domain             = string
    vip                = string
    gateway            = string
    prefix             = number
    nameservers        = list(string)
    bootstrap          = string
    install_disk       = string
    talos_version      = string
    kubernetes_version = string
    extensions         = list(string)
  })
}

variable "nodes" {
  description = "Node name -> role, address, VM ID and size. data_disk is the db nodes' second disk."
  type = map(object({
    role      = string
    ip        = string
    vmid      = number
    cores     = number
    memory    = number
    disk      = number
    data_disk = optional(number)
  }))

  validation {
    condition     = contains(keys(var.nodes), var.cluster.bootstrap)
    error_message = "cluster.bootstrap must name one of the nodes."
  }

  validation {
    condition     = alltrue([for n in var.nodes : contains(["controlplane", "worker", "db"], n.role)])
    error_message = "node role must be controlplane, worker or db."
  }
}

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
  description = "Datastore the Talos ISO is downloaded to (needs 'iso' content type)"
  type        = string
  default     = "local"
}

variable "vm_datastore" {
  description = "Datastore for VM disks"
  type        = string
  default     = "local-lvm"
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

variable "cpu_type" {
  description = "QEMU CPU model"
  type        = string
  default     = "host"
}

variable "backup_storage" {
  description = "Storage the nightly vzdump writes to (the NFS export on the NAS)"
  type        = string
  default     = "backups"
}

variable "backup_schedule" {
  description = "systemd calendar event for the backup job, in the PVE host's local timezone"
  type        = string
  default     = "*-*-* 02:30"
}

variable "backup_enabled" {
  description = "Whether the backup job runs on schedule"
  type        = bool
  default     = true
}

variable "backup_retention" {
  description = "Job-level prune policy, overriding the storage's own prune-backups"
  type        = map(string)
  default = {
    "keep-daily"   = "7"
    "keep-weekly"  = "4"
    "keep-monthly" = "3"
  }
}

variable "nas_server" {
  description = "NFS server backing the backups and iso storages"
  type        = string
}

variable "pve_fqdn" {
  description = "Public hostname of the PVE host, the subject of its ACME certificate"
  type        = string
}

variable "acme_account" {
  description = "Name of the ACME account on the host that orders the certificate"
  type        = string
  default     = "default"
}

variable "acme_dns_plugin_data" {
  description = "Credentials for the acme.sh DNS plugin (CF_Account_ID, CF_Email, CF_Token)"
  type        = map(string)
  sensitive   = true
}

variable "pve_bridge_address" {
  description = "The PVE host's own address on the management bridge, CIDR form"
  type        = string
}

variable "pve_bridge_gateway" {
  description = "Default gateway on the management bridge"
  type        = string
}

variable "pve_bridge_port" {
  description = "Physical NIC enslaved to the management bridge"
  type        = string
}
