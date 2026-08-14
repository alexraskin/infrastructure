data "terraform_remote_state" "proxmox" {
  backend = "oci"

  config = {
    auth             = "APIKey"
    bucket           = "infrastructure-terraform-state"
    key              = "talos-proxmox/terraform.tfstate"
    namespace        = var.backend_namespace
    region           = var.backend_region
    tenancy_ocid     = var.backend_tenancy_ocid
    user_ocid        = var.backend_user_ocid
    fingerprint      = var.backend_fingerprint
    private_key_path = var.backend_private_key_path
  }
}

locals {
  proxmox = try(data.terraform_remote_state.proxmox.outputs, {})

  cluster_addresses = merge(
    try({
      vip      = local.proxmox.network.vip
      pve_host = local.proxmox.network.pve_host
    }, {}),
    try({ for name, node in local.proxmox.nodes : name => node.ip }, {}),
  )
}

check "every_cluster_record_has_an_address" {
  assert {
    condition = alltrue([
      for key, record in var.cluster_dns_records :
      contains(keys(local.cluster_addresses), record.source)
    ])
    error_message = "No address in the Proxmox root for: ${join(", ", [
      for key, record in var.cluster_dns_records :
      "${key} -> ${record.source}"
      if !contains(keys(local.cluster_addresses), record.source)
    ])}. Known: ${join(", ", sort(keys(local.cluster_addresses)))}. If `vip` or `pve_host` is missing, run `mise run tf:apply` in terraform/proxmox/ once."
  }
}

resource "cloudflare_dns_record" "cluster" {
  for_each = var.cluster_dns_records

  zone_id = var.zones[each.value.zone]
  name    = each.value.name
  type    = "A"
  content = local.cluster_addresses[each.value.source]
  ttl     = each.value.ttl
  comment = each.value.comment

  proxied = false
}
