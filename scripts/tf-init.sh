#!/usr/bin/env bash
#
# terraform init for any root, against the shared OCI state bucket.
#
#   tf-init.sh [--force] <root> [required-secret ...]

set -euo pipefail

repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

force=""
if [ "${1:-}" = "--force" ]; then
  force=1
  shift
fi

root=${1:?usage: tf-init.sh [--force] <root> [required-secret ...]}
shift

for f in oci_api_key.pem "$@"; do
  [ -s "$repo/secrets/$f" ] && continue

  echo "missing secrets/$f" >&2
  case "$f" in
  oci.env | oci_api_key.pem) echo "  copy 01-cloud-edge/terraform/oci.env.example" >&2 ;;
  tailscale-oauth.env) echo "  copy tailscale/tailscale-oauth.env.example" >&2 ;;
  cloudflare-api-token) echo "  see terraform/cloudflare/README.md" >&2 ;;
  esac
  exit 1
done

# `source` with no arguments leaves the caller's positional parameters in place,
# and oci-env.sh reads "$@" as extra variable names to require. Clear them.
set --

# shellcheck disable=SC1091
source "$repo/scripts/oci-env.sh"

cd "$repo/$root"

# .terraform/terraform.tfstate is where the resolved backend lands, so its
# absence means this root has never been initialised against the bucket — a bare
# .terraform/ is not enough (terraform init -backend=false leaves one).
[ -z "$force" ] && [ -s .terraform/terraform.tfstate ] && exit 0

# Not part of oci-env.sh's core set: the roots that need it as a *variable* ask
# for it by name.
[ -n "${TF_VAR_oci_namespace:-}" ] || {
  echo "TF_VAR_oci_namespace is not set — add it to secrets/oci.env" >&2
  echo "  Console: Tenancy details -> Object Storage namespace, or 'oci os ns get'" >&2
  exit 1
}

# The backend block itself is partial: bucket and key are in the config, the
# namespace and the API key are credentials and stay in secrets/.
#
# shellcheck disable=SC2154  # every TF_VAR_* below comes from oci-env.sh
#
# `auth` has to arrive as a flag: setting it inside the backend block instead
# makes every request come back 404 BucketNotFound, and without it the backend
# falls through to a credential chain that never reaches the API key.
#
# The retry is for the transient errors that same call returns: BucketNotFound
# on roughly one run in five against a bucket that is demonstrably there, and
# NotAuthenticated while a freshly created API key propagates. Anything else
# fails at once.
log=$(mktemp)
trap 'rm -f "$log"' EXIT

for attempt in 1 2 3; do
  # set +e around the pipeline: errexit would take the script out on the first
  # failure, before the BucketNotFound check below ever runs.
  set +e
  # shellcheck disable=SC2154  # every TF_VAR_* below comes from oci-env.sh
  terraform init -upgrade \
    -backend-config="auth=APIKey" \
    -backend-config="namespace=$TF_VAR_oci_namespace" \
    -backend-config="region=$TF_VAR_oci_region" \
    -backend-config="tenancy_ocid=$TF_VAR_oci_tenancy_ocid" \
    -backend-config="user_ocid=$TF_VAR_oci_user_ocid" \
    -backend-config="fingerprint=$TF_VAR_oci_fingerprint" \
    -backend-config="private_key_path=$TF_VAR_oci_private_key_path" 2>&1 | tee "$log"
  rc=${PIPESTATUS[0]}
  set -e

  [ "$rc" -eq 0 ] && exit 0
  grep -qE "BucketNotFound|NotAuthenticated" "$log" || exit "$rc"

  echo "transient Object Storage error (attempt $attempt/3) — retrying" >&2
  sleep 3
done

exit 1
