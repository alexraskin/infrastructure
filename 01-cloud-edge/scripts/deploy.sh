#!/usr/bin/env bash
set -euo pipefail

# shellcheck source-path=SCRIPTDIR
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

host=$(edge_host)
ip=$(edge_addr "${1:-}")

# CI has no master key and must not: the box keeps the one it was installed
# with. Locally this refreshes it, which is what makes a rebuild survive a
# rotated key.
if [ -s "$repo/secrets/age.key" ]; then
  "$edge/scripts/push-age-key.sh" "$ip"
else
  echo "==> no local age key — leaving /var/lib/sops-nix/key.txt as it is"
fi

echo "==> $ip: copying the flake -> /etc/nixos-edge"
tar -C "$edge" -cf - flake.nix flake.lock edge.json nixos \
  | edge_ssh "$ip" '
      rm -rf /etc/nixos-edge
      mkdir -p /etc/nixos-edge
      tar -C /etc/nixos-edge -xf -
    '

echo "==> $ip: nixos-rebuild switch (building on the box)"
# Detached, because this session is served by tailscaled: a switch that touches
# the tailscale unit kills its own connection mid-activation. The unit outlives
# the drop; the loop below reconnects and waits it out.
edge_ssh "$ip" "
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

edge_ssh "$ip" '
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
' "$edge/edge.json")

for cert in $certs; do
  edge_ssh "$ip" "systemctl start 'acme-$cert.service'" ||
    echo "  acme-$cert failed — check: journalctl -u acme-$cert.service" >&2
done

echo "==> $ip: done"
edge_ssh "$ip" 'tailscale status --peers=false 2>/dev/null || true'
