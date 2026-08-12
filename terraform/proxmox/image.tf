resource "talos_image_factory_schematic" "this" {
  schematic = yamlencode({
    customization = {
      systemExtensions = {
        officialExtensions = local.cluster.extensions
      }
    }
  })
}

data "talos_image_factory_urls" "this" {
  talos_version = local.cluster.talos_version
  schematic_id  = talos_image_factory_schematic.this.id
  platform      = "metal"
  architecture  = "amd64"
}

resource "proxmox_virtual_environment_download_file" "talos_iso" {
  content_type = "iso"
  datastore_id = var.image_datastore
  node_name    = var.pve_node

  url       = data.talos_image_factory_urls.this.urls.iso
  file_name = "talos-${local.cluster.talos_version}-${substr(talos_image_factory_schematic.this.id, 0, 8)}.iso"

  overwrite = false
}
