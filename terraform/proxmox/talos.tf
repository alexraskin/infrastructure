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

  # Hostname is a document, not a v1alpha1 field. Talos 1.13 always generates a
  # `HostnameConfig` with `auto: stable`, and it refuses a config that also sets
  # machine.network.hostname ("static hostname is already set in v1alpha1
  # config"). `auto` and `hostname` are mutually exclusive within the document
  # too, so turning auto off is part of setting a static name, not an extra.
  hostname_patch = {
    for name, node in local.nodes : name => yamlencode({
      apiVersion = "v1alpha1"
      kind       = "HostnameConfig"
      auto       = "off"
      hostname   = name
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

  # One Talos user volume per static PV in apps/base/local-path/, mounted at
  # /var/mnt/<name>. Two Talos facts force this shape:
  #
  #   - /var/mnt is read-only, so a hostPath PV with DirectoryOrCreate cannot
  #     create its own directory — only a user volume puts one there.
  #   - kubelet applies fsGroup ownership to `local` volumes but not to
  #     hostPath ones, so a hostPath PV stays root-owned and every chart that
  #     runs as a non-root uid fails on it. Prometheus is the loud one:
  #     "open /prometheus/queries.active: permission denied".
  #
  # `directory` is the no-extra-disk volume type — it carves the path out of the
  # EPHEMERAL partition. One per claim rather than one shared parent, because a
  # `local` PV binds a directory and two claims cannot share one.
  pv_volumes = ["prometheus", "loki"]

  pv_volume_patches = [
    for volume in local.pv_volumes : yamlencode({
      apiVersion = "v1alpha1"
      kind       = "UserVolumeConfig"
      name       = volume
      volumeType = "directory"
    })
  ]

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

  # cluster_patch is control-plane only: etcd, the scheduler and the
  # controller-manager do not exist on a worker, and Talos rejects the whole
  # config rather than ignoring them ("etcd config is only allowed on control
  # plane machines"). The CNI and proxy settings in it are read when the control
  # plane renders its manifests, so workers need no copy.
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

# Endpoints are the real node addresses, never the VIP: the VIP is bound to
# etcd and apiserver health, and a cluster broken badly enough to need talosctl
# is exactly a cluster whose VIP is gone.
data "talos_client_configuration" "this" {
  cluster_name         = local.cluster.name
  client_configuration = talos_machine_secrets.this.client_configuration
  endpoints            = [for n, v in local.controlplanes : v.ip]
  nodes                = [for n, v in local.nodes : v.ip]
}

# Where a node answers *before* it has been configured. Addressing is static and
# lives in the machine config, so a node booted from the ISO sits in maintenance
# mode on whatever DHCP gave it — not on the address below in `local.nodes`.
# The qemu-guest-agent extension is in the factory schematic, so Proxmox already
# knows that address; this reads it back rather than guessing.
locals {
  apply_ip = {
    for name, vm in proxmox_virtual_environment_vm.node : name => (
      # Configured already: it answers on its own static address, which is the
      # only stable one. Preferring it explicitly matters because a control
      # plane node also reports the VIP, and every node reports a Cilium
      # address — picking "the first non-loopback" would eventually grab one.
      contains(flatten(vm.ipv4_addresses), local.nodes[name].ip)
      ? local.nodes[name].ip
      # Still in maintenance mode: wherever DHCP put it.
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

# The control plane has to finish installing and come back on its static address
# before etcd can be bootstrapped. The apply above returns as soon as the config
# is accepted, which is well before the node has rebooted onto it.
resource "time_sleep" "install" {
  depends_on      = [talos_machine_configuration_apply.node]
  create_duration = "180s"
}

resource "talos_machine_bootstrap" "this" {
  client_configuration = talos_machine_secrets.this.client_configuration
  node                 = local.bootstrap_ip
  endpoint             = local.bootstrap_ip

  depends_on = [time_sleep.install]
}

# Retrieved over the Talos API, so this succeeds while every node is still
# NotReady for want of a CNI — which is the state `mise run cilium` fixes.
resource "talos_cluster_kubeconfig" "this" {
  client_configuration = talos_machine_secrets.this.client_configuration
  node                 = local.bootstrap_ip
  endpoint             = local.bootstrap_ip

  depends_on = [talos_machine_bootstrap.this]
}
