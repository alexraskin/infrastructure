<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.12 |
| <a name="requirement_cloudflare"></a> [cloudflare](#requirement\_cloudflare) | ~> 5 |
| <a name="requirement_oci"></a> [oci](#requirement\_oci) | ~> 6 |
| <a name="requirement_sops"></a> [sops](#requirement\_sops) | ~> 1.4 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_cloudflare"></a> [cloudflare](#provider\_cloudflare) | 5.23.0 |
| <a name="provider_oci"></a> [oci](#provider\_oci) | 6.37.0 |
| <a name="provider_sops"></a> [sops](#provider\_sops) | 1.4.1 |
| <a name="provider_terraform"></a> [terraform](#provider\_terraform) | n/a |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [cloudflare_dns_record.site](https://registry.terraform.io/providers/cloudflare/cloudflare/latest/docs/resources/dns_record) | resource |
| [cloudflare_dns_record.wildcard](https://registry.terraform.io/providers/cloudflare/cloudflare/latest/docs/resources/dns_record) | resource |
| [oci_core_instance.edge](https://registry.terraform.io/providers/oracle/oci/latest/docs/resources/core_instance) | resource |
| [oci_core_internet_gateway.edge](https://registry.terraform.io/providers/oracle/oci/latest/docs/resources/core_internet_gateway) | resource |
| [oci_core_route_table.public](https://registry.terraform.io/providers/oracle/oci/latest/docs/resources/core_route_table) | resource |
| [oci_core_security_list.edge](https://registry.terraform.io/providers/oracle/oci/latest/docs/resources/core_security_list) | resource |
| [oci_core_subnet.public](https://registry.terraform.io/providers/oracle/oci/latest/docs/resources/core_subnet) | resource |
| [oci_core_vcn.edge](https://registry.terraform.io/providers/oracle/oci/latest/docs/resources/core_vcn) | resource |
| [terraform_data.vcn_cidr_marker](https://registry.terraform.io/providers/hashicorp/terraform/latest/docs/resources/data) | resource |
| [cloudflare_zone.this](https://registry.terraform.io/providers/cloudflare/cloudflare/latest/docs/data-sources/zone) | data source |
| [oci_core_images.ubuntu](https://registry.terraform.io/providers/oracle/oci/latest/docs/data-sources/core_images) | data source |
| [oci_identity_availability_domains.ads](https://registry.terraform.io/providers/oracle/oci/latest/docs/data-sources/identity_availability_domains) | data source |
| [sops_file.admin](https://registry.terraform.io/providers/carlpett/sops/latest/docs/data-sources/file) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_instance_availability_domain"></a> [instance\_availability\_domain](#input\_instance\_availability\_domain) | n/a | `string` | `""` | no |
| <a name="input_instance_availability_domain_index"></a> [instance\_availability\_domain\_index](#input\_instance\_availability\_domain\_index) | Zero-based AD index used when no explicit AD is given | `number` | `0` | no |
| <a name="input_public_subnet_cidr"></a> [public\_subnet\_cidr](#input\_public\_subnet\_cidr) | CIDR for the public subnet | `string` | `"10.80.1.0/24"` | no |
| <a name="input_vcn_cidr"></a> [vcn\_cidr](#input\_vcn\_cidr) | CIDR for the VCN. Must not overlap 10.0.200.0/24 (the home LAN reached over Tailscale) or the flannel range. | `string` | `"10.80.0.0/16"` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_availability_domain"></a> [availability\_domain](#output\_availability\_domain) | Which AD the instance actually landed in, after any capacity retries |
| <a name="output_instance_id"></a> [instance\_id](#output\_instance\_id) | n/a |
| <a name="output_private_ip"></a> [private\_ip](#output\_private\_ip) | Address inside the VCN |
| <a name="output_public_ip"></a> [public\_ip](#output\_public\_ip) | Ephemeral public IP. dns.tf already points the site records at it. |
| <a name="output_sites"></a> [sites](#output\_sites) | Public hostname -> home backend, as HAProxy will route them |
<!-- END_TF_DOCS -->
