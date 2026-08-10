#!/usr/bin/env bash
# The two credentials the box needs on disk before a switch can succeed.
#
# Same pattern as the cluster's push-token / push-tailscale-key: activation runs
# tailscaled-autoconnect, and the ACME DNS-01 challenge needs a token, so both
# have to be there first rather than "eventually".
#
#   mise run push-secrets
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
repo=$(cd "$here/.." && pwd)
ip=${1:-$(terraform -chdir="$here/terraform" output -raw public_ip)}

ssh_opts=(-o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=/dev/null)

# A separate tagged key is better than the cluster's: the ACL can then let this
# box reach the Plex backend and nothing else. Falls back to the shared one,
# which works but hands a public box the cluster's tag and its grants.
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

# lego reads CLOUDFLARE_DNS_API_TOKEN from this file. Written over stdin rather
# than scp'd so the token never lands in a temp file on either machine.
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
