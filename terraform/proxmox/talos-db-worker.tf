locals {
  db_patch = yamlencode({
    machine = {
      nodeLabels = { dedicated = "database" }
      kubelet = {
        extraArgs = { "register-with-taints" = "dedicated=database:NoSchedule" }
      }
    }
  })

  db_volume_patch = yamlencode({
    apiVersion = "v1alpha1"
    kind       = "UserVolumeConfig"
    name       = "db"
    provisioning = {
      diskSelector = { match = "!system_disk" }
      minSize      = "1GB"
    }
    filesystem = { type = "xfs" }
  })
}
