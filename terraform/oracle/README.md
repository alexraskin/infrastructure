<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.12 |
| <a name="requirement_oci"></a> [oci](#requirement\_oci) | ~> 6 |
| <a name="requirement_sops"></a> [sops](#requirement\_sops) | ~> 1.4 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_oci"></a> [oci](#provider\_oci) | 6.37.0 |
| <a name="provider_sops"></a> [sops](#provider\_sops) | 1.4.1 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [oci_identity_customer_secret_key.cnpg_backup](https://registry.terraform.io/providers/oracle/oci/latest/docs/resources/identity_customer_secret_key) | resource |
| [oci_identity_group.cnpg_backup](https://registry.terraform.io/providers/oracle/oci/latest/docs/resources/identity_group) | resource |
| [oci_identity_policy.cnpg_backup](https://registry.terraform.io/providers/oracle/oci/latest/docs/resources/identity_policy) | resource |
| [oci_identity_user.cnpg_backup](https://registry.terraform.io/providers/oracle/oci/latest/docs/resources/identity_user) | resource |
| [oci_identity_user_group_membership.cnpg_backup](https://registry.terraform.io/providers/oracle/oci/latest/docs/resources/identity_user_group_membership) | resource |
| [oci_objectstorage_bucket.cnpg](https://registry.terraform.io/providers/oracle/oci/latest/docs/resources/objectstorage_bucket) | resource |
| [oci_identity_compartment.this](https://registry.terraform.io/providers/oracle/oci/latest/docs/data-sources/identity_compartment) | data source |
| [oci_objectstorage_namespace.this](https://registry.terraform.io/providers/oracle/oci/latest/docs/data-sources/objectstorage_namespace) | data source |
| [sops_file.admin](https://registry.terraform.io/providers/carlpett/sops/latest/docs/data-sources/file) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_bucket_name"></a> [bucket\_name](#input\_bucket\_name) | Object Storage bucket holding the CloudNativePG backups | `string` | `"cnpg-backups"` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_access_key_id"></a> [access\_key\_id](#output\_access\_key\_id) | The `access-key-id` key of the cnpg-backup-oci Secret |
| <a name="output_destination_path"></a> [destination\_path](#output\_destination\_path) | barmanObjectStore.destinationPath |
| <a name="output_endpoint_url"></a> [endpoint\_url](#output\_endpoint\_url) | S3-compatible endpoint — goes in cluster.yaml as barmanObjectStore.endpointURL |
| <a name="output_namespace"></a> [namespace](#output\_namespace) | Object Storage namespace, for `oci os object list --namespace` |
| <a name="output_region"></a> [region](#output\_region) | The `region` key of the cnpg-backup-oci Secret |
| <a name="output_secret_access_key"></a> [secret\_access\_key](#output\_secret\_access\_key) | The `secret-access-key` key of the cnpg-backup-oci Secret |
<!-- END_TF_DOCS -->
