_r2_repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
_r2_file="$_r2_repo/secrets/r2.tfbackend"

[ -s "$_r2_file" ] || {
  echo "missing secrets/r2.tfbackend — copy terraform/r2.tfbackend.example" >&2
  return 1 2>/dev/null || exit 1
}

_r2_value() { sed -n "s/^[[:space:]]*$1[[:space:]]*=[[:space:]]*\"\([^\"]*\)\".*/\1/p" "$_r2_file"; }

AWS_ACCESS_KEY_ID=$(_r2_value access_key)
AWS_SECRET_ACCESS_KEY=$(_r2_value secret_key)
AWS_ENDPOINT_URL_S3=$(sed -n 's/.*s3[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' "$_r2_file")

for _r2_name in AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_ENDPOINT_URL_S3; do
  [ -n "${!_r2_name}" ] || {
    echo "could not read $_r2_name out of secrets/r2.tfbackend" >&2
    return 1 2>/dev/null || exit 1
  }
done

export AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_ENDPOINT_URL_S3
unset _r2_repo _r2_file _r2_name
