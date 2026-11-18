# acme-route53-user

An IAM user that can write only the `_acme-challenge` TXT records for its own
names, for hosts that solve DNS-01 against Route 53 and can't use OIDC (PVE,
the edge box). Its access key is created by hand:

    aws iam create-access-key --user-name <user_name>

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
| [aws_iam_group.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_group) | resource |
| [aws_iam_group_policy.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_group_policy) | resource |
| [aws_iam_user.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_user) | resource |
| [aws_iam_user_group_membership.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_user_group_membership) | resource |
| [aws_iam_policy_document.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_domains"></a> [domains](#input\_domains) | Names the user may answer DNS-01 for; a leading *. is the wildcard's base | `list(string)` | n/a | yes |
| <a name="input_name"></a> [name](#input\_name) | IAM user name | `string` | n/a | yes |
| <a name="input_zone_id"></a> [zone\_id](#input\_zone\_id) | Hosted zone the challenges are written to | `string` | n/a | yes |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_user_name"></a> [user\_name](#output\_user\_name) | Create its key with: aws iam create-access-key --user-name <this> |
<!-- END_TF_DOCS -->
