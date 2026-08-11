locals {
  cluster = var.cluster
  nodes   = var.nodes
}

resource "proxmox_virtual_environment_vm" "node" {
  for_each = local.nodes

  name        = each.key
  description = "Talos ${each.value.role} — VM by Terraform, OS configured by talos_machine_configuration_apply.${each.key}"
  tags        = sort(["talos", each.value.role, "terraform"])
  vm_id       = each.value.vmid
  node_name   = var.pve_node

  on_boot = true
  started = true

  # The extension is in the image factory schematic; without it Proxmox never
  # learns the guest's address and a shutdown is a hard stop.
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

  # Blank disk. Talos installs itself onto it from the ISO on first boot —
  # there is no image to import and no cloud-init drive, because Talos takes
  # its entire configuration over its own API.
  disk {
    datastore_id = var.vm_datastore
    file_format  = var.disk_format
    interface    = "scsi0"
    size         = each.value.disk
    discard      = "on"
    ssd          = true
    iothread     = true
  }

  # Second disk on the db nodes only, picked up by the `db` UserVolumeConfig
  # and mounted at /var/mnt/db.
  dynamic "disk" {
    for_each = each.value.data_disk == null ? [] : [each.value.data_disk]

    content {
      datastore_id = var.vm_datastore
      file_format  = var.disk_format
      interface    = "scsi1"
      size         = disk.value
      discard      = "on"
      ssd          = true
      iothread     = true
    }
  }

  cdrom {
    file_id = proxmox_virtual_environment_download_file.talos_iso.id
  }

  boot_order = ["scsi0", "ide3"]

  network_device {
    bridge  = var.network_bridge
    model   = "virtio"
    vlan_id = var.vlan_id
  }

  operating_system {
    type = "l26"
  }

  serial_device {}

  lifecycle {
    # A Talos version bump changes the ISO, and the VM has to come back up on
    # it to be reinstalled.
    replace_triggered_by = [
      proxmox_virtual_environment_download_file.talos_iso.id,
    ]
  }
}
