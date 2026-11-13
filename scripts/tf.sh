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
# role in CI. Secrets are SSM parameters too: the cloudflare and tailscale
# providers get theirs handed over here, every other root reads them itself.

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

# ---------------------------------------------------------------- secrets ---

# SecureStrings under /infrastructure/, owned by 00-global.
secret() {
  aws ssm get-parameter --region us-east-1 --with-decryption \
    --name "/infrastructure/$1" --query Parameter.Value --output text
}

# Both providers read the environment, so their tokens are exported here.
# CI brings its own Tailscale OIDC credentials.
if [ "$root" = cloudflare ] && [ -z "${CLOUDFLARE_API_TOKEN:-}" ]; then
  CLOUDFLARE_API_TOKEN=$(secret cloudflare/api_token)
  export CLOUDFLARE_API_TOKEN
fi
if [ "$root" = tailscale ] && [ -z "${TAILSCALE_OAUTH_CLIENT_ID:-}" ]; then
  TAILSCALE_OAUTH_CLIENT_ID=$(secret tailscale/oauth_client_id)
  TAILSCALE_OAUTH_CLIENT_SECRET=$(secret tailscale/oauth_client_secret)
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
