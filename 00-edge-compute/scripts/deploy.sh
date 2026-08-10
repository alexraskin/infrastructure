#!/usr/bin/env bash
# Phase 3: switch the box to the current flake.
#
# Unlike scripts/deploy-node.sh at the repo root, this does not build locally
# and `nix copy` the closure over: the build host is x86_64 and this instance is
# aarch64, so cross-building would need binfmt emulation or a remote builder.
# The A1 has four Ampere cores, so the flake goes to the box and the box builds.
#
# tar over ssh rather than rsync — rsync has to exist on both ends, and it is
# not in a minimal NixOS system profile. The tree is a few kilobytes; a delta
# would save nothing.
#
#   mise run deploy
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
[ -s "$here/edge.json" ] || {
  echo "missing 00-edge-compute/edge.json — copy edge.json.example" >&2
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

# path: keeps nix from walking up looking for a git repo. /etc/nixos-edge is not
# one, so this also sidesteps the untracked-files trap scripts/nix.sh guards
# against at the repo root.
echo "==> $ip: nixos-rebuild switch (building on the box)"
ssh "${ssh_opts[@]}" "root@$ip" "
  set -eu
  nixos-rebuild switch --flake 'path:/etc/nixos-edge#$host'
"

# nixos-anywhere activates the full config at install time, before this script
# has ever run — so the first acme attempt happens with /etc/cloudflare/credentials
# still absent and dies with "Failed to load environment files". A later switch
# does not retry it: the unit's definition has not changed, so
# switch-to-configuration leaves the failed oneshot alone, and HAProxy keeps
# serving the self-signed placeholder acme drops in so services can start. The
# symptom is a site that works on :443 and fails verification.
#
# Starting it explicitly is idempotent — the unit checks expiry and exits
# without touching LetsEncrypt when the cert is still good.
echo "==> $ip: acme"
for domain in $(jq -r '.sites[].domain' "$here/edge.json"); do
  ssh "${ssh_opts[@]}" "root@$ip" "systemctl start 'acme-$domain.service'" ||
    echo "  acme-$domain failed — check: journalctl -u acme-$domain.service" >&2
done

echo "==> $ip: done"
ssh "${ssh_opts[@]}" "root@$ip" 'tailscale status --peers=false 2>/dev/null || true'
