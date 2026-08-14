# Terraform's secrets

Everything Terraform needs to authenticate lives in two SOPS files, encrypted in
git. The only thing to keep safe outside the repo is the age key.

| file | holds | age key |
| --- | --- | --- |
| `sops/terraform.sops.yaml` | the `terraform-ci` OCI credentials the backend uses, the Cloudflare token, the Tailscale OAuth pair | the terraform key **and** the personal one |
| `sops/admin.sops.yaml` | the OCI API key that can create and destroy, the Proxmox token, the IAM user emails | the personal key only |

Two files because CI gets a key. The deploy workflows only ever plan the
`cloudflare` and `tailscale` roots, so the key they hold opens the first file
and nothing else — not the admin credentials, not `apps/`, not the edge.

## Which keys go where

`sops/admin.sops.yaml` — read locally, by `scripts/tf.sh` and by the sops
provider in `global`, `oracle`, `proxmox` and `edge`:

```yaml
oci_tenancy_ocid:      # also serves as the backend credential locally
oci_user_ocid:
oci_fingerprint:
oci_region:
oci_namespace:
oci_private_key: |
oci_compartment_ocid:
ci_user_email:
backup_user_email:
pve_api_token:
cloudflare_api_token:          # the edge root, and local cloudflare runs
tailscale_oauth_client_id:     # local tailscale runs; CI federates instead
tailscale_oauth_client_secret:
ssh_public_key:                # the key cloud-init puts on the edge box
```

`sops/terraform.sops.yaml` — what CI decrypts:

```yaml
backend_tenancy_ocid:   # the terraform-ci user, from `mise run global:ci-creds`
backend_user_ocid:
backend_fingerprint:
backend_region:
backend_namespace:
backend_private_key: |
cloudflare_api_token:
tailscale_oauth_client_id:
tailscale_oauth_client_secret:
```

`tf.sh` tries the admin file first and falls back to the CI one, taking
`backend_*` or `oci_*` whichever it finds. So locally the backend authenticates
as you, in CI as `terraform-ci` — and filling the CI file does not depend on
being able to read it.

## How it reaches Terraform

- **Providers** read it themselves, through `data "sops_file"`. No `TF_VAR_`
  plumbing, no plaintext file on disk.
- **The backend cannot.** A `backend` block is resolved before any provider
  exists, and it takes `private_key_path` — a file, with no inline-key form. So
  `scripts/tf.sh` decrypts `sops/terraform.sops.yaml`, writes the key to a `mktemp`
  file it removes on exit, and passes the rest as `-backend-config` flags. The
  `terraform_remote_state` data sources in `cloudflare` and `tailscale` take the
  same path, as `var.backend_private_key_path`.

That is the whole reason a wrapper script exists. Run terraform through it:

```bash
scripts/tf.sh proxmox plan          # or: mise run proxmox:plan
```

## Day to day

```bash
sops sops/terraform.sops.yaml              # edit; re-encrypts on save
sops --decrypt sops/terraform.sops.yaml    # look without editing
```

`mise` points `SOPS_AGE_KEY_FILE` at `secrets/age.key`, which holds **both**
identities — one file, two `AGE-SECRET-KEY-` lines.

## First-time setup

1. Generate the CI key, keep the private half in 1Password:

   ```bash
   age-keygen -o /tmp/age-terraform.key
   grep public /tmp/age-terraform.key          # the recipient
   cat /tmp/age-terraform.key >> secrets/age.key
   ```

2. Put that recipient in `.sops.yaml`, replacing
   `REPLACE_WITH_THE_TERRAFORM_AGE_RECIPIENT`.

3. The admin file first — nothing else works until it decrypts:

   ```bash
   cp sops/admin.sops.yaml.example sops/admin.sops.yaml
   $EDITOR sops/admin.sops.yaml          # values from the old secrets/oci.env
   sops --encrypt --in-place sops/admin.sops.yaml
   head -3 sops/admin.sops.yaml          # must show ENC[
   ```

4. Now the CI file, whose `backend_*` values come from a command that needed
   step 3 to work:

   ```bash
   mise run global:ci-creds                 # prints them in this file's shape
   cp sops/terraform.sops.yaml.example sops/terraform.sops.yaml
   $EDITOR sops/terraform.sops.yaml
   sops --encrypt --in-place sops/terraform.sops.yaml
   ```

5. Give CI the key, and take away what it replaces:

   ```bash
   gh secret set SOPS_AGE_KEY --env cloudflare < /tmp/age-terraform.key
   gh secret set SOPS_AGE_KEY --env tailscale  < /tmp/age-terraform.key
   for e in cloudflare tailscale; do
     for s in OCI_TENANCY_OCID OCI_USER_OCID OCI_FINGERPRINT OCI_NAMESPACE OCI_REGION OCI_API_KEY; do
       gh secret delete "$s" --env "$e"
     done
   done
   gh secret delete CLOUDFLARE_API_TOKEN --env cloudflare
   shred -u /tmp/age-terraform.key
   ```

6. Delete what the old scheme needed: `secrets/oci.env`,
   `secrets/oci_api_key.pem`, `secrets/cloudflare-api-token`,
   `secrets/tailscale-oauth.env`, and the `pve_api_token` line in
   `terraform/proxmox/terraform.tfvars`.

`CLOUDFLARE_TFVARS` stays: it is configuration — hostnames, zone and tunnel IDs
— not a credential.

## Rotating

- **Cloudflare token, Tailscale OAuth pair, Proxmox token**: change them at the
  source, `sops` the file, commit.
- **The terraform-ci OCI key**: `terraform taint tls_private_key.ci` in
  `00-global`, apply, paste what `mise run global:ci-creds` prints into
  `sops/terraform.sops.yaml`. The old key dies the moment the apply replaces
  `oci_identity_api_key.ci`.
- **The age key**: add the new recipient to `.sops.yaml`, `sops updatekeys` both
  files, update the GitHub secret.

## What is in state

The sops provider puts every value it reads into Terraform state, in the clear.
That is already true of the tunnel token and the CNPG Customer Secret Key, and
the state bucket is treated as a secret store — see `CLAUDE.md`.
