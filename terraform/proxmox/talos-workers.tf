locals {
  pv_volumes = ["prometheus", "loki"]

  pv_volume_patches = [
    for volume in local.pv_volumes : yamlencode({
      apiVersion = "v1alpha1"
      kind       = "UserVolumeConfig"
      name       = volume
      volumeType = "directory"
    })
  ]
}
