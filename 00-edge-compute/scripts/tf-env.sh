# Sourced by the tf:* mise tasks, never executed. Assembles the credentials
# Terraform needs, all from secrets/ and all as TF_VAR_* so that none of them
# reach a tfvars file, a plan output, or state.
#
#   source scripts/tf-env.sh

_here=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
_repo=$(cd "$_here/.." && pwd)

[ -s "$_here/edge.json" ] || {
  echo "missing 00-edge-compute/edge.json — copy edge.json.example" >&2
  return 1 2>/dev/null || exit 1
}

_need() {
  [ -s "$_repo/secrets/$1" ] || {
    echo "missing secrets/$1 — $2" >&2
    return 1
  }
}

_need oci.env "copy 00-edge-compute/oci.env.example" || return 1 2>/dev/null || exit 1
# shellcheck disable=SC1090
source "$_repo/secrets/oci.env"

: "${TF_VAR_oci_private_key_path:=$_repo/secrets/oci_api_key.pem}"
export TF_VAR_oci_private_key_path

[ -s "${TF_VAR_oci_private_key_path/#\~/$HOME}" ] || {
  echo "OCI signing key not found: $TF_VAR_oci_private_key_path" >&2
  echo "unset TF_VAR_oci_private_key_path in secrets/oci.env to use secrets/oci_api_key.pem" >&2
  return 1 2>/dev/null || exit 1
}

_need cloudflare-api-token "the custom token with Zone/DNS/Edit + Zone/Zone/Read" ||
  return 1 2>/dev/null || exit 1
TF_VAR_cloudflare_api_token=$(cat "$_repo/secrets/cloudflare-api-token")
export TF_VAR_cloudflare_api_token

unset _repo _here
unset -f _need
