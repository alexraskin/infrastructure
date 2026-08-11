locals {
  controlplanes = { for n, v in local.nodes : n => v if v.role == "controlplane" }
  bootstrap_ip  = local.nodes[local.cluster.bootstrap].ip

  # The VIP, not a node address: it is what new nodes join through and what the
  # kubeconfig points at. It only answers once etcd is up, which is why it must
  # never be used as a *Talos* API endpoint (see data.talos_client_configuration).
  cluster_endpoint = "https://${local.cluster.vip}:6443"

  install_image = "factory.talos.dev/installer/${talos_image_factory_schematic.this.id}:${local.cluster.talos_version}"

  cert_sans = [local.cluster.vip, "${local.cluster.name}.${local.cluster.domain}"]

  # Identity and addressing, per node. The NIC is matched by driver rather than
  # by name — naming it is the mistake that stranded nodes under NixOS.
  common_patch = {
    for name, node in local.nodes : name => yamlencode({
      machine = {
        install = {
          disk  = local.cluster.install_disk
          image = local.install_image
        }
        certSANs = local.cert_sans
        features = {
          kubePrism = {
            enabled = true
            port    = 7445
          }
        }
        network = {
          hostname    = name
          nameservers = local.cluster.nameservers
          interfaces = [
            merge(
              {
                deviceSelector = { driver = "virtio_net" }
                addresses      = ["${node.ip}/${local.cluster.prefix}"]
                routes = [{
                  network = "0.0.0.0/0"
                  gateway = local.cluster.gateway
                }]
              },
              node.role == "controlplane" ? { vip = { ip = local.cluster.vip } } : {},
            )
          ]
        }
      }
    })
  }

  # Cilium replaces both the CNI and kube-proxy, so Talos must ship neither.
  # The bind-address/listen-metrics-urls arguments are what makes
  # kube-prometheus-stack's controller-manager, scheduler and etcd targets
  # reachable from a pod instead of 127.0.0.1-only.
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

  # db nodes: labelled and tainted, so nothing lands there without asking for it.
  db_patch = yamlencode({
    machine = {
      nodeLabels = { dedicated = "database" }
      kubelet = {
        extraArgs = { "register-with-taints" = "dedicated=database:NoSchedule" }
      }
    }
  })

  # Their second disk, as its own configuration document. Talos partitions it,
  # labels the partition u-db and mounts it at /var/mnt/db — which, unlike
  # /var itself, survives a reinstall or `talosctl upgrade --wipe`.
  # maxSize is left unset on purpose: the volume then grows to the whole disk,
  # so resizing a db node is a change to cluster.auto.tfvars.json and nothing else.
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

  node_patches = {
    for name, node in local.nodes : name => concat(
      [local.common_patch[name], local.cluster_patch],
      node.role == "db" ? [local.db_patch, local.db_volume_patch] : [],
    )
  }
}

resource "talos_machine_secrets" "this" {
  talos_version = local.cluster.talos_version
}

data "talos_machine_configuration" "node" {
  for_each = local.nodes

  cluster_name     = local.cluster.name
  cluster_endpoint = local.cluster_endpoint
  machine_type     = each.value.role == "controlplane" ? "controlplane" : "worker"
  machine_secrets  = talos_machine_secrets.this.machine_secrets

  talos_version      = local.cluster.talos_version
  kubernetes_version = local.cluster.kubernetes_version

  config_patches = local.node_patches[each.key]
}

# Endpoints are the real node addresses, never the VIP: the VIP is bound to
# etcd and apiserver health, and a cluster broken badly enough to need talosctl
# is exactly a cluster whose VIP is gone.
data "talos_client_configuration" "this" {
  cluster_name         = local.cluster.name
  client_configuration = talos_machine_secrets.this.client_configuration
  endpoints            = [for n, v in local.controlplanes : v.ip]
  nodes                = [for n, v in local.nodes : v.ip]
}

resource "talos_machine_configuration_apply" "node" {
  for_each = local.nodes

  client_configuration        = talos_machine_secrets.this.client_configuration
  machine_configuration_input = data.talos_machine_configuration.node[each.key].machine_configuration
  node                        = each.value.ip
  endpoint                    = each.value.ip

  depends_on = [proxmox_virtual_environment_vm.node]

  lifecycle {
    replace_triggered_by = [proxmox_virtual_environment_vm.node[each.key].id]
  }
}

resource "talos_machine_bootstrap" "this" {
  client_configuration = talos_machine_secrets.this.client_configuration
  node                 = local.bootstrap_ip
  endpoint             = local.bootstrap_ip

  depends_on = [talos_machine_configuration_apply.node]
}

# Retrieved over the Talos API, so this succeeds while every node is still
# NotReady for want of a CNI — which is the state `mise run cilium` fixes.
resource "talos_cluster_kubeconfig" "this" {
  client_configuration = talos_machine_secrets.this.client_configuration
  node                 = local.bootstrap_ip
  endpoint             = local.bootstrap_ip

  depends_on = [talos_machine_bootstrap.this]
}
