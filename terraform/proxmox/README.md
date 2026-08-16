<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.12 |
| <a name="requirement_cloudflare"></a> [cloudflare](#requirement\_cloudflare) | ~> 5 |
| <a name="requirement_proxmox"></a> [proxmox](#requirement\_proxmox) | ~> 0.111 |
| <a name="requirement_sops"></a> [sops](#requirement\_sops) | ~> 1.4 |
| <a name="requirement_talos"></a> [talos](#requirement\_talos) | ~> 0.9 |
| <a name="requirement_time"></a> [time](#requirement\_time) | ~> 0.12 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_proxmox"></a> [proxmox](#provider\_proxmox) | 0.111.1 |
| <a name="provider_sops"></a> [sops](#provider\_sops) | 1.4.1 |
| <a name="provider_talos"></a> [talos](#provider\_talos) | 0.11.0 |
| <a name="provider_time"></a> [time](#provider\_time) | 0.14.1 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [proxmox_acme_certificate.host](https://registry.terraform.io/providers/bpg/proxmox/latest/docs/resources/acme_certificate) | resource |
| [proxmox_acme_dns_plugin.cloudflare](https://registry.terraform.io/providers/bpg/proxmox/latest/docs/resources/acme_dns_plugin) | resource |
| [proxmox_apt_standard_repository.no_subscription](https://registry.terraform.io/providers/bpg/proxmox/latest/docs/resources/apt_standard_repository) | resource |
| [proxmox_backup_job.cluster](https://registry.terraform.io/providers/bpg/proxmox/latest/docs/resources/backup_job) | resource |
| [proxmox_network_linux_bridge.vmbr0](https://registry.terraform.io/providers/bpg/proxmox/latest/docs/resources/network_linux_bridge) | resource |
| [proxmox_storage_directory.local](https://registry.terraform.io/providers/bpg/proxmox/latest/docs/resources/storage_directory) | resource |
| [proxmox_storage_lvmthin.local_lvm](https://registry.terraform.io/providers/bpg/proxmox/latest/docs/resources/storage_lvmthin) | resource |
| [proxmox_storage_nfs.nas](https://registry.terraform.io/providers/bpg/proxmox/latest/docs/resources/storage_nfs) | resource |
| [proxmox_virtual_environment_container.nfs](https://registry.terraform.io/providers/bpg/proxmox/latest/docs/resources/virtual_environment_container) | resource |
| [proxmox_virtual_environment_download_file.debian_lxc](https://registry.terraform.io/providers/bpg/proxmox/latest/docs/resources/virtual_environment_download_file) | resource |
| [proxmox_virtual_environment_download_file.talos_iso](https://registry.terraform.io/providers/bpg/proxmox/latest/docs/resources/virtual_environment_download_file) | resource |
| [proxmox_virtual_environment_user.metrics_exporter](https://registry.terraform.io/providers/bpg/proxmox/latest/docs/resources/virtual_environment_user) | resource |
| [proxmox_virtual_environment_user_token.metrics_exporter](https://registry.terraform.io/providers/bpg/proxmox/latest/docs/resources/virtual_environment_user_token) | resource |
| [proxmox_virtual_environment_vm.node](https://registry.terraform.io/providers/bpg/proxmox/latest/docs/resources/virtual_environment_vm) | resource |
| [talos_cluster_kubeconfig.this](https://registry.terraform.io/providers/siderolabs/talos/latest/docs/resources/cluster_kubeconfig) | resource |
| [talos_image_factory_schematic.this](https://registry.terraform.io/providers/siderolabs/talos/latest/docs/resources/image_factory_schematic) | resource |
| [talos_machine_bootstrap.this](https://registry.terraform.io/providers/siderolabs/talos/latest/docs/resources/machine_bootstrap) | resource |
| [talos_machine_configuration_apply.node](https://registry.terraform.io/providers/siderolabs/talos/latest/docs/resources/machine_configuration_apply) | resource |
| [talos_machine_secrets.this](https://registry.terraform.io/providers/siderolabs/talos/latest/docs/resources/machine_secrets) | resource |
| [time_sleep.install](https://registry.terraform.io/providers/hashicorp/time/latest/docs/resources/sleep) | resource |
| [sops_file.admin](https://registry.terraform.io/providers/carlpett/sops/latest/docs/data-sources/file) | data source |
| [talos_client_configuration.this](https://registry.terraform.io/providers/siderolabs/talos/latest/docs/data-sources/client_configuration) | data source |
| [talos_image_factory_urls.this](https://registry.terraform.io/providers/siderolabs/talos/latest/docs/data-sources/image_factory_urls) | data source |
| [talos_machine_configuration.node](https://registry.terraform.io/providers/siderolabs/talos/latest/docs/data-sources/machine_configuration) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_acme_account"></a> [acme\_account](#input\_acme\_account) | Name of the ACME account on the host that orders the certificate | `string` | `"default"` | no |
| <a name="input_acme_dns_plugin_data"></a> [acme\_dns\_plugin\_data](#input\_acme\_dns\_plugin\_data) | Credentials for the acme.sh DNS plugin (CF\_Account\_ID, CF\_Email, CF\_Token) | `map(string)` | n/a | yes |
| <a name="input_backup_enabled"></a> [backup\_enabled](#input\_backup\_enabled) | Whether the backup job runs on schedule | `bool` | `true` | no |
| <a name="input_backup_retention"></a> [backup\_retention](#input\_backup\_retention) | Job-level prune policy, overriding the storage's own prune-backups | `map(string)` | <pre>{<br/>  "keep-daily": "7",<br/>  "keep-monthly": "3",<br/>  "keep-weekly": "4"<br/>}</pre> | no |
| <a name="input_backup_schedule"></a> [backup\_schedule](#input\_backup\_schedule) | systemd calendar event for the backup job, in the PVE host's local timezone | `string` | `"*-*-* 02:30"` | no |
| <a name="input_backup_storage"></a> [backup\_storage](#input\_backup\_storage) | Storage the nightly vzdump writes to (the NFS export on the NAS) | `string` | `"backups"` | no |
| <a name="input_cluster"></a> [cluster](#input\_cluster) | Cluster-wide settings: addressing, versions, install disk, image extensions | <pre>object({<br/>    name               = string<br/>    domain             = string<br/>    vip                = string<br/>    gateway            = string<br/>    prefix             = number<br/>    nameservers        = list(string)<br/>    bootstrap          = string<br/>    install_disk       = string<br/>    talos_version      = string<br/>    kubernetes_version = string<br/>    extensions         = list(string)<br/>  })</pre> | n/a | yes |
| <a name="input_cpu_type"></a> [cpu\_type](#input\_cpu\_type) | QEMU CPU model | `string` | `"host"` | no |
| <a name="input_disk_format"></a> [disk\_format](#input\_disk\_format) | On-datastore disk format: raw for LVM/ZFS/Ceph, qcow2 for directory storage | `string` | `"raw"` | no |
| <a name="input_image_datastore"></a> [image\_datastore](#input\_image\_datastore) | Datastore the Talos ISO is downloaded to (needs 'iso' content type) | `string` | `"local"` | no |
| <a name="input_nas_server"></a> [nas\_server](#input\_nas\_server) | NFS server backing the backups and iso storages | `string` | n/a | yes |
| <a name="input_network_bridge"></a> [network\_bridge](#input\_network\_bridge) | Proxmox bridge to attach VMs to | `string` | `"vmbr0"` | no |
| <a name="input_nfs"></a> [nfs](#input\_nfs) | The NFS server LXC: identity, sizing and what it exports. Sizes are GB. | <pre>object({<br/>    name        = string<br/>    vmid        = number<br/>    ip          = string<br/>    cores       = number<br/>    memory      = number<br/>    root_disk   = number<br/>    data_disk   = number<br/>    export_path = string<br/>  })</pre> | n/a | yes |
| <a name="input_nodes"></a> [nodes](#input\_nodes) | Node name -> role, address, VM ID and size. data\_disk is the db nodes' second disk. | <pre>map(object({<br/>    role      = string<br/>    ip        = string<br/>    vmid      = number<br/>    cores     = number<br/>    memory    = number<br/>    disk      = number<br/>    data_disk = optional(number)<br/>  }))</pre> | n/a | yes |
| <a name="input_pve_bridge_address"></a> [pve\_bridge\_address](#input\_pve\_bridge\_address) | The PVE host's own address on the management bridge, CIDR form | `string` | n/a | yes |
| <a name="input_pve_bridge_gateway"></a> [pve\_bridge\_gateway](#input\_pve\_bridge\_gateway) | Default gateway on the management bridge | `string` | n/a | yes |
| <a name="input_pve_bridge_port"></a> [pve\_bridge\_port](#input\_pve\_bridge\_port) | Physical NIC enslaved to the management bridge | `string` | n/a | yes |
| <a name="input_pve_endpoint"></a> [pve\_endpoint](#input\_pve\_endpoint) | Proxmox VE API endpoint, e.g. https://pve2.lan:8006/ | `string` | n/a | yes |
| <a name="input_pve_exporter_acl_path"></a> [pve\_exporter\_acl\_path](#input\_pve\_exporter\_acl\_path) | ACL path the role is granted on | `string` | `"/"` | no |
| <a name="input_pve_exporter_role_id"></a> [pve\_exporter\_role\_id](#input\_pve\_exporter\_role\_id) | Role granted to the exporter user. PVEAuditor is read-only and enough. | `string` | `"PVEAuditor"` | no |
| <a name="input_pve_exporter_token_name"></a> [pve\_exporter\_token\_name](#input\_pve\_exporter\_token\_name) | Name of that user's API token | `string` | `"exporter"` | no |
| <a name="input_pve_exporter_user_id"></a> [pve\_exporter\_user\_id](#input\_pve\_exporter\_user\_id) | PVE user the Prometheus exporter authenticates as, realm included | `string` | `"prometheus@pve"` | no |
| <a name="input_pve_fqdn"></a> [pve\_fqdn](#input\_pve\_fqdn) | Public hostname of the PVE host, the subject of its ACME certificate | `string` | n/a | yes |
| <a name="input_pve_insecure"></a> [pve\_insecure](#input\_pve\_insecure) | Skip TLS verification (self-signed PVE cert) | `bool` | `true` | no |
| <a name="input_pve_node"></a> [pve\_node](#input\_pve\_node) | Proxmox node the VMs are created on | `string` | n/a | yes |
| <a name="input_pve_ssh_private_key_path"></a> [pve\_ssh\_private\_key\_path](#input\_pve\_ssh\_private\_key\_path) | Private key the provider uses for SSH to the node. Empty string falls back to ssh-agent. | `string` | `"~/.ssh/id_ed25519"` | no |
| <a name="input_pve_ssh_username"></a> [pve\_ssh\_username](#input\_pve\_ssh\_username) | SSH user on the Proxmox node, used by the provider for disk operations | `string` | `"root"` | no |
| <a name="input_vlan_id"></a> [vlan\_id](#input\_vlan\_id) | VLAN tag for the VM NIC, null for untagged | `number` | `null` | no |
| <a name="input_vm_datastore"></a> [vm\_datastore](#input\_vm\_datastore) | Datastore for VM disks | `string` | `"local-lvm"` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_backup_job"></a> [backup\_job](#output\_backup\_job) | The nightly vzdump job |
| <a name="output_control_plane_endpoint"></a> [control\_plane\_endpoint](#output\_control\_plane\_endpoint) | The Talos VIP fronting the API servers |
| <a name="output_kubeconfig"></a> [kubeconfig](#output\_kubeconfig) | Cluster admin kubeconfig, pointed at the VIP |
| <a name="output_network"></a> [network](#output\_network) | Cluster addressing other Terraform roots consume |
| <a name="output_nfs_server"></a> [nfs\_server](#output\_nfs\_server) | Where the NFS export lives, for the StorageClass in apps/base/csi-driver-nfs/ |
| <a name="output_nodes"></a> [nodes](#output\_nodes) | Node name -> address, role and vmid |
| <a name="output_pve_exporter"></a> [pve\_exporter](#output\_pve\_exporter) | Credentials for apps/base/pve-exporter/credentials.sops.yaml |
| <a name="output_talos_endpoints"></a> [talos\_endpoints](#output\_talos\_endpoints) | Talos API endpoints — node addresses, deliberately not the VIP |
| <a name="output_talos_image"></a> [talos\_image](#output\_talos\_image) | Factory schematic and the installer image the nodes run |
| <a name="output_talosconfig"></a> [talosconfig](#output\_talosconfig) | Client configuration for talosctl |
<!-- END_TF_DOCS -->
