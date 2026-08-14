<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.12 |
| <a name="requirement_tailscale"></a> [tailscale](#requirement\_tailscale) | ~> 0.29 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_tailscale"></a> [tailscale](#provider\_tailscale) | 0.29.2 |
| <a name="provider_terraform"></a> [terraform](#provider\_terraform) | n/a |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [tailscale_acl.policy](https://registry.terraform.io/providers/tailscale/tailscale/latest/docs/resources/acl) | resource |
| [terraform_remote_state.proxmox](https://registry.terraform.io/providers/hashicorp/terraform/latest/docs/data-sources/remote_state) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_backend_fingerprint"></a> [backend\_fingerprint](#input\_backend\_fingerprint) | Fingerprint of that user's API signing key | `string` | n/a | yes |
| <a name="input_backend_namespace"></a> [backend\_namespace](#input\_backend\_namespace) | Object Storage namespace holding the state bucket | `string` | n/a | yes |
| <a name="input_backend_private_key_path"></a> [backend\_private\_key\_path](#input\_backend\_private\_key\_path) | Where scripts/tf.sh decrypted that signing key | `string` | n/a | yes |
| <a name="input_backend_region"></a> [backend\_region](#input\_backend\_region) | Region the state bucket lives in | `string` | n/a | yes |
| <a name="input_backend_tenancy_ocid"></a> [backend\_tenancy\_ocid](#input\_backend\_tenancy\_ocid) | Tenancy the state credentials belong to | `string` | n/a | yes |
| <a name="input_backend_user_ocid"></a> [backend\_user\_ocid](#input\_backend\_user\_ocid) | User the state credentials belong to | `string` | n/a | yes |

## Outputs

No outputs.
<!-- END_TF_DOCS -->
