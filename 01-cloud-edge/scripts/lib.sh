#!/usr/bin/env bash
# Sourced by the edge scripts: paths, the edge.json guard, and the SSH options
# every one of them uses.

edge=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
repo=$(cd "$edge/.." && pwd)

ssh_opts=(-o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=/dev/null)

require_edge_json() {
  [ -s "$edge/edge.json" ] || {
    echo "missing 01-cloud-edge/edge.json — copy edge.json.example" >&2
    exit 1
  }
}

edge_host() {
  require_edge_json
  jq -r '.instance.hostname' "$edge/edge.json"
}

edge_addr() {
  "$edge/scripts/edge-addr.sh" "${1:-}"
}

edge_ssh() {
  local ip=$1
  shift
  ssh "${ssh_opts[@]}" "root@$ip" "$@"
}
