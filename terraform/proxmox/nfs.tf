# The NFS server — a Debian LXC on the cluster's own bridge, exporting a disk
# to the Kubernetes nodes as RWX storage.
#
# It is deliberately *not* the NAS. The NAS lives on 10.0.54.0/24 and the
# cluster on 10.0.200.0/24 with no route between them, and no amount of
# in-cluster configuration fixes that: an NFS mount is performed by the CSI
# node plugin in the node's own network namespace, so a Tailscale egress proxy
# cannot carry it either. This container is on the cluster's network, so it can.

locals {
  # The hostname the provider SSHes to, taken from the API endpoint.
  pve_host = regex("^https?://([^:/]+)", var.pve_endpoint)[0]

  # 10.0.200.0/24 — what the export is restricted to.
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

  # The kernel NFS server needs to manipulate mounts and load nfsd, which an
  # unprivileged container cannot do. This is the one guest here that is not
  # locked down, which is also why it exports to the cluster subnet only.
  unprivileged = false

  features {
    nesting = true
    mount   = ["nfs"]
  }

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

  # The exported volume, separate from the root filesystem so the OS can be
  # rebuilt without touching the data.
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

  # Installs nfs-kernel-server and writes /etc/exports. Runs through `pct exec`
  # on the PVE host rather than SSH into the container: the provider already
  # needs that SSH access, and this way the container needs no key of its own
  # and no sshd at all.
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
      # The provider reports the allocated volume id (local-lvm:vm-130-disk-1),
      # which never matches the datastore name given here.
      mount_point[0].volume,
      operating_system[0].template_file_id,
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
