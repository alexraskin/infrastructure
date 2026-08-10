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
