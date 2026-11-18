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
| [aws_route53_record.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_record) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_records"></a> [records](#input\_records) | Key => record set. Names are FQDNs. Give records (with ttl) or alias, not both. | <pre>map(object({<br/>    name    = string<br/>    type    = string<br/>    ttl     = optional(number, 300)<br/>    records = optional(list(string))<br/>    alias = optional(object({<br/>      name    = string<br/>      zone_id = string<br/>    }))<br/>  }))</pre> | n/a | yes |
| <a name="input_zone_id"></a> [zone\_id](#input\_zone\_id) | Hosted zone the records go in | `string` | n/a | yes |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_fqdns"></a> [fqdns](#output\_fqdns) | Key => FQDN |
<!-- END_TF_DOCS -->
