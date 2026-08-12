#!/usr/bin/env bash
#
# terraform init for any of the five roots, against the shared R2 backend.
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

for f in r2.tfbackend "$@"; do
  [ -s "$repo/secrets/$f" ] && continue

  echo "missing secrets/$f" >&2
  case "$f" in
  r2.tfbackend) echo "  copy terraform/r2.tfbackend.example" >&2 ;;
  oci.env | oci_api_key.pem) echo "  see terraform/oracle/CLAUDE.md" >&2 ;;
  tailscale-oauth.env) echo "  copy tailscale/tailscale-oauth.env.example" >&2 ;;
  cloudflare-api-token) echo "  see terraform/cloudflare/README.md" >&2 ;;
  esac
  exit 1
done

cd "$repo/$root"

# .terraform/terraform.tfstate is where the resolved backend lands, so its
# absence means this root has never been initialised against R2 — a bare
# .terraform/ is not enough (terraform init -backend=false leaves one).
[ -z "$force" ] && [ -s .terraform/terraform.tfstate ] && exit 0

terraform init -upgrade -backend-config="$repo/secrets/r2.tfbackend"
