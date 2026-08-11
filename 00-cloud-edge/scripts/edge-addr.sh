#!/usr/bin/env bash
# Where to reach the box over SSH.
#
# Not terraform's public_ip: 22 is closed in the OCI security list, so that
# address only answers on 443. Everything after `install` goes over the tailnet.
# An explicit argument wins, for the window where neither is true.
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

if [ "${1:-}" != "" ]; then
  echo "$1"
  exit 0
fi

[ -s "$here/edge.json" ] || {
  echo "missing 00-cloud-edge/edge.json — copy edge.json.example" >&2
  exit 1
}
host=$(jq -r '.instance.hostname' "$here/edge.json")

command -v tailscale >/dev/null 2>&1 || {
  echo "no tailscale CLI here, and 22 is closed on the public IP" >&2
  echo "join the tailnet, or pass an address explicitly" >&2
  exit 1
}

addr=$(tailscale ip -4 "$host" 2>/dev/null) || addr=""
[ -n "$addr" ] || {
  echo "$host is not a peer on this tailnet — check 'tailscale status'" >&2
  echo "a box that has never been installed has no tailnet address yet;" >&2
  echo "that is what 'mise run install' and the public IP are for" >&2
  exit 1
}

echo "$addr"
