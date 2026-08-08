locals {
  hosts   = jsondecode(file("${path.module}/../hosts.json"))
  cluster = local.hosts.cluster
  nodes   = local.hosts.nodes
}

# The golden NixOS image, uploaded once and used as the backing disk for every VM.
# Content type "iso" is the datastore slot Proxmox accepts arbitrary disk images in;
# the .img suffix is required for it to be listed as importable.
#
# "iso" always goes through the HTTP API (upload_mode does not apply), which is
# slow and unresumable for a multi-GB image over a WAN link. Set upload_image =
# false and run `mise run push-image` to rsync it to the node instead.
resource "proxmox_virtual_environment_file" "nixos_image" {
  count = var.upload_image ? 1 : 0

  content_type   = "iso"
  datastore_id   = var.image_datastore
  node_name      = var.pve_node
  timeout_upload = var.image_upload_timeout
  overwrite      = true

  source_file {
    path      = var.nixos_image_path
    file_name = local.image_file_name
  }
}

locals {
  image_file_name = "nixos-k3s-base.img"

  # Either the file Terraform just uploaded, or the one `mise run push-image` put
  # on the node. Same volume id either way.
  image_file_id = var.upload_image ? one(proxmox_virtual_environment_file.nixos_image[*].id) : "${var.image_datastore}:iso/${local.image_file_name}"
}

resource "proxmox_virtual_environment_vm" "node" {
  for_each = local.nodes

  name        = each.key
  description = "k3s ${each.value.role} — managed by Terraform, configured by nixosConfigurations.${each.key}"
  tags        = sort(["k3s", each.value.role, "terraform"])
  vm_id       = each.value.vmid
  node_name   = var.pve_node

  on_boot = true
  started = true

  agent {
    enabled = true
  }

  cpu {
    cores = each.value.cores
    type  = var.cpu_type
  }

  memory {
    dedicated = each.value.memory
  }

  scsi_hardware = "virtio-scsi-single"

  disk {
    datastore_id = var.vm_datastore
    file_id      = local.image_file_id
    file_format  = var.disk_format
    interface    = "scsi0"
    size         = each.value.disk
    discard      = "on"
    ssd          = true
    iothread     = true
  }

  network_device {
    bridge  = var.network_bridge
    vlan_id = var.vlan_id
  }

  # First-boot identity only. After `mise run deploy` the NixOS config owns the
  # network, and these values are never read again.
  initialization {
    datastore_id = var.vm_datastore
    interface    = "ide2"

    ip_config {
      ipv4 {
        address = "${each.value.ip}/${local.cluster.prefix}"
        gateway = local.cluster.gateway
      }
    }

    dns {
      domain  = local.cluster.domain
      servers = local.cluster.nameservers
    }

    user_account {
      username = "root"
      keys     = [trimspace(file(pathexpand(var.ssh_public_key_path)))]
    }
  }

  operating_system {
    type = "l26"
  }

  serial_device {}

  lifecycle {
    ignore_changes = [
      # Rebuilding the image must not recreate running cluster members.
      disk[0].file_id,
    ]
  }
}
