# Sourced by the oci:* mise tasks, never executed. Assembles the OCI credentials
# Terraform needs, all from secrets/ and all as TF_VAR_* so that none of them
# reach a tfvars file, a plan output, or state.
#
#   source scripts/oci-env.sh
#
# Deliberately a second copy of the OCI half of 00-cloud-edge/scripts/tf-env.sh
# rather than a shared file: that one also requires 00-cloud-edge/edge.json and
# secrets/cloudflare-api-token, neither of which this root has any use for, and
# it resolves the repo root from its own location inside 00-cloud-edge/.

_repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

[ -s "$_repo/secrets/oci.env" ] || {
  echo "missing secrets/oci.env — copy 00-cloud-edge/oci.env.example" >&2
  return 1 2>/dev/null || exit 1
}

# shellcheck disable=SC1090
source "$_repo/secrets/oci.env"

: "${TF_VAR_oci_private_key_path:=$_repo/secrets/oci_api_key.pem}"
export TF_VAR_oci_private_key_path

[ -s "${TF_VAR_oci_private_key_path/#\~/$HOME}" ] || {
  echo "OCI signing key not found: $TF_VAR_oci_private_key_path" >&2
  echo "unset TF_VAR_oci_private_key_path in secrets/oci.env to use secrets/oci_api_key.pem" >&2
  return 1 2>/dev/null || exit 1
}

# backup_user_email is not a credential, but it is an email address and this repo
# is public, so it rides along in secrets/oci.env like everything else here.
for _v in oci_tenancy_ocid oci_user_ocid oci_fingerprint oci_region oci_compartment_ocid backup_user_email; do
  eval "[ -n \"\${TF_VAR_$_v:-}\" ]" || {
    echo "secrets/oci.env does not set TF_VAR_$_v" >&2
    unset _repo _v
    return 1 2>/dev/null || exit 1
  }
done

unset _repo _v
