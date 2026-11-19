# route53-records

Record sets in one Route 53 hosted zone. Every root that publishes a name
(`00-global` for the static ones, `proxmox` for the cluster, `edge` for the
edge box) calls this with the zone ID; `00-global` owns the zone itself.

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
| [aws_kms_alias.dnssec](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_alias) | resource |
| [aws_kms_key.dnssec](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_key) | resource |
| [aws_route53_hosted_zone_dnssec.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_hosted_zone_dnssec) | resource |
| [aws_route53_key_signing_key.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_key_signing_key) | resource |
| [aws_route53_record.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_record) | resource |
| [aws_route53domains_delegation_signer_record.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53domains_delegation_signer_record) | resource |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [aws_iam_policy_document.dnssec_kms](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_dnssec"></a> [dnssec](#input\_dnssec) | Sign the zone (the root that owns it sets this once). publish\_ds adds the registry DS record: only after the zone has been signed for its max TTL, 48h for the apex NS. | <pre>object({<br/>    domain     = string<br/>    publish_ds = optional(bool, false)<br/>  })</pre> | `null` | no |
| <a name="input_records"></a> [records](#input\_records) | Key => record set. Names are FQDNs. Give records (with ttl) or alias, not both. | <pre>map(object({<br/>    name    = string<br/>    type    = string<br/>    ttl     = optional(number, 300)<br/>    records = optional(list(string))<br/>    alias = optional(object({<br/>      name    = string<br/>      zone_id = string<br/>    }))<br/>  }))</pre> | n/a | yes |
| <a name="input_zone_id"></a> [zone\_id](#input\_zone\_id) | Hosted zone the records go in | `string` | n/a | yes |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_ds_record"></a> [ds\_record](#output\_ds\_record) | The zone's DS record, when dnssec is set |
<!-- END_TF_DOCS -->
