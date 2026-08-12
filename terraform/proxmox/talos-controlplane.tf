locals {
  controlplanes = { for n, v in local.nodes : n => v if v.role == "controlplane" }
  bootstrap_ip  = local.nodes[local.cluster.bootstrap].ip

  cluster_patch = yamlencode({
    cluster = {
      network = { cni = { name = "none" } }
      proxy   = { disabled = true }
      apiServer = {
        certSANs = local.cert_sans
      }
      controllerManager = { extraArgs = { "bind-address" = "0.0.0.0" } }
      scheduler         = { extraArgs = { "bind-address" = "0.0.0.0" } }
      etcd              = { extraArgs = { "listen-metrics-urls" = "http://0.0.0.0:2381" } }
    }
  })
}

data "talos_client_configuration" "this" {
  cluster_name         = local.cluster.name
  client_configuration = talos_machine_secrets.this.client_configuration
  endpoints            = [for n, v in local.controlplanes : v.ip]
  nodes                = [for n, v in local.nodes : v.ip]
}

resource "talos_machine_bootstrap" "this" {
  client_configuration = talos_machine_secrets.this.client_configuration
  node                 = local.bootstrap_ip
  endpoint             = local.bootstrap_ip

  depends_on = [time_sleep.install]
}

resource "talos_cluster_kubeconfig" "this" {
  client_configuration = talos_machine_secrets.this.client_configuration
  node                 = local.bootstrap_ip
  endpoint             = local.bootstrap_ip

  depends_on = [talos_machine_bootstrap.this]
}
