# 00-global

The AWS roles GitHub Actions assumes over OIDC to reach Terraform state, one
per GitHub environment, each limited to its own state object (plus the Proxmox
root's, read through `terraform_remote_state`).

State for every root lives in the `alexraskin-tfstate` S3 bucket (us-east-1)
under `infrastructure/<root>/terraform.tfstate`, locked with S3's native
lockfile. Neither the bucket nor the GitHub OIDC provider is managed here: the
bucket was made by hand, and the provider belongs to the alexraskin.com
project, since an account holds one per URL.

`mise run global:roles` prints the `AWS_ROLE_ARN` each environment wants.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.12 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | ~> 6 |
| <a name="requirement_sops"></a> [sops](#requirement\_sops) | ~> 1.4 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | 6.73.0 |
| <a name="provider_sops"></a> [sops](#provider\_sops) | ~> 1.4 |

## Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_ci_role"></a> [ci\_role](#module\_ci\_role) | ../modules/github-oidc-role | n/a |

## Resources

| Name | Type |
|------|------|
| [aws_budgets_budget.monthly](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/budgets_budget) | resource |
| [aws_caller_identity.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [aws_iam_openid_connect_provider.github](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_openid_connect_provider) | data source |
| [sops_file.admin](https://registry.terraform.io/providers/carlpett/sops/latest/docs/data-sources/file) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_region"></a> [region](#input\_region) | Region the state bucket lives in | `string` | `"us-east-1"` | no |
| <a name="input_repository"></a> [repository](#input\_repository) | GitHub repository whose workflows assume the CI roles | `string` | `"alexraskin/infrastructure"` | no |
| <a name="input_state_bucket"></a> [state\_bucket](#input\_state\_bucket) | S3 bucket holding every root's state, under infrastructure/ | `string` | `"alexraskin-tfstate"` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_ci_role_arns"></a> [ci\_role\_arns](#output\_ci\_role\_arns) | AWS\_ROLE\_ARN for each GitHub environment |
<!-- END_TF_DOCS -->
