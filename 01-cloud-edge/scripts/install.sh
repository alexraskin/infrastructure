#!/usr/bin/env bash
# Replace the Ubuntu instance Terraform created with NixOS via nixos-anywhere.
# Destructive; refuses to run on a box that is already NixOS.
# --build-on-remote because this host is x86_64 and the instance aarch64.
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

# sops-nix derives its age identity from the host key, so seed the same one
# before activation or the secrets stop decrypting.
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

# nix.sh mounts ~/.ssh read-only; nixos-anywhere needs to write there.
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
