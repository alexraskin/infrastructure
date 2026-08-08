#!/usr/bin/env bash
# Build one node's system closure, push it over SSH and activate it.
#
# This is what `nixos-rebuild switch --target-host` does, spelled out, so it
# also works when the build host only has nix in a container (scripts/nix.sh).
#
#   scripts/deploy-node.sh k3s-agent-2
set -euo pipefail

repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
host=${1:?usage: deploy-node.sh <host from hosts.json>}

# mise sets this, but the script is also run directly. Without it `nix copy`
# spawns an ssh that fails host key verification on a freshly built VM.
export NIX_SSHOPTS="${NIX_SSHOPTS:--o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=/dev/null}"

ip=$(jq -r --arg h "$host" '.nodes[$h].ip // empty' "$repo/hosts.json")
if [ -z "$ip" ]; then
  echo "unknown host: $host" >&2
  exit 1
fi

echo "==> $host ($ip): build"
out=$("$repo/scripts/nix.sh" "nix build '.#nixosConfigurations.$host.config.system.build.toplevel' --no-link --print-out-paths")

echo "==> $host ($ip): copy $out"
"$repo/scripts/nix.sh" "
  set -eu
  nix copy --no-check-sigs --to 'ssh://root@$ip' '$out'
  ssh \$NIX_SSHOPTS 'root@$ip' \
    'nix-env -p /nix/var/nix/profiles/system --set $out && /nix/var/nix/profiles/system/bin/switch-to-configuration switch'
"
echo "==> $host ($ip): done"
