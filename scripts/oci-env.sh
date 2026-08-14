# shellcheck shell=bash
# shellcheck disable=SC2317  # `return` here, `exit` when someone runs it anyway
#
# Sourced, never executed. Puts the OCI API key credentials in the environment
# as TF_VAR_*, so they reach both the oci provider and the terraform_remote_state
# data sources without ever landing in a tfvars file.
#
#   source scripts/oci-env.sh [extra-required-var ...]
#
# Extra names are checked on top of the core six, for roots that need more —
# terraform/oracle/ wants oci_compartment_ocid and backup_user_email.
#
# secrets/oci.env is optional when the variables are already exported, which is
# how CI supplies them.

_oci_repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

if [ -s "$_oci_repo/secrets/oci.env" ]; then
  # shellcheck disable=SC1091
  source "$_oci_repo/secrets/oci.env"
elif [ -z "${TF_VAR_oci_tenancy_ocid:-}" ]; then
  echo "missing secrets/oci.env — copy 01-cloud-edge/terraform/oci.env.example" >&2
  unset _oci_repo
  return 1 2>/dev/null || exit 1
fi

: "${TF_VAR_oci_private_key_path:=$_oci_repo/secrets/oci_api_key.pem}"
export TF_VAR_oci_private_key_path

[ -s "${TF_VAR_oci_private_key_path/#\~/$HOME}" ] || {
  echo "OCI signing key not found: $TF_VAR_oci_private_key_path" >&2
  echo "unset TF_VAR_oci_private_key_path in secrets/oci.env to use secrets/oci_api_key.pem" >&2
  unset _oci_repo
  return 1 2>/dev/null || exit 1
}

for _oci_v in oci_tenancy_ocid oci_user_ocid oci_fingerprint oci_region "$@"; do
  eval "[ -n \"\${TF_VAR_$_oci_v:-}\" ]" || {
    echo "TF_VAR_$_oci_v is not set — add it to secrets/oci.env" >&2
    [ "$_oci_v" = oci_namespace ] &&
      echo "  Console: Tenancy details -> Object Storage namespace, or 'oci os ns get'" >&2
    unset _oci_repo _oci_v
    return 1 2>/dev/null || exit 1
  }
done

unset _oci_repo _oci_v
