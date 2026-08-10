# Sourced by the tf:* mise tasks, never executed. Assembles the credentials
# Terraform needs, all from secrets/ and all as TF_VAR_* so that none of them
# reach a tfvars file, a plan output, or state.
#
#   source scripts/tf-env.sh

_here=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
_repo=$(cd "$_here/.." && pwd)

# Gitignored, so a fresh clone has none — and terraform's own error for a
# missing file() is a stack trace about a local, not a sentence about a file.
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

# Checked at the path Terraform will actually use, with ~ expanded the way
# providers.tf's pathexpand() does — an override in oci.env pointing somewhere
# that does not exist otherwise fails much later, as a bare 401
# "NotAuthenticated" that names nothing.
[ -s "${TF_VAR_oci_private_key_path/#\~/$HOME}" ] || {
  echo "OCI signing key not found: $TF_VAR_oci_private_key_path" >&2
  echo "unset TF_VAR_oci_private_key_path in secrets/oci.env to use secrets/oci_api_key.pem" >&2
  return 1 2>/dev/null || exit 1
}

# The same custom token terraform/cloudflare/ uses. Zone/DNS/Edit writes the A
# records; Zone/Zone/Read is what the zone lookup in dns.tf needs — a token
# without it gets an empty zone list rather than a 403.
_need cloudflare-api-token "the custom token with Zone/DNS/Edit + Zone/Zone/Read" ||
  return 1 2>/dev/null || exit 1
TF_VAR_cloudflare_api_token=$(cat "$_repo/secrets/cloudflare-api-token")
export TF_VAR_cloudflare_api_token

unset _repo _here
unset -f _need
