#!/usr/bin/env bash
# Phase 2: install NixOS over the Ubuntu instance Terraform created.
#
# nixos-anywhere kexecs into a NixOS installer, runs disko against
# nixos/hosts/edge-1/disk-config.nix, installs the closure and reboots. Nothing
# of the Ubuntu image survives.
#
# --build-on-remote is what makes this work at all from here: the build host is
# x86_64 and the instance is aarch64. The kexec image itself is substituted
# prebuilt from cache.nixos.org (a download, not a build, so no emulation), and
# the system closure is built by the installer on the box's own four Ampere
# cores.
#
# Destructive by design, and only correct on a box that holds nothing. It
# refuses to run against something that is already NixOS.
#
#   mise run install
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
repo=$(cd "$here/.." && pwd)
[ -s "$here/edge.json" ] || {
  echo "missing 00-edge-compute/edge.json — copy edge.json.example" >&2
  exit 1
}
host=$(jq -r '.instance.hostname' "$here/edge.json")
ip=${1:-$(terraform -chdir="$here/terraform" output -raw public_ip)}

ssh_opts=(-o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=/dev/null)

echo "==> $ip: waiting for SSH on the Ubuntu image"
deadline=$((SECONDS + 300))
until ssh "${ssh_opts[@]}" -o ConnectTimeout=5 "ubuntu@$ip" true 2>/dev/null; do
  if [ $SECONDS -ge $deadline ]; then
    echo "timed out waiting for SSH on $ip" >&2
    echo "check: is 22 open in ssh_ingress_cidr, and did cloud-init copy the key to root?" >&2
    exit 1
  fi
  sleep 5
done

if ssh "${ssh_opts[@]}" "ubuntu@$ip" 'test -e /etc/NIXOS' 2>/dev/null; then
  echo "$ip is already NixOS — install is a one-shot. Use 'mise run deploy'."
  exit 0
fi

echo "==> $ip: nixos-anywhere (kexec, disko, install, reboot)"

# scripts/nix.sh mounts $HOME/.ssh into the container read-only, which is right
# for every other consumer — they only read keys. nixos-anywhere writes: it
# generates a throwaway keypair for the post-kexec reconnect and hands it to
# ssh-copy-id, which wants a temp dir under ~/.ssh and dies with
# "failed to create required temporary directory under ~/.ssh (HOME=/root)".
#
# So point HOME at a writable copy for the duration, rather than remounting the
# real one rw for everything.
"$repo/scripts/nix.sh" "
  set -eu
  export HOME=/tmp/nixos-anywhere-home
  mkdir -p \"\$HOME/.ssh\"
  cp -a /root/.ssh/. \"\$HOME/.ssh/\" 2>/dev/null || true
  chmod 700 \"\$HOME/.ssh\"
  chmod 600 \"\$HOME\"/.ssh/* 2>/dev/null || true

  nix run github:nix-community/nixos-anywhere -- \
    --flake 'path:./00-edge-compute#$host' \
    --build-on-remote \
    --ssh-option StrictHostKeyChecking=accept-new \
    --target-host 'ubuntu@$ip'
"

echo "==> $ip: installed. Next: mise run deploy"
