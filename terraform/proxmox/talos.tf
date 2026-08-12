locals {
  install_image = "factory.talos.dev/installer/${talos_image_factory_schematic.this.id}:${local.cluster.talos_version}"

  cert_sans = [local.cluster.vip, "${local.cluster.name}.${local.cluster.domain}"]

  cluster_endpoint = "https://${local.cluster.vip}:6443"

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

  hostname_patch = {
    for name, node in local.nodes : name => yamlencode({
      apiVersion = "v1alpha1"
      kind       = "HostnameConfig"
      auto       = "off"
      hostname   = name
    })
  }

  node_patches = {
    for name, node in local.nodes : name => concat(
      [local.common_patch[name], local.hostname_patch[name]],
      node.role == "controlplane" ? [local.cluster_patch] : local.pv_volume_patches,
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

locals {
  apply_ip = {
    for name, vm in proxmox_virtual_environment_vm.node : name => (
      contains(flatten(vm.ipv4_addresses), local.nodes[name].ip)
      ? local.nodes[name].ip
      : try([
        for addr in flatten(vm.ipv4_addresses) : addr
        if addr != "127.0.0.1"
        && !startswith(addr, "169.254.")
        && addr != local.cluster.vip
      ][0], local.nodes[name].ip)
    )
  }
}

resource "talos_machine_configuration_apply" "node" {
  for_each = local.nodes

  client_configuration        = talos_machine_secrets.this.client_configuration
  machine_configuration_input = data.talos_machine_configuration.node[each.key].machine_configuration
  node                        = local.apply_ip[each.key]
  endpoint                    = local.apply_ip[each.key]

  depends_on = [proxmox_virtual_environment_vm.node]

  lifecycle {
    replace_triggered_by = [proxmox_virtual_environment_vm.node[each.key].id]
  }
}

resource "time_sleep" "install" {
  depends_on      = [talos_machine_configuration_apply.node]
  create_duration = "180s"
}
