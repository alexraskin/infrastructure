#!/usr/bin/env bash
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
[ -s "$here/edge.json" ] || {
  echo "missing 00-cloud-edge/edge.json — copy edge.json.example" >&2
  exit 1
}
host=$(jq -r '.instance.hostname' "$here/edge.json")
ip=${1:-$(terraform -chdir="$here/terraform" output -raw public_ip)}

ssh_opts=(-o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=/dev/null)

"$here/scripts/push-secrets.sh" "$ip"

echo "==> $ip: copying the flake -> /etc/nixos-edge"
tar -C "$here" -cf - flake.nix flake.lock edge.json nixos \
  | ssh "${ssh_opts[@]}" "root@$ip" '
      rm -rf /etc/nixos-edge
      mkdir -p /etc/nixos-edge
      tar -C /etc/nixos-edge -xf -
    '

echo "==> $ip: nixos-rebuild switch (building on the box)"
ssh "${ssh_opts[@]}" "root@$ip" "
  set -eu
  nixos-rebuild switch --flake 'path:/etc/nixos-edge#$host'
"

echo "==> $ip: acme"
certs=$(jq -r '
  (.wildcards // []) as $w
  | $w + [ .sites[].domain
           | select((split(".") | .[1:] | join(".")) as $parent
                    | ($w | index($parent)) == null) ]
  | unique[]
' "$here/edge.json")

for cert in $certs; do
  ssh "${ssh_opts[@]}" "root@$ip" "systemctl start 'acme-$cert.service'" ||
    echo "  acme-$cert failed — check: journalctl -u acme-$cert.service" >&2
done

echo "==> $ip: done"
ssh "${ssh_opts[@]}" "root@$ip" 'tailscale status --peers=false 2>/dev/null || true'
