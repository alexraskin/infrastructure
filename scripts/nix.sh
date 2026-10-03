#!/usr/bin/env bash

set -euo pipefail

repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
script=${1:?usage: nix.sh <shell script>}


export NIX_CONFIG="experimental-features = nix-command flakes
system-features = kvm nixos-test benchmark big-parallel uid-range"

untracked=$(git -C "$repo" ls-files --others --exclude-standard -- \
  01-cloud-edge || true)
if [ -n "$untracked" ]; then
  echo "error: these files are untracked and would be invisible to the flake:" >&2
  printf '  %s\n' $untracked >&2
  echo "run: git -C $repo add $untracked" >&2
  exit 1
fi

if command -v nix >/dev/null 2>&1; then
  cd "$repo"
  printf '%s' "$script" | bash -s
  exit
fi

image=${NIX_DOCKER_IMAGE:-nixos/nix:2.31.2}

args=(
  --rm --interactive
  --volume "k3s-nix-store:/nix"
  --volume "$repo:/work"
  --workdir /work
  --volume "$HOME/.ssh:/root/.ssh:ro"
  --env "NIX_CONFIG=$NIX_CONFIG"
  --env "NIX_SSHOPTS=${NIX_SSHOPTS:-}"
)

gitconfig=${XDG_CACHE_HOME:-$HOME/.cache}/nix-container-gitconfig
if [ ! -f "$gitconfig" ]; then
  mkdir -p "$(dirname "$gitconfig")"
  printf '[safe]\n\tdirectory = /work\n' > "$gitconfig"
fi
args+=(--volume "$gitconfig:/root/.gitconfig:ro")

if [ -e /dev/kvm ]; then
  args+=(--device /dev/kvm)
fi

if [ -n "${SSH_AUTH_SOCK:-}" ] && [ -S "${SSH_AUTH_SOCK}" ]; then
  args+=(--volume "$SSH_AUTH_SOCK:/ssh-agent" --env "SSH_AUTH_SOCK=/ssh-agent")
fi

# The container runs as root; give any flake.lock it wrote back to the caller.
reown() {
  docker run --rm --volume "$repo:/work" --entrypoint chown "$image" \
    "$(id -u):$(id -g)" /work/flake.lock /work/01-cloud-edge/flake.lock >/dev/null 2>&1 || true
}
trap reown EXIT

printf '%s' "$script" | docker run "${args[@]}" "$image" \
  nix shell nixpkgs#openssh nixpkgs#bash -c bash -s
