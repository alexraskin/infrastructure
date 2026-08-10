locals {
  nas_storages = {
    backups = {
      export  = "/volume1/proxmox_backups"
      content = ["backup", "images", "iso", "rootdir"]
    }
    iso = {
      export  = "/volume1/ios-images"
      content = ["images", "iso", "rootdir"]
    }
  }
}

resource "proxmox_storage_nfs" "nas" {
  for_each = local.nas_storages

  id      = each.key
  server  = var.nas_server
  export  = each.value.export
  content = each.value.content

  backups {
    keep_all = true
  }
}
