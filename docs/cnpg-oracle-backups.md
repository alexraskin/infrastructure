# CloudNativePG backups to Oracle Object Storage

## Context

`apps/base/cnpg/cluster/cluster.yaml` has no `spec.backup`. Three Postgres
instances hold gatus' uptime history and — as of this session — Grafana's
dashboard, user and preference database. Storage is `db-local`: node-pinned
`local` PVs on the db nodes' second disk. Losing one node loses one replica and
the cluster survives, but a bad `DROP` or losing all three is unrecoverable, and
there is no point-in-time restore. Both `cluster.yaml` and
`apps/base/cnpg/CLAUDE.md` already name this gap and prescribe
`spec.backup.barmanObjectStore` as the fix.

They prescribe **R2**. This plan uses **Oracle Object Storage** instead, because
the intent is to consolidate more of this setup onto the Oracle free tier — the
edge already lives there. That is a deliberate departure and both places need
rewriting; the "no new dependency" argument the docs lean on no longer applies.

`terraform/oracle/` already exists with a single empty `main.tf`. It is
untracked and is the only uncommitted path in the repo besides this work.

**Decisions taken:**

| | |
|---|---|
| Endpoint | **Plaintext in `cluster.yaml`.** `endpointURL` is a plain string in the CRD with no secret ref. The namespace identifies the tenancy but is not a credential. |
| Credential | **Terraform-created**, `terraform output -raw` into a SOPS file by hand — the flow the repo already documents for the cloudflared tunnel token. |
| Schedule | **Weekly base backup, `retentionPolicy: 30d`**, plus continuous WAL archiving. |

**Verified against chart 0.29.0 / operator 1.30.0**: in-tree
`spec.backup.barmanObjectStore` is still present and carries no deprecation
notice. No barman-cloud plugin migration is needed. Schema confirmed:
`destinationPath`, `endpointURL`, `endpointCA`, `s3Credentials`, `data`, `wal`,
`serverName`, `tags`; `s3Credentials` is `{accessKeyId, secretAccessKey, region,
sessionToken, inheritFromIAMRole}` where every field is a `SecretKeySelector`.

---

## 1. `terraform/oracle/` — a fourth root

Follows the conventions in `terraform/cloudflare/providers.tf` and
`01-cloud-edge/terraform/`. Backend inline in `providers.tf` (the cloudflare
style), not a separate `backend.tf`.

- **`providers.tf`** — `required_version = ">= 1.6"`; partial `backend "s3"`
  with `bucket = "terraform"`, **`key = "oracle-backups/terraform.tfstate"`**
  (a fifth unique key), `region = "auto"`, the five `skip_*` flags and
  `use_path_style = true`; `oracle/oci ~> 6`. Provider block copies
  `01-cloud-edge/terraform/providers.tf` verbatim — same five variables,
  `private_key_path = pathexpand(var.oci_private_key_path)`.
- **`variables.tf`** — the six OCI variables (`oci_tenancy_ocid`,
  `oci_user_ocid`, `oci_fingerprint`, `oci_private_key_path`, `oci_region`,
  `oci_compartment_ocid`) matching `01-cloud-edge/terraform/variables.tf`
  exactly, plus `bucket_name` (default `cnpg-backups`).
- **`objectstorage.tf`** — `data.oci_objectstorage_namespace.this` and
  `oci_objectstorage_bucket.cnpg` with `access_type = "NoPublicAccess"`,
  `storage_tier = "Standard"`, versioning disabled. No lifecycle policy:
  CNPG's own `retentionPolicy` deletes expired backups, and a second expiry
  mechanism fighting it would delete WALs a base backup still needs.
- **`iam.tf`** — a **dedicated least-privilege user**, not the Terraform API
  user. `oci_identity_user.cnpg_backup`, `oci_identity_group.cnpg_backup`,
  `oci_identity_user_group_membership`, `oci_identity_policy` (created in the
  tenancy, statements referencing the compartment by name via
  `data.oci_identity_compartment.this.name`) granting `manage objects` and
  `read buckets` scoped with `where target.bucket.name = var.bucket_name`, and
  `oci_identity_customer_secret_key.cnpg_backup`. This mirrors the reasoning in
  `apps/base/loki/CLAUDE.md` for scoping the Loki token to one bucket: the
  credential lives in a Secret that anything with pod-exec can read.
- **`outputs.tf`** — `endpoint_url` (assembled from the namespace and
  `var.oci_region`), `bucket`, `access_key_id`, and `secret_access_key` marked
  `sensitive`.
- **`CLAUDE.md`** — new, following the pattern of the other root docs.

**`01-cloud-edge/scripts/tf-env.sh` cannot be reused.** It hard-requires
`01-cloud-edge/edge.json` and `secrets/cloudflare-api-token`, and derives
`_repo` from its own location. Add **`scripts/oci-env.sh`** at the repo root: the
same `secrets/oci.env` + `secrets/oci_api_key.pem` logic with the edge- and
Cloudflare-specific parts removed. Note the duplication in the new `CLAUDE.md`
rather than refactoring the edge's copy — that script is load-bearing for a
working deploy path and this is a 20-line overlap.

## 2. `mise.toml` — an `oci:*` prefix

**`tf:` is already taken twice** — root `mise.toml` (proxmox) and
`01-cloud-edge/mise.toml` (the edge). Use `oci:` in the root config, following
the `cf:*` block at `mise.toml:66` for shape.

- `oci:init` — `scripts/tf-init.sh --force terraform/oracle oci.env`, which
  guards the secrets and assembles the backend config. (Written against the R2
  backend originally; state now lives in Object Storage — see
  `terraform-state-migration.md`.)
- `oci:plan` / `oci:apply` — `depends = ["oci:init"]`, `source ../../scripts/oci-env.sh`.
- `oci:creds` — prints the two output values in the exact key order of the
  example Secret, so pasting into SOPS is mechanical.

## 3. `apps/base/cnpg/cluster/` — the backup config

- **`backup-oci.example.yaml`** (committed template, modelled on
  `apps/base/loki/r2.example.yaml` including its header comment explaining where
  the values come from and the encrypt command) and **`backup-oci.sops.yaml`**
  (encrypted). Secret `cnpg-backup-oci` in `cnpg-system`, `Opaque`, keys
  `access-key-id`, `secret-access-key`, `region`.

  `region` is in the Secret only because `s3Credentials.region` is a
  `SecretKeySelector` — it is not a secret, and it is already visible in
  `endpointURL`. It is set explicitly rather than omitted because boto3 needs a
  region for SigV4 signing and the default it would otherwise pick is not
  Oracle's.

- **`cluster.yaml`** — add `spec.backup`:

  ```yaml
  backup:
    retentionPolicy: 30d
    barmanObjectStore:
      destinationPath: s3://cnpg-backups/
      endpointURL: https://<namespace>.compat.objectstorage.<region>.oraclecloud.com
      s3Credentials:
        accessKeyId:     { name: cnpg-backup-oci, key: access-key-id }
        secretAccessKey: { name: cnpg-backup-oci, key: secret-access-key }
        region:          { name: cnpg-backup-oci, key: region }
      data: { compression: gzip, jobs: 2 }
      wal:  { compression: gzip, maxParallel: 2 }
  ```

  `serverName` is left at its default (the cluster name, `postgres`). Replace
  the existing "no backup configured … against R2" comment block with one
  explaining the Oracle choice and the WAL risk below.

- **`scheduledbackup.yaml`** — `ScheduledBackup` `postgres-weekly` in
  `cnpg-system`, `cluster.name: postgres`, `backupOwnerReference: self`,
  `immediate: true` so the first base backup is taken on creation rather than
  waiting a week.

  **CNPG's `schedule` is a six-field cron with seconds first.** `"0 0 3 * * 0"`
  is Sunday 03:00. A five-field expression is silently misread.

- **`kustomization.yaml`** — add `backup-oci.sops.yaml` and
  `scheduledbackup.yaml`. The `cnpg-cluster` Flux Kustomization already carries
  the `decryption` block, so nothing changes in `apps/clusters/talos/apps.yaml`.

## 4. Docs

- **New `terraform/oracle/CLAUDE.md`** — the dedicated IAM user and why, the
  state key, the `oci:*` tasks, the Customer Secret Key being returned only at
  creation, and the credential-to-SOPS handoff.
- **`apps/base/cnpg/CLAUDE.md`** — replace "No backups yet, and what that means"
  wholesale. Cover: weekly base + continuous WAL, 30d retention, the least-
  privilege OCI user, the WAL-accumulation failure mode, and the restore recipe.
- **`apps/base/cnpg/cluster/cluster.yaml`** — the comment block noted above.
- **Root `CLAUDE.md`** — add `oci:*` to the commands list, `terraform/oracle/`
  to the "Where the rest of the docs live" table, and a line in "Terraform state
  lives in R2" noting the fifth key.
- **`README.md`** — `secrets/` inventory already lists `oci.env` and
  `oci_api_key.pem`; add `terraform/oracle/` wherever the roots are enumerated.

---

## Order of execution

1. Copy this plan to `docs/cnpg-oracle-backups.md`.
2. Write `terraform/oracle/` and `scripts/oci-env.sh`; `terraform fmt` and
   `validate`.
3. Add the `oci:*` tasks to `mise.toml`.
4. `mise run oci:plan`, review, `mise run oci:apply`.
5. `mise run oci:creds`, fill `backup-oci.sops.yaml` from
   `backup-oci.example.yaml`, encrypt with
   `cd apps && mise exec -- sops --encrypt --in-place base/cnpg/cluster/backup-oci.sops.yaml`
   (the `sops-encrypt` task is broken — see `apps/CLAUDE.md`).
6. Paste the real `endpointURL` into `cluster.yaml`.
7. Write the docs, commit, push. **Nothing reaches the cluster until this is
   pushed** — Flux only reads git.
8. `cd apps && mise run sync`, then verify below **immediately** — see the WAL
   risk.

## Verification

```bash
terraform -chdir=terraform/oracle validate && terraform fmt -recursive terraform/
cd apps && mise exec -- kustomize build base/cnpg/cluster >/dev/null

# the operator accepted the config
kubectl -n cnpg-system get cluster postgres -o jsonpath='{.status.conditions}' | jq

# WAL archiving is the thing that must work first
kubectl -n cnpg-system get cluster postgres \
  -o jsonpath='{.status.conditions[?(@.type=="ContinuousArchiving")]}' | jq

# the immediate base backup
kubectl -n cnpg-system get backup
kubectl -n cnpg-system get cluster postgres -o jsonpath='{.status.firstRecoverabilityPoint}'

# objects actually landed
oci os object list --bucket-name cnpg-backups --namespace <ns> | head
```

End to end, the only test that counts is a restore: create a second `Cluster`
with `bootstrap.recovery.source` pointing at an `externalCluster` with the same
`barmanObjectStore`, let it recover, `psql` one table, delete it. Worth doing
once now rather than discovering the gap during an incident.

## Risks

- **A broken credential fills the database PVs and takes the cluster down.**
  Once `barmanObjectStore` is set, Postgres will not recycle a WAL segment until
  `archive_command` succeeds. If the credential, endpoint or bucket policy is
  wrong, `pg_wal` grows on the 90Gi `db-local` volumes until they are full — and
  a full `pg_wal` stops Postgres. This is the single reason step 8 says verify
  immediately: check the `ContinuousArchiving` condition before walking away. If
  it is failing and cannot be fixed quickly, remove `spec.backup` to restore the
  old behaviour.
- **The Customer Secret Key is only returned at creation** and lands in
  Terraform state. `CLAUDE.md` already treats that state as a secret store, so
  this is consistent — but losing state means the credential cannot be read
  back, only replaced.
- **Always Free caps: 20 GiB and 50,000 API requests/month.** Weekly base
  backups plus WAL for databases this size are comfortably inside both. The
  request count is the one that could move: every WAL segment is an upload, so a
  short `archive_timeout` on a busy database is what would approach 50k. Worth
  re-checking Oracle's current Always Free terms before relying on it.
- **No state locking.** Terraform 1.9 predates `use_lockfile`; single operator,
  accepted, same as the other roots.
- **Backups depend on a second cloud provider being reachable.** The cluster
  already egresses to the internet for images, so this adds no new network path,
  but it does mean an Oracle outage stops WAL archiving — see the first risk.

## Out of scope, still open

Unrelated to this plan but outstanding in the working tree and the cluster:

- Loki cannot resolve `loki-memberlist.logging.svc.cluster.local` after its
  restart, so no logs are being ingested.
- Edge → Loki over the tailnet is diagnosed but unfixed (the tailscale
  LoadBalancer proxy DNATs to a ClusterIP that Cilium will not translate on the
  forwarded path); the fix is switching that Service to a tailscale Ingress.
- The live cluster carries `bpf-lb-external-clusterip: true`, reverted in git;
  the next `mise run cilium` clears the drift.
- The Grafana-on-CNPG change set is committed but the `tf:apply` that drops the
  `grafana` user volume has not run; when it does, prometheus and loki need a
  rollout restart (root `CLAUDE.md` gotcha).
- Something in the editor strips YAML comments on save; it has already landed
  once in commit `9a94e15`.
