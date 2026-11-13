# github-oidc-role

An IAM role a GitHub Actions job assumes over OIDC, trusted only for one
repository and GitHub environment, with read/write/lock on one Terraform state
object in S3 and read on any others it lists.

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
| [aws_iam_role.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy.state](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_policy_document.state](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.trust](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_environment"></a> [environment](#input\_environment) | GitHub environment the job declares — the only subject the role trusts | `string` | n/a | yes |
| <a name="input_name"></a> [name](#input\_name) | Role name | `string` | n/a | yes |
| <a name="input_oidc_provider_arn"></a> [oidc\_provider\_arn](#input\_oidc\_provider\_arn) | ARN of the token.actions.githubusercontent.com provider in this account | `string` | n/a | yes |
| <a name="input_read_state_keys"></a> [read\_state\_keys](#input\_read\_state\_keys) | Other roots' state objects, read through terraform\_remote\_state | `list(string)` | `[]` | no |
| <a name="input_repository"></a> [repository](#input\_repository) | owner/repo the workflow runs in | `string` | n/a | yes |
| <a name="input_state_bucket"></a> [state\_bucket](#input\_state\_bucket) | S3 bucket holding the Terraform state | `string` | n/a | yes |
| <a name="input_state_key"></a> [state\_key](#input\_state\_key) | State object the role reads, writes and locks | `string` | n/a | yes |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_role_arn"></a> [role\_arn](#output\_role\_arn) | What aws-actions/configure-aws-credentials assumes |
<!-- END_TF_DOCS -->
