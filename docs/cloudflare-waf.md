# Cloudflare WAF

`terraform/cloudflare/waf.tf` owns the WAF for every zone in `var.zones`. It is
in that root, and not in `01-cloud-edge/terraform/`, because a zone has exactly
**one** entry point ruleset per phase: two roots writing rules for
`alexraskin.com` would overwrite each other's on every apply. Whatever the edge
needs goes in `var.waf_extra_hosts`, applied from the same place.

## The Free plan is the constraint

| | Free plan |
| --- | --- |
| Custom rules | 5 per zone |
| Rate limiting rules | 1 per zone, period and mitigation timeout fixed at 10s |
| Rate limiting expression | `Path` and `Verified Bot` only — **no `http.host`** |
| Rate limiting counter | per IP |
| Custom rule actions | everything except `log` |
| Rate limiting actions | `block` only — anything else is `not entitled to use the <action> action in ratelimiting` |
| Regex in expressions | no — Business and up |
| Managed rulesets | the Cloudflare Free Managed Ruleset only, on by default, not configurable |

A `check` block in `waf.tf` fails the plan if the rule list grows past five, so
adding a sixth is caught at plan and not by the API. `lower(...) contains ...`
appears everywhere a regex would be the obvious tool; that is the plan talking,
not a preference.

The rate limiting rule cannot be scoped to a hostname, so it counts every
proxied request to the zone: 100 requests per 10s per IP, then a block for 10s.

## Only proxied traffic reaches the WAF

Cloudflare evaluates rules where it terminates the connection. A grey-cloud
record resolves straight to the origin, so no rule of any plan applies to it.
Today that means:

| record | proxied | covered |
| --- | --- | --- |
| `alexraskin.com`, `www`, `lastfm` | yes — tunnel CNAMEs | yes |
| `*.relay.alexraskin.com`, `*.cloud.alexraskin.com` (the OCI edge) | no | **no** |
| `pve.lan`, `k8s.lan` (`cluster_dns_records`) | no, and RFC1918 | no, and cannot be |

`local.tunnel_hostnames` is what the read-only rule matches on, so a hostname
added to `var.ingress` is covered without a second edit.

### The edge stays grey on purpose

`01-cloud-edge/terraform/dns.tf` sets `proxied = false`, and orange-clouding it
would mean proxying Plex — video through the CDN is what section 2.8 of
Cloudflare's terms exists to stop, and the proxy's request limits break large
streams anyway. The edge is defended by the OCI security list (443 and the
Tailscale UDP port, nothing else) and by HAProxy only serving the SNI names it
holds a cert for. If a non-video site ever lands on the edge, orange-cloud that
hostname alone and add it to `var.waf_extra_hosts`.

## The ruleset already existed

A zone gets one entry point ruleset per phase and the API refuses a second with

```text
'zone' is not a valid value for kind because exceeded maximum number of
zone rulesets for phase http_request_firewall_custom
```

so the custom-rules ruleset is adopted by an `import` block in the gitignored
`imports.tf`, keyed `zones/<zone_id>/<ruleset_id>`. Its ID comes from
`GET /zones/<zone>/rulesets/phases/http_request_firewall_custom/entrypoint`.
The rate limiting phase had no ruleset, so that one is created.

The token in `sops/terraform.sops.yaml` needs **Zone → Zone WAF → Edit**;
without it every ruleset call answers `Authentication error (10000)` while the
plan stays clean, because there is nothing to read until the first apply.

## Rules that exist today

| ref | action | matches |
| --- | --- | --- |
| `verified_bots` | managed challenge | `cf.client.bot` — written in the dashboard as "Defense", adopted here |
| `block_junk` | block | `var.waf_blocked_paths` (wp-\*, `.env`, `.git/`, phpMyAdmin) or `var.waf_blocked_user_agents` (AI and SEO crawlers) |
| `read_only_hosts` | block | POST/PUT/PATCH/DELETE/TRACE/CONNECT to a tunnel hostname |
| `no_user_agent` | managed challenge | empty User-Agent that is not a verified crawler |

`verified_bots` matches Googlebot and Bingbot, so the zone is not indexable
while it stands. It blocked outright until this file adopted it.

`read_only_hosts` holds because both apps behind the tunnel serve static
content. The first app that takes a write needs its hostname out of the match,
not the rule deleted.

Two conditions share `block_junk` for the same reason one slot is left free:
the plan counts rules, not conditions. Country blocks (`ip.src.country`) and ASN
blocks (`ip.src.asnum`) are both available on Free if that slot is ever needed.

## Changing them

```bash
mise run cloudflare:plan
mise run cloudflare:apply
```

The plan prints every expression in full — read them there rather than in the
dashboard. **Rules added by hand in the dashboard live in the same entry point
ruleset and the next apply deletes them.**
