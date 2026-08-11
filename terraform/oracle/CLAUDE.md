# terraform/oracle/ — the CloudNativePG backup bucket

A fourth Terraform root, holding one Object Storage bucket and the least-
privilege OCI identity that writes to it. `apps/base/cnpg/cluster/` consumes
both. State in R2 under `oracle/terraform.tfstate`.

Its own root rather than resources in `00-cloud-edge/terraform/` even though the
credentials are identical: that root owns the public edge instance, its VCN and
its DNS, and a backup bucket has no business planning against any of it. Same
reasoning that keeps `terraform/cloudflare/` apart from `terraform/proxmox/`.

## Credentials, and the second copy of tf-env.sh

The OCI variables arrive as `TF_VAR_*` from `secrets/oci.env`, via
**`scripts/oci-env.sh`** — never a tfvars file, so none of them reach a plan
output or a diff. The signing key defaults to `secrets/oci_api_key.pem`.

That script is deliberately a second copy of the OCI half of
`00-cloud-edge/scripts/tf-env.sh` rather than a shared file. The original also
requires `00-cloud-edge/edge.json` and `secrets/cloudflare-api-token`, neither of
which this root uses, and resolves the repo root relative to its own location
inside `00-cloud-edge/`. Twenty duplicated lines beat making the edge's deploy
path depend on this one.

## Tasks are `oci:*`, not `tf:*`

`tf:` is already taken twice — the Proxmox root in the top-level `mise.toml` and
the edge root in `00-cloud-edge/mise.toml`.

```bash
mise run oci:plan     # sources scripts/oci-env.sh
mise run oci:apply
mise run oci:creds    # prints the values backup-oci.sops.yaml and cluster.yaml need
```

`oci:init` guards on `secrets/oci.env`, `secrets/oci_api_key.pem` and
`secrets/r2.tfbackend`, then inits with `-backend-config`. `scripts/oci-env.sh`
additionally fails fast if `secrets/oci.env` is missing any of the six
`TF_VAR_*` values, `backup_user_email` included — the edge's copy of that file
predates it, so an existing `oci.env` needs the line added. As everywhere else
here, a bare `terraform init` prompts for the missing backend values and writes
them into `.terraform/` — use the task.

## This is an Identity Domains tenancy

Two things follow, both learned by watching the first apply fail:

- **`oci_identity_user` requires `email`.** The legacy IAM API is shimmed onto
  SCIM in an identity-domain tenancy, and SCIM rejects a user without a primary
  email: `400-IdcsConversionError ... The primary email must be specified`. It
  comes from `TF_VAR_backup_user_email` in `secrets/oci.env` — not a credential,
  but an email address in a public repo, so it lives with the rest.
- **The compartment here *is* the tenancy root.** `oci_compartment_ocid` and
  `oci_tenancy_ocid` are the same OCID, and a policy statement scoped at the root
  must say `in tenancy`. Using the compartment's name instead — which is the
  tenancy name, `drycoin6658` — fails with "does not exist or is not part of the
  policy compartment subtree". `local.policy_scope` picks the right form, so
  moving the bucket into a real child compartment later needs no edit.

## A dedicated user, not the API user

`iam.tf` creates `cnpg-backup` as its own user, group and policy rather than
minting a Customer Secret Key against the user in `secrets/oci.env`. The
credential ends up in a Kubernetes Secret, which anything with pod-exec in the
cluster can read; handing that out with the Terraform user's rights would hand
out the edge instance with it. The same reasoning scopes Loki's R2 token to one
bucket (`apps/base/loki/CLAUDE.md`).

The policy is two statements, both `where target.bucket.name = '<bucket>'`:
`read buckets` (barman-cloud checks the bucket exists before its first upload)
and `manage objects`. Their scope comes from `local.policy_scope` — see the
Identity Domains section above; `data.oci_identity_compartment.this` supplies the
compartment *name* for the non-root case, because statements never take an OCID.
IAM lives in the tenancy, so the user, group and policy are all created against
`var.oci_tenancy_ocid` no matter where the bucket sits.

## The Customer Secret Key exists only in state

`oci_identity_customer_secret_key.key` is returned by the OCI API **once, at
creation**. It is not readable afterwards through the console or the API, so R2
state is the only copy — consistent with the root `CLAUDE.md` line about treating
R2 state as a secret store, and the same posture as the Talos machine secrets.
Losing state means creating a new key and re-encrypting the Secret, not
recovering the old one.

Getting it into the cluster is by hand, the same handoff the cloudflared tunnel
token uses:

```bash
mise run oci:creds
cp apps/base/cnpg/cluster/backup-oci.example.yaml apps/base/cnpg/cluster/backup-oci.sops.yaml
$EDITOR apps/base/cnpg/cluster/backup-oci.sops.yaml
cd apps && mise exec -- sops --encrypt --in-place base/cnpg/cluster/backup-oci.sops.yaml
```

and the `endpointURL` line from the same output goes into
`apps/base/cnpg/cluster/cluster.yaml`.

## Gotchas

- **No lifecycle policy on the bucket, on purpose.** CNPG's
  `backup.retentionPolicy` already deletes expired backups and the WAL they no
  longer need. An object-age rule running alongside it would eventually delete
  WAL segments that a still-valid base backup depends on, and that only shows up
  at restore.
- **The bucket name appears in three places** — `var.bucket_name`, the two IAM
  policy statements, and `destinationPath` in `cluster.yaml`. The first two move
  together; the third is in a different repo directory and does not.
- **Always Free is 20 GiB of Object Storage and 50,000 API requests a month**
  across the tenancy, shared with anything else put there. Every WAL segment is
  an upload, so the request count is the number that moves with database write
  volume, not the storage.
- **No state locking.** Terraform 1.9 predates `use_lockfile`, same as every
  other root here. Single operator, accepted.
