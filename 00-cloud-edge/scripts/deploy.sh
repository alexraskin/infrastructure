#!/usr/bin/env bash
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
[ -s "$here/edge.json" ] || {
  echo "missing 00-cloud-edge/edge.json — copy edge.json.example" >&2
  exit 1
}
host=$(jq -r '.instance.hostname' "$here/edge.json")
ip=$("$here/scripts/edge-addr.sh" "${1:-}")

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
# Detached, because this session is served by tailscaled: a switch that touches
# the tailscale unit kills its own connection mid-activation. The unit outlives
# the drop; the loop below reconnects and waits it out.
ssh "${ssh_opts[@]}" "root@$ip" "
  set -eu
  systemctl reset-failed edge-rebuild.service 2>/dev/null || true
  systemd-run --no-block --unit=edge-rebuild \
    --property=Type=oneshot --property=RemainAfterExit=yes \
    nixos-rebuild switch --flake 'path:/etc/nixos-edge#$host'
"

deadline=$((SECONDS + 1800))
printf '    '
while :; do
  state=$(ssh "${ssh_opts[@]}" -o ConnectTimeout=5 "root@$ip" \
    'systemctl show -p ActiveState --value edge-rebuild.service' 2>/dev/null) || state=""
  case "$state" in
    active | failed) break ;;
    "") printf '?' ;;
    *) printf '.' ;;
  esac
  if [ $SECONDS -ge $deadline ]; then
    echo
    echo "timed out waiting for edge-rebuild on $ip" >&2
    echo "check: journalctl -u edge-rebuild.service" >&2
    exit 1
  fi
  sleep 5
done
echo

ssh "${ssh_opts[@]}" "root@$ip" '
  journalctl -u edge-rebuild.service --no-pager -n 40
  state=$(systemctl show -p ActiveState --value edge-rebuild.service)
  systemctl stop edge-rebuild.service 2>/dev/null || true
  systemctl reset-failed edge-rebuild.service 2>/dev/null || true
  [ "$state" = active ]
' || {
  echo "nixos-rebuild failed on $ip" >&2
  exit 1
}

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
