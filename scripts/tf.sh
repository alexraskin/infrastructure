#!/usr/bin/env bash
# Terraform, for every root in this repo.
#
#   scripts/tf.sh <root> <terraform args ...>   e.g. tf.sh proxmox plan
#   scripts/tf.sh <root> init                   re-resolve providers
#   scripts/tf.sh roots                         the dirs CI and the lint tasks read
#
# Roots: global proxmox cloudflare oracle tailscale edge
#
# State is in S3 (alexraskin-tfstate, under infrastructure/), and the backend
# takes its credentials from the environment: `aws sso login` locally, an OIDC
# role in CI. Only the cloudflare and tailscale providers need a secret handed
# to them here; every other root reads sops/ through the sops provider.

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

secrets=
load_secrets() {
  [ -z "$secrets" ] || return 0
  local f why
  why=$(mktemp)
  # The admin file first: it is the local source of truth, and it is the one CI
  # cannot open, so CI falls through to the file its key does decrypt.
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
    rm -f "$why"
    exit 1
  }
  rm -f "$why"
}

secret() {
  load_secrets
  jq -re --arg k "$1" '.[$k] // empty' <<<"$secrets" || {
    echo "the secrets file has no $1" >&2
    return 1
  }
}

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

log=$(mktemp)
trap 'rm -f "$log"' EXIT

# No -migrate-state or -reconfigure here: pass one in when a backend really
# moved. tf.sh <root> init -reconfigure is the usual answer to a stale cache.
init() {
  terraform init -upgrade "$@"
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
    terraform apply -var "instance_availability_domain_index=$idx" "$@" 2>&1 | tee "$log"
    rc=${PIPESTATUS[0]}
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

terraform "$@"
