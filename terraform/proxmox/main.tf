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
    file_format  = var.disk_format
    interface    = "scsi0"
    size         = each.value.disk
    discard      = "on"
    ssd          = true
    iothread     = true
    # Control plane disks hold etcd: unsafe keeps its fsync off the
    # slow flush path of the single host NVMe (applied live 2026-11-08; writeback tried first, did not stop the stalls).
    cache = each.value.role == "controlplane" ? "unsafe" : "none"
  }

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

  # Mapped, not usb.host: PVE only lets root@pam (not an API token) pass a raw host device.
  dynamic "usb" {
    for_each = each.value.usb == null ? [] : [proxmox_hardware_mapping_usb.node[each.key].name]

    content {
      mapping = usb.value
    }
  }

  cdrom {
    file_id = proxmox_download_file.talos_iso.id
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

  # Talos upgrades in place (mise run upgrade); a new ISO only swaps the CD-ROM media.
  reboot_after_update = false
}
