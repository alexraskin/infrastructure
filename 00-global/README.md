# 00-global

The AWS roles GitHub Actions assumes over OIDC to reach Terraform state, one
per GitHub environment, each limited to its own state object (plus the Proxmox
root's, read through `terraform_remote_state`).

State for every root lives in the `alexraskin-tfstate` S3 bucket (us-east-1)
under `infrastructure/<root>/terraform.tfstate`, locked with S3's native
lockfile. The bucket was made by hand and isn't managed here. The account's
GitHub OIDC provider (one per URL) is managed here; other repos' deploy roles
read it as a data source.

`mise run global:roles` prints the `AWS_ROLE_ARN` each environment wants.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.12 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | ~> 6 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | 6.73.0 |
| <a name="provider_aws.sso"></a> [aws.sso](#provider\_aws.sso) | 6.73.0 |

## Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_ci_role"></a> [ci\_role](#module\_ci\_role) | ../modules/github-oidc-role | n/a |
| <a name="module_dns"></a> [dns](#module\_dns) | ../modules/route53-records | n/a |
| <a name="module_secrets"></a> [secrets](#module\_secrets) | ../modules/ssm-params | n/a |

## Resources

| Name | Type |
|------|------|
| [aws_budgets_budget.monthly](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/budgets_budget) | resource |
| [aws_iam_openid_connect_provider.github](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_openid_connect_provider) | resource |
| [aws_identitystore_group.admin](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/identitystore_group) | resource |
| [aws_identitystore_group_membership.alex_admin](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/identitystore_group_membership) | resource |
| [aws_identitystore_user.alex](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/identitystore_user) | resource |
| [aws_route53_zone.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_zone) | resource |
| [aws_route53domains_registered_domain.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53domains_registered_domain) | resource |
| [aws_ssoadmin_account_assignment.alex_admin](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ssoadmin_account_assignment) | resource |
| [aws_ssoadmin_managed_policy_attachment.admin](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ssoadmin_managed_policy_attachment) | resource |
| [aws_ssoadmin_permission_set.admin](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ssoadmin_permission_set) | resource |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [aws_ssoadmin_instances.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/ssoadmin_instances) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_dnssec_publish_ds"></a> [dnssec\_publish\_ds](#input\_dnssec\_publish\_ds) | Publish the DS record at the registry (modules/route53-records). Only after the zone has been signed for 48h. | `bool` | `false` | no |
| <a name="input_domain"></a> [domain](#input\_domain) | The hosted zone this root owns | `string` | `"alexraskin.com"` | no |
| <a name="input_region"></a> [region](#input\_region) | Region the state bucket lives in | `string` | `"us-east-1"` | no |
| <a name="input_repository"></a> [repository](#input\_repository) | GitHub repository whose workflows assume the CI roles | `string` | `"alexraskin/infrastructure"` | no |
| <a name="input_state_bucket"></a> [state\_bucket](#input\_state\_bucket) | S3 bucket holding every root's state, under infrastructure/ | `string` | `"alexraskin-tfstate"` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_ci_role_arns"></a> [ci\_role\_arns](#output\_ci\_role\_arns) | AWS\_ROLE\_ARN for each GitHub environment |
| <a name="output_dnssec_ds_record"></a> [dnssec\_ds\_record](#output\_dnssec\_ds\_record) | The DS record the registry should carry once dnssec\_publish\_ds is on |
| <a name="output_name_servers"></a> [name\_servers](#output\_name\_servers) | Set these at the registrar to cut the domain over to Route 53 |
<!-- END_TF_DOCS -->
