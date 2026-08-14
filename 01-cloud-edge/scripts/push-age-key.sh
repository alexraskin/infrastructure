#!/usr/bin/env bash
# The one secret that cannot be committed: the age key sops-nix decrypts
# nixos/hosts/oracle-edge/secrets.sops.yaml with.
#
# Everything else the box needs is in that file, encrypted, in git. This runs
# before `nixos-rebuild switch` because activation installs the secrets, and
# activation fails if the key is not there yet.
#
#   mise run push-age-key
set -euo pipefail

# shellcheck source-path=SCRIPTDIR
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

key="$repo/secrets/age.key"

[ -s "$key" ] || {
  echo "missing secrets/age.key" >&2
  echo "  the same key apps/.sops.yaml encrypts to — restore it from 1Password" >&2
  exit 1
}

ip=$(edge_addr "${1:-}")

echo "==> $ip: age key -> /var/lib/sops-nix/key.txt"
edge_ssh "$ip" '
  set -eu
  install -d -m 0755 /var/lib/sops-nix
  umask 077
  cat > /var/lib/sops-nix/key.txt
  chmod 0400 /var/lib/sops-nix/key.txt
' < "$key"
