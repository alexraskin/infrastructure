# terraform/cloudflare/ — the tunnel and DNS

A second root on purpose: different credentials, different blast radius. A DNS
change should not plan against the VMs. State holds the tunnel token in
cleartext, so the R2 bucket must stay private.

Auth is `CLOUDFLARE_API_TOKEN`, read from `secrets/cloudflare-api-token` by the
`cf:*` tasks — never a tfvars entry, never in state. The token needs exactly
three rows on a *custom* token: Account/Cloudflare Tunnel/Edit, Zone/DNS/Edit,
Zone/Zone/Read. DNS/Edit does **not** imply Zone/Read, and a token missing it
gets an empty zone list rather than a 403 — the same permission-filtering
behaviour as a privsep Proxmox token.

It **adopts** the pre-existing tunnel rather than creating one: `imports.tf`
holds `import` blocks for the tunnel, its config and every CNAME, so the
connector token already in `apps/base/cloudflared/token.sops.yaml` stays valid
and cloudflared never restarts. A correct plan is "N to import, 0 to add, 0 to
destroy". If it wants to *create* the tunnel, an import block is missing or
`tunnel_id` is wrong — applying then builds a second tunnel and moves the CNAMEs
to one with no connectors, which is the outage case.

`var.ingress` is the whole tunnel config. Order only matters for overlapping
rules (paths, wildcards), so a plan that merely reorders distinct hostnames is
inert; a rule that disappears from the list is deleted on apply. The catch-all
is appended automatically — Cloudflare requires the list to end with a rule that
has no hostname. `origin_request = {} -> null` on an adopted config is the
provider's round-trip noise, not a change. The config resource has no DELETE
endpoint, hence the standing "cannot be destroyed" warning.

Zones are matched by longest suffix, so `go.example.com` finds `example.com` in
`var.zones` with no per-entry zone. Only externally reachable apps need an entry
at all — `lhbotgo` has none, it dials Discord out.

One-time recipes, kept here rather than as tasks nobody runs twice:

```bash
# account + tunnel ID, without the dashboard: the connector token is base64 JSON
# {"a": account, "t": tunnel, "s": secret}
cd apps && SOPS_AGE_KEY_FILE=../secrets/age.key sops -d base/cloudflared/token.sops.yaml \
  | sed -n 's/.*token: //p' | base64 -d | jq '{account: .a, tunnel: .t}'

# zone name -> zone ID
curl -fsS "https://api.cloudflare.com/client/v4/zones?per_page=50" \
  -H "Authorization: Bearer $(cat secrets/cloudflare-api-token)" \
  | jq -r '.result[] | "\(.name) \(.id)"'

# the tunnel's live ingress rules, to transcribe into tfvars
curl -fsS "https://api.cloudflare.com/client/v4/accounts/$ACCT/cfd_tunnel/$TUN/configurations" \
  -H "Authorization: Bearer $(cat secrets/cloudflare-api-token)" | jq '.result.config.ingress'

# import blocks for CNAMEs that already exist
curl -fsS "https://api.cloudflare.com/client/v4/zones/$ZONE/dns_records?type=CNAME&per_page=100" \
  -H "Authorization: Bearer $(cat secrets/cloudflare-api-token)" \
  | jq -r --arg z "$ZONE" '.result[] | select(.content | endswith(".cfargotunnel.com"))
      | "import {\n  to = cloudflare_dns_record.tunnel[\"\(.name)\"]\n  id = \"\($z)/\(.id)\"\n}"'
```

If the tunnel is ever replaced, the new token has to reach the cluster:
`terraform output -raw tunnel_token` into a copy of
`apps/base/cloudflared/token.example.yaml`, then `mise run sops-encrypt`.
