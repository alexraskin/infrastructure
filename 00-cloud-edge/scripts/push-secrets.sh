set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
repo=$(cd "$here/.." && pwd)
[ -s "$here/edge.json" ] || {
  echo "missing 00-cloud-edge/edge.json — copy edge.json.example" >&2
  exit 1
}
host=$(jq -r '.instance.hostname' "$here/edge.json")
ip=$("$here/scripts/edge-addr.sh" "${1:-}")

ssh_opts=(-o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=/dev/null)

key=""
for candidate in "$repo/secrets/tailscale-authkey-edge" "$repo/secrets/tailscale-authkey"; do
  [ -s "$candidate" ] && { key=$candidate; break; }
done
if [ -z "$key" ]; then
  echo "no tailscale pre-auth key found." >&2
  echo "create a *tagged*, reusable key and write it to secrets/tailscale-authkey-edge" >&2
  exit 1
fi

token="$repo/secrets/cloudflare-api-token"
if [ ! -s "$token" ]; then
  echo "missing secrets/cloudflare-api-token — ACME DNS-01 cannot answer without it" >&2
  exit 1
fi

echo "==> $ip: tailscale pre-auth key ($(basename "$key"))"
scp "${ssh_opts[@]}" "$key" "root@$ip:/var/lib/tailscale-authkey"
ssh "${ssh_opts[@]}" "root@$ip" 'chmod 600 /var/lib/tailscale-authkey'

echo "==> $ip: cloudflare token for ACME DNS-01"
ssh "${ssh_opts[@]}" "root@$ip" "
  set -eu
  install -d -m 0700 /etc/cloudflare
  umask 077
  cat > /etc/cloudflare/credentials
" <<EOF
CLOUDFLARE_DNS_API_TOKEN=$(cat "$token")
EOF

echo "==> $ip: done"
