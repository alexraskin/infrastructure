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
holds `import` blocks for the tunnel, its config and every DNS record it owns,
so the connector token already in `apps/base/cloudflared/token.sops.yaml` stays
valid and cloudflared never restarts. A correct plan is "N to import, 0 to add,
0 to destroy". If it wants to *create* the tunnel, an import block is missing or
`tunnel_id` is wrong — applying then builds a second tunnel and moves the CNAMEs
to one with no connectors, which is the outage case.

**`imports.tf` is gitignored**, because every block in it names a hostname and
a Cloudflare record ID. Once the import has been applied the file is inert —
the resources are in state, and an `import` block for something already managed
is a no-op — so nothing here depends on it existing, CI included. It is kept
locally only as the recovery path for a lost state file. Rebuilding it does not
need the old copy; the record IDs come back from the API:

```bash
curl -s -H "Authorization: Bearer $(cat ../../secrets/cloudflare-api-token)" \
  "https://api.cloudflare.com/client/v4/zones/<zone_id>/dns_records?per_page=100" \
  | jq -r '.result[] | "\(.id)\t\(.type)\t\(.name)"'
```

with the tunnel's own two blocks keyed `<account_id>/<tunnel_id>`, both of which
are already in `terraform.tfvars`. If state is ever lost and this file is *not*
rebuilt first, the "Guard against destructive plans" step in CI fails the run
rather than letting the apply create a second tunnel.

`var.ingress` is the whole tunnel config. Order only matters for overlapping
rules (paths, wildcards), so a plan that merely reorders distinct hostnames is
inert; a rule that disappears from the list is deleted on apply. The catch-all
is appended automatically — Cloudflare requires the list to end with a rule that
has no hostname. `origin_request = {} -> null` on an adopted config is the
provider's round-trip noise, not a change. The config resource has no DELETE
endpoint, hence the standing "cannot be destroyed" warning.

`var.extra_dns_records` carries records that have nothing to do with the tunnel.
Today that is one: `bunker`, the PVE host's own A record — a private address,
deliberately unproxied, since it is both how the web UI is reached on the LAN
and the name on the host's ACME certificate (`terraform/proxmox/acme.tf`). It
was adopted the same way the CNAMEs were, with an `import` block. The rest of
the zone is still click-ops on purpose: `phx.ddns` is rewritten by a DDNS
client and the `_acme-challenge` TXTs by ACME clients, so Terraform would fight
both, and the two `*.cloud` / `*.relay` wildcards already belong to
`00-cloud-edge/terraform/dns.tf`.

Zones are matched by longest suffix, so `go.example.com` finds `example.com` in
`var.zones` with no per-entry zone. Only externally reachable apps need an entry
at all — `lhbotgo` has none, it dials Discord out.

## CI

`.github/workflows/cloudflare-deploy.yml` mirrors the tailscale one: plan on a
PR, plan **and apply** on a push to `main` that touches this directory, plus a
`workflow_dispatch` with an `apply` toggle. It runs in the `cloudflare`
environment and needs five secrets — `CLOUDFLARE_API_TOKEN`,
`CLOUDFLARE_TFVARS`, and the three `R2_*` the tailscale job already uses. No
`id-token: write`: unlike Tailscale's OAuth, this provider takes a plain token.

Two things differ from the tailscale job, both because this repo is public:

- **`terraform.tfvars` is not in git**, so CI writes `ci.auto.tfvars` from the
  `CLOUDFLARE_TFVARS` secret before `init`. Keep that secret in step with the
  local file — a variable added to one and not the other fails CI at plan with
  `No value for required variable`, since `TF_INPUT=false`.
- **Plan and apply output is redirected to a file, not the log.** A plan names
  every hostname in `var.ingress`, and the logs of a public repo are public.
  Only the `Plan:`/`No changes.` line and `Apply complete!` are echoed; on
  failure the job prints an error and withholds the output. Read real plans
  locally with `mise run cf:plan`.

Because the plan is invisible, the **"Guard against destructive plans"** step
carries the review that a human would otherwise do: it reads
`terraform show -json` and fails on any `delete`, or on the tunnel planning as
`create`. That second case is the outage described above — import blocks not
matching — and auto-apply would otherwise walk straight into it. The step
prints resource *types and names* only, never addresses, because an address
carries the hostname as its map key.

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
