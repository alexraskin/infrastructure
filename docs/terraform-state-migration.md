# Moving Terraform state from R2 to Oracle Object Storage

Every root moved from `backend "s3"` (Cloudflare R2, no locking) to
`backend "oci"` (Object Storage, locking via `If-None-Match: *`). The bucket
those backends point at is created by the new `00-global/` root.

**Done on 2026-08-14.** All six roots live in the bucket and plan clean; what is
left is the teardown in section 4. The pre-migration state of every root — the
five R2 objects plus `00-global`'s local file — is in
`~/tf-state-backup-20260814-071543/`, outside the repo. Kept as the record of
how it went, because three of the traps below will bite again on any future
backend move.

Requires Terraform **1.12+** (`backend "oci"` does not exist before that) —
`mise.toml` and `01-cloud-edge/mise.toml` both pin 1.15.

## The three traps

- **`auth` must be a `-backend-config` flag, not a line in the backend block.**
  In the block it is ignored *and* poisons the credential chain: every request
  comes back `404 BucketNotFound` on a bucket that plainly exists. Without it
  the backend never reaches the API key at all. `scripts/tf-init.sh` passes
  `-backend-config="auth=APIKey"`. In a `terraform_remote_state` `config` map,
  where there are no flags, `auth = "APIKey"` does work.
- **Object Storage answers with a spurious `BucketNotFound`**, on `init`,
  `plan` and `state pull` alike. Worst right after the bucket is created and it
  decays: ~25% of calls at bucket age 15 minutes, ~5% at 90 minutes.
  `tf-init.sh` retries that one error three times, and
  `OCI_SDK_DEFAULT_RETRY_ENABLED=true` (set in both mise configs and both deploy
  workflows) cut a 12-call sample from 3 failures to 1.
- **`-migrate-state` could not read the R2 side.** The cached
  `.terraform/terraform.tfstate` was written by Terraform 1.9's `s3` backend and
  carries `assume_role_duration_seconds`, which 1.15's schema rejects:
  `Failed to decode current backend config`. So the actual move was
  download-from-R2 + `init -reconfigure` + `terraform state push`, section 2b.

## 0. Before anything

Keep a copy of the state that carries the cluster PKI. It is the one file in
this repo that cannot be regenerated:

```bash
cd terraform/proxmox
terraform state pull > ~/talos-proxmox.tfstate.backup   # NOT inside the repo
```

Do the same for any root you would rather not rebuild by hand.

**Do not delete any `.terraform/` directory.** It still holds the resolved R2
backend, which is what `-migrate-state` reads the old state through.

## 1. Create the bucket

Put the Object Storage namespace in `secrets/oci.env` first — every backend
block in the repo is initialised against it, and `00-global/` takes it as a
variable too:

```bash
oci os ns get        # or Console -> Tenancy details -> Object Storage namespace
```

```bash
export TF_VAR_oci_namespace="<the namespace>"
```

`00-global/` creates the bucket its own backend block points at, so its first
apply has to run with that block absent — a `backend` block binds `apply`, not
just `init`, and `-backend=false` does not change that. There is no task for
this; it happens once:

```bash
cd 00-global
mv backend.tf backend.tf.disabled
source ../scripts/oci-env.sh oci_compartment_ocid oci_namespace
terraform init -upgrade          # no backend block, so this is local state
terraform apply
mv backend.tf.disabled backend.tf
```

Then migrate `00-global`'s own state into the bucket it just made:

```bash
source scripts/oci-env.sh
cd 00-global
terraform init -migrate-state \
  -backend-config="auth=APIKey" \
  -backend-config="namespace=$TF_VAR_oci_namespace" \
  -backend-config="region=$TF_VAR_oci_region" \
  -backend-config="tenancy_ocid=$TF_VAR_oci_tenancy_ocid" \
  -backend-config="user_ocid=$TF_VAR_oci_user_ocid" \
  -backend-config="fingerprint=$TF_VAR_oci_fingerprint" \
  -backend-config="private_key_path=$TF_VAR_oci_private_key_path"
```

Answer `yes` to "Do you want to copy existing state to the new backend?", then
delete the local `terraform.tfstate` it leaves behind. This is the one root the
`-migrate-state` path worked for — its source was a local state file, not the
1.9-era `s3` cache.

## 2. Migrate the other five roots

| root | key in the bucket |
| --- | --- |
| `terraform/proxmox` | `talos-proxmox/terraform.tfstate` |
| `terraform/cloudflare` | `cloudflare-k3s/terraform.tfstate` |
| `terraform/oracle` | `oracle/terraform.tfstate` |
| `tailscale` | `tailscale/terraform.tfstate` |
| `01-cloud-edge/terraform` | `edge-compute/terraform.tfstate` |

### 2a. What `-migrate-state` would look like

Only usable when the cached backend in `.terraform/` can still be decoded — for
these five it could not (trap 3), so this is here for the next move, not this
one:

```bash
source scripts/oci-env.sh          # from the repo root, once per shell
cd terraform/proxmox
terraform init -migrate-state -backend-config="auth=APIKey" \
  -backend-config="namespace=$TF_VAR_oci_namespace" \
  ... the rest as in section 1 ...
terraform plan                     # must be "No changes"
```

### 2b. Download and push — what actually ran

```bash
# 1. every object out of R2 first, into a directory outside the repo
f=secrets/r2.tfbackend
export AWS_ACCESS_KEY_ID=$(sed -n 's/^[[:space:]]*access_key[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' "$f")
export AWS_SECRET_ACCESS_KEY=$(sed -n 's/^[[:space:]]*secret_key[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' "$f")
export AWS_DEFAULT_REGION=auto        # R2 rejects the aws CLI's default region
export AWS_REQUEST_CHECKSUM_CALCULATION=when_required
export AWS_RESPONSE_CHECKSUM_VALIDATION=when_required
EP=$(sed -n 's/.*s3[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' "$f")

aws s3 cp s3://terraform/talos-proxmox/terraform.tfstate ~/backup/ --endpoint-url "$EP"

# 2. point the root at the new backend, discarding the undecodable old one
cd terraform/proxmox
terraform init -reconfigure -backend-config="auth=APIKey" \
  -backend-config="namespace=$TF_VAR_oci_namespace" \
  ... the rest as in section 1 ...

# 3. push, but only into an empty remote — check first
terraform state list                       # must print nothing
terraform state push ~/backup/terraform.tfstate
terraform state list | wc -l               # resource count, instances expanded
terraform plan                             # must be "No changes"
```

Compare the pushed address list against the backup rather than trusting the
count: a state file's `resources` array counts resource *blocks*, while
`state list` expands `count`/`for_each` instances, so the two numbers differ
legitimately (proxmox: 21 blocks, 46 addresses).

A `plan` that wants to create everything means nothing was pushed.

## 3. Check the lock actually works

Locking is the entire point of the move. Prove it once:

```bash
cd terraform/proxmox
terraform plan -lock-timeout=0 > /dev/null 2>&1 &
terraform plan -lock-timeout=0        # start both at once, or the first finishes first
```

One of the two fails with `Error acquiring the state lock`, naming the lock ID,
`Path: talos-proxmox/terraform.tfstate` and who holds it. Verified on
2026-08-14.

A stale lock after a killed run is `terraform force-unlock <ID>`; the object is
`<key>.lock` in the bucket and can also be deleted from the console.

## 4. Tear down the R2 side

Every root plans clean as of 2026-08-14, so this is the outstanding work:

- Delete the `terraform` bucket in R2 (or keep it read-only for a while — it is
  cold state, and it still contains the cluster PKI, so treat it as a secret
  either way).
- Delete the R2 API token.
- Delete `secrets/r2.tfbackend`.
- Replace the GitHub Actions secrets `R2_ACCESS_KEY_ID`, `R2_SECRET_ACCESS_KEY`
  and `R2_S3_ENDPOINT` with the six `OCI_*` values `mise run global:ci-creds`
  prints, in **both** the `cloudflare` and `tailscale` environments. Those are
  the `terraform-ci` user's, not the API key in `secrets/oci.env` — CI gets
  `read buckets` + `manage objects` on the state bucket and nothing else.

The R2 bucket holding Loki chunks is unrelated and stays.
