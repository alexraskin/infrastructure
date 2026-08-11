# tailscale/ — the tailnet policy file

A third Terraform root, holding one resource: `tailscale_acl.policy`, whose
`acl` is `file("policy.hujson")`. That is the tailnet's *entire* policy file,
not just its `acls` block — the resource name predates Tailscale's rename — so
an apply overwrites whatever is in the admin console. State is in the same R2
bucket as the other two roots, `key = "tailscale/terraform.tfstate"`.

- It **adopts**, like `terraform/cloudflare/`: `policy.tf` carries a permanent
  `import` block with `id = "acl"` (there is one policy file per tailnet). The
  import is not optional — `overwrite_existing_content` is left at `false`, and
  the provider then refuses to write a policy it has never read. That is the
  guard against a fresh state replacing a hand-edited policy. The block is
  *in* `policy.tf` rather than an `imports.tf` because `.gitignore` excludes
  that filename.
- **`terraform plan` validates the policy against the Tailscale API**, tests
  included, so a syntax error or a failing `tests` entry fails the PR instead of
  the apply. This is the whole reason to run plan on pull requests.
- **Two different credentials, by design.** CI authenticates as a *federated
  identity* — `TAILSCALE_OAUTH_CLIENT_ID` + `TAILSCALE_AUDIENCE`, both repo
  *variables*, not secrets. The provider mints the GitHub OIDC token itself and
  exchanges it, which is why the job needs `permissions: id-token: write` and
  why no Tailscale secret exists in this public repo's Actions. Running by hand
  uses an OAuth client instead, `secrets/tailscale-oauth.env`, scoped to
  `policy_file:write`. `audience` and `oauth_client_secret` conflict in the
  provider, so neither is written into `providers.tf`: `provider "tailscale" {}`
  is empty and everything arrives through the environment.
- **`tailnet` is deliberately unset**, defaulting to the tailnet that owns the
  credential — the name is the one part of this worth not publishing, same
  reasoning as `grafana-tailnet.sops.yaml`.
- The federated identity's subject claim binds to
  `repo:<owner>/<repo>:environment:tailscale`, which is why the job declares
  `environment: tailscale`. A workflow that omits it cannot authenticate even
  from this repo.
- Terraform 1.9 means no state locking here either, so the workflow's
  `concurrency: { group: tailscale, cancel-in-progress: false }` is what keeps
  two applies apart.

```bash
mise run ts:plan     # from the repo root; needs secrets/tailscale-oauth.env
mise run ts:apply    # CI does this on push to main
```

## The five Tailscale credentials, and which is which

They are all different, none substitutes for another, and the names are close
enough to confuse. A cluster rebuild touches exactly one of them.

| credential | lives in | what it is | on a rebuild |
| --- | --- | --- | --- |
| `secrets/tailscale-oauth.env` | build host | OAuth client, scope `policy_file:write`. Only `ts:plan` / `ts:apply` by hand use it. | keep |
| `TAILSCALE_OAUTH_CLIENT_ID` + `TAILSCALE_AUDIENCE` | GitHub repo *variables* | federated identity for CI, same scope, no stored secret | keep |
| `oauth.sops.yaml` → Secret `operator-oauth` | the cluster | OAuth client with **Devices Core (write)** and **Auth Keys (write)**, tagged `tag:k8s-operator`. The operator mints its own device keys from it. | keep — Flux re-applies it |
| `secrets/tailscale-authkey` | was pushed to every node | tagged pre-auth key for the k3s subnet routers | **dead.** Revoke it and delete the file |
| `secrets/tailscale-authkey-edge` | the Oracle edge | tagged `tag:cloud-edge`, still NixOS | keep, unrelated |

Nothing has to be re-minted. The operator's client keeps working because tags,
not clients, are what a rebuild changes.

## The tags

`tagOwners` is the whole mechanism: an OAuth client may create a device with any
tag its own tag **owns**. The operator is `tag:k8s-operator`, and everything it
creates is a tag that names `tag:k8s-operator` as owner — which is why adding a
new proxy kind needs a policy change, not a new credential.

| tag | worn by | owned by |
| --- | --- | --- |
| `tag:k8s-operator` | the operator itself (`talos-operator`) | nobody — admins only |
| `tag:k8s` | every Ingress and egress proxy it spawns | `tag:k8s-operator` |
| `tag:k8s-loki` | Loki's operator-served LoadBalancer, split out so the edge's grant stays narrow | `tag:k8s-operator` |
| `tag:k8s-router` | the `Connector` subnet router — **new**; `autoApprovers` gives it `10.0.200.0/24` | `tag:k8s-operator` |
| `tag:cloud-edge` | the Oracle box | nobody |
| ~~`tag:k3s`~~ | the old NixOS nodes | removed |

## What the policy file cannot do

Four things live only in the admin console, and a cluster rebuild is when they
bite:

- **Delete the old devices.** Nothing here reaps them. After a rebuild the
  tailnet still lists whatever the previous cluster registered, and a stale
  device holding the same *hostname* makes the new one come up as
  `name-1`, `name-2`, … — which breaks MagicDNS names that other config hard-codes
  (`00-cloud-edge`'s Loki push URL, the Grafana `GF_SERVER_*` values). Remove
  them before or immediately after the rebuild.
- **The operator's OAuth client** (`secrets/…` → `operator-oauth`), needing the
  Devices Core and Auth Keys **write** scopes and the `tag:k8s-operator` tag.
  Its tag must own every tag it hands out — `tag:k8s`, `tag:k8s-loki`,
  `tag:k8s-router` — which the `tagOwners` block here declares but the console
  is what enforces at device-creation time.
- **MagicDNS and HTTPS Certificates**, both on the DNS page. Without them the
  operator has no cert to fetch and an Ingress never goes ready.
- **Nothing else needs approving.** `autoApprovers` covers the Connector's
  `10.0.200.0/24` (`tag:k8s-router`) and the edge's exit node, so neither waits
  on a human — provided this policy is applied *before* the devices appear.
