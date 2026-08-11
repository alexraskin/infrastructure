#!/usr/bin/env bash

set -euo pipefail

repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
script=${1:?usage: nix.sh <shell script>}


export NIX_CONFIG="experimental-features = nix-command flakes
system-features = kvm nixos-test benchmark big-parallel uid-range"

# 00-cloud-edge/ is the only flake left in this repo — the cluster is Talos and
# owns no Nix. Flakes evaluate from the git tree, so an untracked file there is
# invisible to the build and the failure is confusing.
untracked=$(git -C "$repo" ls-files --others --exclude-standard -- \
  00-cloud-edge || true)
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

# The container runs as root but the repo is owned by the invoking user, and git
# refuses to read a repo it does not own — "repository path '/work' is not owned
# by current user". Nix evaluates flakes through libgit2, which only honours this
# from a config file, not GIT_CONFIG_* environment variables.
gitconfig=${XDG_CACHE_HOME:-$HOME/.cache}/nix-container-gitconfig
if [ ! -f "$gitconfig" ]; then
  mkdir -p "$(dirname "$gitconfig")"
  printf '[safe]\n\tdirectory = /work\n' > "$gitconfig"
fi
args+=(--volume "$gitconfig:/root/.gitconfig:ro")

if [ -e /dev/kvm ]; then
  args+=(--device /dev/kvm)
fi

# Forward the SSH agent when there is one, so passphrase-protected keys work.
if [ -n "${SSH_AUTH_SOCK:-}" ] && [ -S "${SSH_AUTH_SOCK}" ]; then
  args+=(--volume "$SSH_AUTH_SOCK:/ssh-agent" --env "SSH_AUTH_SOCK=/ssh-agent")
fi

# The container is root; anything it writes back (flake.lock) would land in the
# repo owned by root. Hand it back on the way out, success or not. Named
# explicitly rather than chown -R: the repo also holds media and service data.
reown() {
  # Every lockfile a flake in this repo might write. 00-cloud-edge/ is a
  # second, self-contained flake (see its README) and nix writes its lock as
  # root too — the symptom otherwise is a `git add` that fails on a file the
  # invoking user cannot touch.
  docker run --rm --volume "$repo:/work" --entrypoint chown "$image" \
    "$(id -u):$(id -g)" /work/flake.lock /work/00-cloud-edge/flake.lock >/dev/null 2>&1 || true
}
trap reown EXIT

printf '%s' "$script" | docker run "${args[@]}" "$image" \
  nix shell nixpkgs#openssh nixpkgs#bash -c bash -s
