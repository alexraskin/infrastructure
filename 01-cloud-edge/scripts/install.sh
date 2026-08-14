#!/usr/bin/env bash
# Phase 2: install NixOS over the Ubuntu instance Terraform created.
#
# nixos-anywhere kexecs into a NixOS installer, runs disko against
# nixos/hosts/oracle-edge/disk-config.nix, installs the closure and reboots. Nothing
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

# shellcheck source-path=SCRIPTDIR
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

host=$(edge_host)
ip=${1:-$("$repo/scripts/tf.sh" edge output -raw public_ip)}

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

# An identity sops-nix can decrypt with has to be on the disk before the
# installer activates the config, or activation fails and takes the whole
# install with it. --extra-files copies this tree to / on the target.
#
# The host key is what matters: sops-nix derives its age identity from it, and
# a freshly generated one would leave a box whose secrets no longer decrypt.
# Seeding the same key every time keeps the recipient in .sops.yaml valid across
# reinstalls. The age key is seeded too only while secrets.nix still lists
# keyFile as a fallback — drop that block here once it does not.
extra="$repo/secrets/.extra-files"
rm -rf "$extra"
trap 'rm -rf "$extra"' EXIT

host="$repo/secrets/edge-host-ed25519"
[ -s "$host" ] || {
  echo "missing secrets/edge-host-ed25519 — restore it from 1Password" >&2
  echo "  it is the box's /etc/ssh/ssh_host_ed25519_key, and the second" >&2
  echo "  recipient in 01-cloud-edge/.sops.yaml is derived from it" >&2
  exit 1
}
install -d -m 0755 "$extra/etc/ssh"
install -m 0600 "$host" "$extra/etc/ssh/ssh_host_ed25519_key"
install -m 0644 "$host.pub" "$extra/etc/ssh/ssh_host_ed25519_key.pub"

key="$repo/secrets/age.key"
if [ -s "$key" ]; then
  install -d -m 0755 "$extra/var/lib/sops-nix"
  install -m 0400 "$key" "$extra/var/lib/sops-nix/key.txt"
fi

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
    --flake 'path:./01-cloud-edge#$host' \
    --build-on-remote \
    --extra-files './secrets/.extra-files' \
    --ssh-option StrictHostKeyChecking=accept-new \
    --target-host 'ubuntu@$ip'
"

echo "==> $ip: installed. Next: mise run deploy"
