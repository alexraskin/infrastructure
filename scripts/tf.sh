#!/usr/bin/env bash
# Terraform, for every root in this repo.
#
#   scripts/tf.sh <root> <terraform args ...>   e.g. tf.sh proxmox plan
#   scripts/tf.sh <root> init                   re-resolve providers
#   scripts/tf.sh roots                         the dirs CI and the lint tasks read
#
# Roots: global proxmox cloudflare oracle tailscale edge
#
# Credentials come from sops/ — admin.sops.yaml locally, terraform.sops.yaml
# in CI. A backend block is resolved before any provider exists and wants a key
# file rather than a string, so that much is assembled here; everything else a
# root needs it reads through the sops provider.

set -euo pipefail

repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

root_dir() {
  case $1 in
  global) echo 00-global ;;
  proxmox) echo terraform/proxmox ;;
  cloudflare) echo terraform/cloudflare ;;
  oracle) echo terraform/oracle ;;
  tailscale) echo tailscale ;;
  edge) echo 01-cloud-edge/terraform ;;
  *) return 1 ;;
  esac
}

if [ "${1:-}" = roots ]; then
  for r in global edge tailscale cloudflare oracle proxmox; do root_dir "$r"; done | sort
  exit 0
fi

root=${1:?usage: tf.sh <root> <terraform args ...>   (roots: global proxmox cloudflare oracle tailscale edge)}
shift
dir=$(root_dir "$root") || {
  echo "unknown root: $root" >&2
  echo "  one of: global proxmox cloudflare oracle tailscale edge" >&2
  exit 1
}

# ------------------------------------------------------------- decryption ---

# The admin file first: it is the local source of truth, and it is the one CI
# cannot open, so CI falls through to the file its key does decrypt.
secrets=
why=$(mktemp)
trap 'rm -f "$why"' EXIT
for f in sops/admin.sops.yaml sops/terraform.sops.yaml; do
  if [ ! -s "$repo/$f" ]; then
    echo "$f: not there" >> "$why"
    continue
  fi
  secrets=$(sops --decrypt --output-type json "$repo/$f" 2>>"$why") && break
  secrets=
done

[ -n "$secrets" ] || {
  echo "no decryptable secrets file — see docs/terraform-sops.md" >&2
  sed 's/^/  /' "$why" >&2
  echo "  SOPS_AGE_KEY_FILE=${SOPS_AGE_KEY_FILE:-unset}" >&2
  exit 1
}

# A value pasted out of `export FOO="bar"` keeps the quote, and OCI reports that
# as 401 NotAuthenticated or as silent drift. Catch the whole class at once.
bad=$(jq -r 'to_entries[]
  | select(.value | type == "string")
  | select(.value | contains("\n") | not)
  | select(.value | test("^[[:space:]\"'"'"']|[[:space:]\"'"'"']$"))
  | .key' <<<"$secrets")
[ -z "$bad" ] || {
  echo "these values start or end with a quote or space — paste artefacts:" >&2
  # shellcheck disable=SC2086
  printf '  %s\n' $bad >&2
  echo "  fix them: sops sops/admin.sops.yaml" >&2
  exit 1
}

secret() {
  jq -re --arg k "$1" '.[$k] // empty' <<<"$secrets" || {
    echo "the secrets file has no $1" >&2
    return 1
  }
}

# The admin file names these oci_*, the CI one backend_* — same values, different
# identity: yours can create things, CI's can only read and write state objects.
backend_raw() {
  jq -re --arg a "backend_$1" --arg b "oci_$1" '.[$a] // .[$b] // empty' <<<"$secrets" || {
    echo "the secrets file has neither backend_$1 nor oci_$1" >&2
    return 1
  }
}

# Same, for the values that are a single identifier: a quote or space pasted
# along with one becomes a 401 from OCI, which says nothing about the cause.
backend() {
  local v
  v=$(backend_raw "$1") || return 1
  case $v in
  *[!A-Za-z0-9._:-]*)
    echo "$1 in the secrets file contains something that is not part of an OCID," >&2
    echo "  fingerprint or region — a quote or space pasted along with the value?" >&2
    echo "  OCI answers a malformed tenancy with 401 NotAuthenticated." >&2
    return 1
    ;;
  esac
  printf '%s' "$v"
}

key_file=${XDG_RUNTIME_DIR:-/tmp}/tf-oci-key-$(id -u).pem
log=$(mktemp)
trap 'rm -f "$key_file" "$log"' EXIT
(
  umask 077
  backend_raw private_key > "$key_file"
)
[ -s "$key_file" ] || {
  echo "the decrypted signing key is empty — check the private key block in the secrets file" >&2
  exit 1
}

# The terraform_remote_state data sources authenticate exactly as the backend
# does — one identity per request, from whichever file was decrypted here.
export TF_VAR_backend_private_key_path="$key_file"
TF_VAR_backend_namespace=$(backend namespace)
TF_VAR_backend_region=$(backend region)
TF_VAR_backend_tenancy_ocid=$(backend tenancy_ocid)
TF_VAR_backend_user_ocid=$(backend user_ocid)
TF_VAR_backend_fingerprint=$(backend fingerprint)
export TF_VAR_backend_namespace TF_VAR_backend_region TF_VAR_backend_tenancy_ocid \
  TF_VAR_backend_user_ocid TF_VAR_backend_fingerprint

# Both providers read the environment, so there is nothing for the sops provider
# to do in their roots. CI brings its own Tailscale OIDC credentials.
if [ "$root" = cloudflare ] && [ -z "${CLOUDFLARE_API_TOKEN:-}" ]; then
  CLOUDFLARE_API_TOKEN=$(secret cloudflare_api_token)
  export CLOUDFLARE_API_TOKEN
fi
if [ "$root" = tailscale ] && [ -z "${TAILSCALE_OAUTH_CLIENT_ID:-}" ]; then
  TAILSCALE_OAUTH_CLIENT_ID=$(secret tailscale_oauth_client_id)
  TAILSCALE_OAUTH_CLIENT_SECRET=$(secret tailscale_oauth_client_secret)
  export TAILSCALE_OAUTH_CLIENT_ID TAILSCALE_OAUTH_CLIENT_SECRET
fi

if [ "$root" = edge ] && [ ! -s "$repo/01-cloud-edge/edge.json" ]; then
  echo "missing 01-cloud-edge/edge.json — copy edge.json.example" >&2
  exit 1
fi

cd "$repo/$dir"

# ----------------------------------------------------------------- runner ---

# Object Storage returns BucketNotFound and NotAuthenticated spuriously; both
# are gone on the next attempt. An apply that started changing things is not.
retry() {
  local rc attempt
  for attempt in 1 2 3; do
    set +e
    "$@" 2>&1 | tee "$log"
    rc=${PIPESTATUS[0]}
    set -e

    [ "$rc" -eq 0 ] && return 0
    grep -qE "BucketNotFound|NotAuthenticated" "$log" || return "$rc"
    if grep -qE "^[^[:space:]]+: (Creating|Modifying|Destroying|Still)" "$log"; then
      echo "state error after resource work had started — not retrying" >&2
      return "$rc"
    fi

    echo "transient Object Storage error (attempt $attempt/3) — retrying" >&2
    sleep 5
  done
  return 1
}

# `auth` has to be a flag: in the backend block it makes every request 404.
init() {
  local namespace region tenancy user fingerprint
  namespace=$(backend namespace)
  region=$(backend region)
  tenancy=$(backend tenancy_ocid)
  user=$(backend user_ocid)
  fingerprint=$(backend fingerprint)

  # No -migrate-state or -reconfigure here: pass one in when a backend really
  # moved. tf.sh <root> init -reconfigure is the usual answer to a stale cache.
  retry terraform init -upgrade "$@" \
    -backend-config="auth=APIKey" \
    -backend-config="namespace=$namespace" \
    -backend-config="region=$region" \
    -backend-config="tenancy_ocid=$tenancy" \
    -backend-config="user_ocid=$user" \
    -backend-config="fingerprint=$fingerprint" \
    -backend-config="private_key_path=$key_file"
}

if [ "${1:-}" = init ]; then
  shift
  init "$@"
  exit
fi

# Where the resolved backend lands, so its absence means "never initialised".
# To stderr: callers capture the stdout of `tf.sh <root> output -raw ...`.
[ -s .terraform/terraform.tfstate ] || init >&2

# Always Free A1 capacity is usually gone: walk the availability domains.
if [ "$root" = edge ] && [ "${1:-}" = apply ]; then
  shift
  for idx in 0 1 2; do
    echo "==> apply, availability domain index $idx"
    set +e
    retry terraform apply -var "instance_availability_domain_index=$idx" "$@"
    rc=$?
    set -e
    [ "$rc" -eq 0 ] && exit 0

    if grep -qi "Out of host capacity" "$log"; then
      echo "no capacity in AD $idx — trying the next one"
      continue
    fi
    if grep -qiE "does not identify an element|Invalid index" "$log"; then
      echo "region has no AD at index $idx — every one it does have is full." >&2
      exit 1
    fi
    exit "$rc"
  done
  echo "every availability domain is out of A1 capacity — try again later." >&2
  exit 1
fi

retry terraform "$@"
