# The NFS server — a Debian LXC on the cluster's own bridge

locals {
  pve_host = regex("^https?://([^:/]+)", var.pve_endpoint)[0]

  cluster_subnet = "${cidrhost("${local.cluster.gateway}/${local.cluster.prefix}", 0)}/${local.cluster.prefix}"
}

resource "proxmox_virtual_environment_download_file" "debian_lxc" {
  content_type = "vztmpl"
  datastore_id = var.image_datastore
  node_name    = var.pve_node

  url                = "http://download.proxmox.com/images/system/debian-13-standard_13.6-1_amd64.tar.zst"
  checksum           = "4c0c27ca6ceab5ef0b84db57825a00f26157ef1854bafe97297813e1cbe8ecb8cc9c453cab6b3b0efe1ba193a50c47ece1e41d950e411b8730b835b71e9e754b"
  checksum_algorithm = "sha512"

  overwrite = false
}

resource "proxmox_virtual_environment_container" "nfs" {
  description = "NFS server for Kubernetes RWX volumes — managed by Terraform"
  tags        = sort(["kubernetes", "nfs", "storage", "terraform"])

  node_name = var.pve_node
  vm_id     = var.nfs.vmid

  started       = true
  start_on_boot = true

  unprivileged = false

  cpu {
    cores = var.nfs.cores
  }

  memory {
    dedicated = var.nfs.memory
  }

  disk {
    datastore_id = var.vm_datastore
    size         = var.nfs.root_disk
  }
  mount_point {
    volume = var.vm_datastore
    size   = "${var.nfs.data_disk}G"
    path   = var.nfs.export_path
    backup = true
  }

  initialization {
    hostname = var.nfs.name

    ip_config {
      ipv4 {
        address = "${var.nfs.ip}/${local.cluster.prefix}"
        gateway = local.cluster.gateway
      }
    }

    dns {
      domain  = local.cluster.domain
      servers = local.cluster.nameservers
    }
  }

  network_interface {
    name    = "eth0"
    bridge  = var.network_bridge
    vlan_id = var.vlan_id
  }

  operating_system {
    template_file_id = proxmox_virtual_environment_download_file.debian_lxc.id
    type             = "debian"
  }

  provisioner "local-exec" {
    command = "${path.module}/../../scripts/nfs-provision.sh"

    environment = {
      PVE_HOST    = local.pve_host
      PVE_USER    = var.pve_ssh_username
      VMID        = var.nfs.vmid
      EXPORT_PATH = var.nfs.export_path
      EXPORT_TO   = local.cluster_subnet
    }
  }

  lifecycle {
    ignore_changes = [
      mount_point[0].volume,
      operating_system[0].template_file_id,
      features,
    ]
  }
}

output "nfs_server" {
  description = "Where the NFS export lives, for the StorageClass in apps/base/csi-driver-nfs/"
  value = {
    host   = var.nfs.ip
    share  = var.nfs.export_path
    vmid   = proxmox_virtual_environment_container.nfs.vm_id
    backed = "vzdump, via the nightly job"
  }
}
