<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.6 |
| <a name="requirement_oci"></a> [oci](#requirement\_oci) | ~> 6 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_oci"></a> [oci](#provider\_oci) | 6.37.0 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [oci_identity_customer_secret_key.cnpg_backup](https://registry.terraform.io/providers/oracle/oci/latest/docs/resources/identity_customer_secret_key) | resource |
| [oci_identity_group.cnpg_backup](https://registry.terraform.io/providers/oracle/oci/latest/docs/resources/identity_group) | resource |
| [oci_identity_policy.cnpg_backup](https://registry.terraform.io/providers/oracle/oci/latest/docs/resources/identity_policy) | resource |
| [oci_identity_user.cnpg_backup](https://registry.terraform.io/providers/oracle/oci/latest/docs/resources/identity_user) | resource |
| [oci_identity_user_group_membership.cnpg_backup](https://registry.terraform.io/providers/oracle/oci/latest/docs/resources/identity_user_group_membership) | resource |
| [oci_objectstorage_bucket.cnpg](https://registry.terraform.io/providers/oracle/oci/latest/docs/resources/objectstorage_bucket) | resource |
| [oci_identity_compartment.this](https://registry.terraform.io/providers/oracle/oci/latest/docs/data-sources/identity_compartment) | data source |
| [oci_objectstorage_namespace.this](https://registry.terraform.io/providers/oracle/oci/latest/docs/data-sources/objectstorage_namespace) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_backup_user_email"></a> [backup\_user\_email](#input\_backup\_user\_email) | Primary email for the cnpg-backup IAM user — required in an Identity Domains tenancy | `string` | n/a | yes |
| <a name="input_bucket_name"></a> [bucket\_name](#input\_bucket\_name) | Object Storage bucket holding the CloudNativePG backups | `string` | `"cnpg-backups"` | no |
| <a name="input_oci_compartment_ocid"></a> [oci\_compartment\_ocid](#input\_oci\_compartment\_ocid) | Compartment the bucket is created in | `string` | n/a | yes |
| <a name="input_oci_fingerprint"></a> [oci\_fingerprint](#input\_oci\_fingerprint) | Fingerprint of that user's API signing key | `string` | n/a | yes |
| <a name="input_oci_private_key_path"></a> [oci\_private\_key\_path](#input\_oci\_private\_key\_path) | Path to the API signing key; defaults to secrets/oci\_api\_key.pem | `string` | n/a | yes |
| <a name="input_oci_region"></a> [oci\_region](#input\_oci\_region) | Region the bucket lives in — also the region in the S3 endpoint | `string` | n/a | yes |
| <a name="input_oci_tenancy_ocid"></a> [oci\_tenancy\_ocid](#input\_oci\_tenancy\_ocid) | Tenancy OCID | `string` | n/a | yes |
| <a name="input_oci_user_ocid"></a> [oci\_user\_ocid](#input\_oci\_user\_ocid) | OCID of the user whose API key signs these requests | `string` | n/a | yes |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_access_key_id"></a> [access\_key\_id](#output\_access\_key\_id) | The `access-key-id` key of the cnpg-backup-oci Secret |
| <a name="output_destination_path"></a> [destination\_path](#output\_destination\_path) | barmanObjectStore.destinationPath |
| <a name="output_endpoint_url"></a> [endpoint\_url](#output\_endpoint\_url) | S3-compatible endpoint — goes in cluster.yaml as barmanObjectStore.endpointURL |
| <a name="output_namespace"></a> [namespace](#output\_namespace) | Object Storage namespace, for `oci os object list --namespace` |
| <a name="output_region"></a> [region](#output\_region) | The `region` key of the cnpg-backup-oci Secret |
| <a name="output_secret_access_key"></a> [secret\_access\_key](#output\_secret\_access\_key) | The `secret-access-key` key of the cnpg-backup-oci Secret |
<!-- END_TF_DOCS -->
