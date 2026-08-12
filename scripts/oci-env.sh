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

for _v in oci_tenancy_ocid oci_user_ocid oci_fingerprint oci_region oci_compartment_ocid backup_user_email; do
  eval "[ -n \"\${TF_VAR_$_v:-}\" ]" || {
    echo "secrets/oci.env does not set TF_VAR_$_v" >&2
    unset _repo _v
    return 1 2>/dev/null || exit 1
  }
done

unset _repo _v
