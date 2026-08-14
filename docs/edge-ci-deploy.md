# Deploying the edge from CI

`.github/workflows/edge-deploy.yml` runs `01-cloud-edge/scripts/deploy.sh` from
a GitHub runner that has joined the tailnet as `tag:ci`. It carries no SSH key
and no master age key.

- **SSH needs no key.** The edge runs `tailscaled --ssh`, and
  `tailscale/policy.hujson` accepts `tag:ci → tag:cloud-edge` as root. The rule
  is `accept`, never `check`: a check wants a human at a browser and would hang
  the runner until the job times out.
- **The runner is confined to port 22 on the edge.** One grant, and a `tests`
  case asserting everything else is denied — the API evaluates those at
  `terraform plan`, so widening the grant fails the PR.
- **The node is ephemeral** and reaped when the job ends.

## The auth key, under tailnet lock

A locked tailnet will not admit a node whose key is unsigned, and an ephemeral
node has no key to sign until it exists. The way out is a **pre-signed** auth
key: sign it once, and every node that uses it is trusted.

OAuth clients cannot be used for this — signing applies to auth keys.

1. In the admin console, create an auth key that is **reusable**, **ephemeral**,
   **pre-approved**, and tagged `tag:ci`.
2. On a node holding a trusted tailnet-lock key:

   ```bash
   tailscale lock sign tskey-auth-xxxxCTRL-xxxxxxxxxx
   ```

   It prints the signed key.
3. Put that value in `sops/terraform.sops.yaml` as `tailscale_ci_authkey`:

   ```bash
   mise exec -- sops sops/terraform.sops.yaml
   ```

The workflow passes `--statedir=/tmp/tailscale-state` to `tailscaled`, which is
where the client keeps the key-authority data it verifies the signature against.

Re-signing is only needed when the key itself is replaced. Watch the number of
signing keys if you automate rotation — tailscale/tailscale#16607 covers keys
accumulating when each deploy signs a fresh authkey.

## What else the job needs

`SOPS_AGE_KEY` in the `edge` environment — the same terraform-only key the other
two workflows use. Everything else the runner needs is inside
`sops/terraform.sops.yaml`: the signed auth key, and `edge_json`, which the job
writes to `01-cloud-edge/edge.json` before deploying.

## The master age key is still on the box

`deploy.sh` pushes `secrets/age.key` to `/var/lib/sops-nix/key.txt` only when it
finds one locally, so CI skips that step and the box keeps the key it was
installed with. That key decrypts every `apps/base/**/*.sops.yaml`, and it lives
on a public-internet-facing VM.

The fix is to give sops-nix the box's own SSH host key as its identity
(`sops.age.sshKeyPaths`) and make that host key a second recipient on
`01-cloud-edge/nixos/hosts/oracle-edge/secrets.sops.yaml`. Then an edge
compromise costs four values instead of every secret in the repo. That work is
Phase 1 of the plan in the vault (`Secretless Edge Deploy Plan`) and is not done
yet — CI deploying does not depend on it, but it is the reason to finish it.
