<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.12 |
| <a name="requirement_tailscale"></a> [tailscale](#requirement\_tailscale) | ~> 0.29 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_tailscale"></a> [tailscale](#provider\_tailscale) | 0.29.2 |
| <a name="provider_terraform"></a> [terraform](#provider\_terraform) | n/a |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [tailscale_acl.policy](https://registry.terraform.io/providers/tailscale/tailscale/latest/docs/resources/acl) | resource |
| [terraform_remote_state.proxmox](https://registry.terraform.io/providers/hashicorp/terraform/latest/docs/data-sources/remote_state) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_oci_fingerprint"></a> [oci\_fingerprint](#input\_oci\_fingerprint) | Fingerprint of that user's API signing key | `string` | n/a | yes |
| <a name="input_oci_namespace"></a> [oci\_namespace](#input\_oci\_namespace) | Object Storage namespace holding the state bucket | `string` | n/a | yes |
| <a name="input_oci_private_key_path"></a> [oci\_private\_key\_path](#input\_oci\_private\_key\_path) | Path to the API signing key; defaults to secrets/oci\_api\_key.pem | `string` | n/a | yes |
| <a name="input_oci_region"></a> [oci\_region](#input\_oci\_region) | Region the state bucket lives in | `string` | n/a | yes |
| <a name="input_oci_tenancy_ocid"></a> [oci\_tenancy\_ocid](#input\_oci\_tenancy\_ocid) | Tenancy OCID | `string` | n/a | yes |
| <a name="input_oci_user_ocid"></a> [oci\_user\_ocid](#input\_oci\_user\_ocid) | OCID of the user whose API key signs the state read | `string` | n/a | yes |

## Outputs

No outputs.
<!-- END_TF_DOCS -->
