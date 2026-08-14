# 00-global

The Object Storage bucket every Terraform root in this repo keeps its state in,
one object per root, locked by the `oci` backend's own `If-None-Match: *` PUT.

An ordinary root now: `mise run global:plan` / `global:apply`, with
`mise run global:backend` printing what every backend block resolves against.

It creates the bucket its own backend block points at, so building it from
nothing is circular — `backend.tf` aside, apply on local state, then
`terraform init -migrate-state`. That is a one-off, not a task;
`docs/terraform-state-migration.md` has it, along with the record of moving the
other five roots off Cloudflare R2.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.12 |
| <a name="requirement_oci"></a> [oci](#requirement\_oci) | ~> 6 |
| <a name="requirement_tls"></a> [tls](#requirement\_tls) | ~> 4 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_oci"></a> [oci](#provider\_oci) | 6.37.0 |
| <a name="provider_tls"></a> [tls](#provider\_tls) | 4.3.0 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [oci_identity_api_key.ci](https://registry.terraform.io/providers/oracle/oci/latest/docs/resources/identity_api_key) | resource |
| [oci_identity_group.ci](https://registry.terraform.io/providers/oracle/oci/latest/docs/resources/identity_group) | resource |
| [oci_identity_policy.ci](https://registry.terraform.io/providers/oracle/oci/latest/docs/resources/identity_policy) | resource |
| [oci_identity_user.ci](https://registry.terraform.io/providers/oracle/oci/latest/docs/resources/identity_user) | resource |
| [oci_identity_user_group_membership.ci](https://registry.terraform.io/providers/oracle/oci/latest/docs/resources/identity_user_group_membership) | resource |
| [oci_objectstorage_bucket.tfstate](https://registry.terraform.io/providers/oracle/oci/latest/docs/resources/objectstorage_bucket) | resource |
| [tls_private_key.ci](https://registry.terraform.io/providers/hashicorp/tls/latest/docs/resources/private_key) | resource |
| [oci_identity_compartment.this](https://registry.terraform.io/providers/oracle/oci/latest/docs/data-sources/identity_compartment) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_bucket_name"></a> [bucket\_name](#input\_bucket\_name) | Object Storage bucket holding the Terraform state of every root | `string` | `"infrastructure-terraform-state"` | no |
| <a name="input_ci_user_email"></a> [ci\_user\_email](#input\_ci\_user\_email) | Primary email for the terraform-ci IAM user — required in an Identity Domains tenancy | `string` | n/a | yes |
| <a name="input_oci_compartment_ocid"></a> [oci\_compartment\_ocid](#input\_oci\_compartment\_ocid) | Compartment the state bucket is created in | `string` | n/a | yes |
| <a name="input_oci_fingerprint"></a> [oci\_fingerprint](#input\_oci\_fingerprint) | Fingerprint of that user's API signing key | `string` | n/a | yes |
| <a name="input_oci_namespace"></a> [oci\_namespace](#input\_oci\_namespace) | Object Storage namespace — Console: Tenancy details, or `oci os ns get` | `string` | n/a | yes |
| <a name="input_oci_private_key_path"></a> [oci\_private\_key\_path](#input\_oci\_private\_key\_path) | Path to the API signing key; defaults to secrets/oci\_api\_key.pem | `string` | n/a | yes |
| <a name="input_oci_region"></a> [oci\_region](#input\_oci\_region) | Region the state bucket lives in — also the region every backend block resolves against | `string` | n/a | yes |
| <a name="input_oci_tenancy_ocid"></a> [oci\_tenancy\_ocid](#input\_oci\_tenancy\_ocid) | Tenancy OCID | `string` | n/a | yes |
| <a name="input_oci_user_ocid"></a> [oci\_user\_ocid](#input\_oci\_user\_ocid) | OCID of the user whose API key signs these requests | `string` | n/a | yes |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_bucket"></a> [bucket](#output\_bucket) | State bucket name, repeated in the backend block of every root |
| <a name="output_ci_fingerprint"></a> [ci\_fingerprint](#output\_ci\_fingerprint) | Fingerprint of the terraform-ci signing key — the OCI\_FINGERPRINT secret |
| <a name="output_ci_private_key"></a> [ci\_private\_key](#output\_ci\_private\_key) | PEM body of the terraform-ci signing key — the OCI\_API\_KEY secret |
| <a name="output_ci_user_ocid"></a> [ci\_user\_ocid](#output\_ci\_user\_ocid) | OCID of the terraform-ci user — the OCI\_USER\_OCID secret |
| <a name="output_namespace"></a> [namespace](#output\_namespace) | Object Storage namespace the bucket lives in |
| <a name="output_region"></a> [region](#output\_region) | Region the state bucket lives in |
| <a name="output_tenancy_ocid"></a> [tenancy\_ocid](#output\_tenancy\_ocid) | The OCI\_TENANCY\_OCID secret |
<!-- END_TF_DOCS -->
