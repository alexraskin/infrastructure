The WAF rulesets here cover every zone in `var.zones`, including the hostnames
the OCI edge serves — a zone has one entry point ruleset per phase, so they
cannot be split across roots. `docs/cloudflare-waf.md` has the Free-plan limits
they are shaped around, and why a grey-cloud record is outside them.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.12 |
| <a name="requirement_cloudflare"></a> [cloudflare](#requirement\_cloudflare) | ~> 5.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_cloudflare"></a> [cloudflare](#provider\_cloudflare) | 5.23.0 |
| <a name="provider_terraform"></a> [terraform](#provider\_terraform) | n/a |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [cloudflare_dns_record.cluster](https://registry.terraform.io/providers/cloudflare/cloudflare/latest/docs/resources/dns_record) | resource |
| [cloudflare_dns_record.tunnel](https://registry.terraform.io/providers/cloudflare/cloudflare/latest/docs/resources/dns_record) | resource |
| [cloudflare_ruleset.waf_custom](https://registry.terraform.io/providers/cloudflare/cloudflare/latest/docs/resources/ruleset) | resource |
| [cloudflare_ruleset.waf_ratelimit](https://registry.terraform.io/providers/cloudflare/cloudflare/latest/docs/resources/ruleset) | resource |
| [cloudflare_zero_trust_tunnel_cloudflared.this](https://registry.terraform.io/providers/cloudflare/cloudflare/latest/docs/resources/zero_trust_tunnel_cloudflared) | resource |
| [cloudflare_zero_trust_tunnel_cloudflared_config.this](https://registry.terraform.io/providers/cloudflare/cloudflare/latest/docs/resources/zero_trust_tunnel_cloudflared_config) | resource |
| [cloudflare_zero_trust_tunnel_cloudflared_token.this](https://registry.terraform.io/providers/cloudflare/cloudflare/latest/docs/data-sources/zero_trust_tunnel_cloudflared_token) | data source |
| [terraform_remote_state.proxmox](https://registry.terraform.io/providers/hashicorp/terraform/latest/docs/data-sources/remote_state) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_account_id"></a> [account\_id](#input\_account\_id) | Cloudflare account ID that owns the tunnel | `string` | n/a | yes |
| <a name="input_backend_fingerprint"></a> [backend\_fingerprint](#input\_backend\_fingerprint) | Fingerprint of that user's API signing key | `string` | n/a | yes |
| <a name="input_backend_namespace"></a> [backend\_namespace](#input\_backend\_namespace) | Object Storage namespace holding the state bucket | `string` | n/a | yes |
| <a name="input_backend_private_key_path"></a> [backend\_private\_key\_path](#input\_backend\_private\_key\_path) | Where scripts/tf.sh decrypted that signing key | `string` | n/a | yes |
| <a name="input_backend_region"></a> [backend\_region](#input\_backend\_region) | Region the state bucket lives in | `string` | n/a | yes |
| <a name="input_backend_tenancy_ocid"></a> [backend\_tenancy\_ocid](#input\_backend\_tenancy\_ocid) | Tenancy the state credentials belong to | `string` | n/a | yes |
| <a name="input_backend_user_ocid"></a> [backend\_user\_ocid](#input\_backend\_user\_ocid) | User the state credentials belong to | `string` | n/a | yes |
| <a name="input_catch_all_service"></a> [catch\_all\_service](#input\_catch\_all\_service) | What the tunnel answers with for a hostname no rule matched. | `string` | `"http_status:404"` | no |
| <a name="input_cluster_dns_records"></a> [cluster\_dns\_records](#input\_cluster\_dns\_records) | n/a | <pre>map(object({<br/>    zone    = string<br/>    name    = string<br/>    source  = string<br/>    ttl     = optional(number, 1)<br/>    comment = optional(string, "terraform: cluster address")<br/>  }))</pre> | `{}` | no |
| <a name="input_ingress"></a> [ingress](#input\_ingress) | n/a | <pre>list(object({<br/>    hostname = string<br/>    service  = string<br/>    path     = optional(string)<br/>  }))</pre> | n/a | yes |
| <a name="input_tunnel_id"></a> [tunnel\_id](#input\_tunnel\_id) | UUID of the existing tunnel, used by the import blocks in imports.tf | `string` | n/a | yes |
| <a name="input_tunnel_name"></a> [tunnel\_name](#input\_tunnel\_name) | Name of the existing tunnel, as it appears in Zero Trust -> Networks -> Tunnels | `string` | `"k3s"` | no |
| <a name="input_waf_blocked_paths"></a> [waf\_blocked\_paths](#input\_waf\_blocked\_paths) | Path substrings that get a 403. Matched against lower(path); the Free plan has no regex. | `list(string)` | <pre>[<br/>  "/wp-admin",<br/>  "/wp-login",<br/>  "/wp-content",<br/>  "/wp-includes",<br/>  "/xmlrpc.php",<br/>  "/.env",<br/>  "/.git/",<br/>  "/.aws/",<br/>  "/.ssh/",<br/>  "/phpmyadmin",<br/>  "/vendor/phpunit",<br/>  "/cgi-bin/",<br/>  "/administrator/"<br/>]</pre> | no |
| <a name="input_waf_blocked_user_agents"></a> [waf\_blocked\_user\_agents](#input\_waf\_blocked\_user\_agents) | User-Agent substrings that get a 403. Matched against lower(user\_agent). | `list(string)` | <pre>[<br/>  "ahrefsbot",<br/>  "amazonbot",<br/>  "bytespider",<br/>  "ccbot",<br/>  "dataforseobot",<br/>  "dotbot",<br/>  "gptbot",<br/>  "imagesiftbot",<br/>  "mj12bot",<br/>  "petalbot",<br/>  "semrushbot"<br/>]</pre> | no |
| <a name="input_waf_enabled"></a> [waf\_enabled](#input\_waf\_enabled) | Whether to manage the WAF rulesets of every zone in var.zones. | `bool` | `true` | no |
| <a name="input_waf_extra_hosts"></a> [waf\_extra\_hosts](#input\_waf\_extra\_hosts) | Hostnames the read-only rule covers beyond the tunnel's own. Only a proxied hostname ever reaches the WAF. | `list(string)` | `[]` | no |
| <a name="input_waf_rate_limit"></a> [waf\_rate\_limit](#input\_waf\_rate\_limit) | Per-IP flood control. The Free plan fixes the period and the mitigation timeout at 10s, allows one rule, and takes no action other than block. | <pre>object({<br/>    enabled             = optional(bool, true)<br/>    requests_per_period = optional(number, 100)<br/>    action              = optional(string, "block")<br/>  })</pre> | `{}` | no |
| <a name="input_zones"></a> [zones](#input\_zones) | Zone name -> zone ID. Every ingress hostname must fall under one of these. | `map(string)` | n/a | yes |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_hostnames"></a> [hostnames](#output\_hostnames) | Public hostname -> origin the tunnel forwards it to |
| <a name="output_tunnel_cname"></a> [tunnel\_cname](#output\_tunnel\_cname) | What every public hostname CNAMEs to |
| <a name="output_tunnel_id"></a> [tunnel\_id](#output\_tunnel\_id) | UUID of the tunnel |
| <a name="output_tunnel_token"></a> [tunnel\_token](#output\_tunnel\_token) | Connector token — the TUNNEL\_TOKEN cloudflared runs with |
<!-- END_TF_DOCS -->
