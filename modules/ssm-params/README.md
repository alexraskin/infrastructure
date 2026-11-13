# ssm-params

One group of SecureString parameters under `/infrastructure/<group>/`,
encrypted with the account's free `aws/ssm` key. Terraform owns the names;
values are put out of band and ignored, so nothing secret is in this repo:

    aws ssm put-parameter --overwrite --type SecureString \
      --name /infrastructure/<group>/<name> --value "$value"

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.12 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | ~> 6 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | ~> 6 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [aws_ssm_parameter.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ssm_parameter) | resource |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [aws_region.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/region) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_group"></a> [group](#input\_group) | Path segment under /infrastructure/ — one per consumer | `string` | n/a | yes |
| <a name="input_parameters"></a> [parameters](#input\_parameters) | Parameter name => description | `map(string)` | n/a | yes |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_read_arns"></a> [read\_arns](#output\_read\_arns) | What GetParameter and GetParametersByPath need to read the group |
| <a name="output_values"></a> [values](#output\_values) | Parameter name => decrypted value |
<!-- END_TF_DOCS -->
