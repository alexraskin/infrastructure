#!/usr/bin/env bash
set -euo pipefail

: "${PVE_HOST:?}" "${PVE_USER:?}" "${VMID:?}" "${EXPORT_PATH:?}" "${EXPORT_TO:?}"

ssh_opts=(-o BatchMode=yes -o ConnectTimeout=15 -o StrictHostKeyChecking=accept-new)
pve() { ssh "${ssh_opts[@]}" "$PVE_USER@$PVE_HOST" "$@"; }

wait_running() {
  for _ in $(seq 1 30); do
    [ "$(pve "pct status $VMID" 2>/dev/null)" = "status: running" ] && return 0
    sleep 2
  done
  echo "container $VMID never reached running" >&2
  return 1
}

echo "==> waiting for container $VMID to run"
wait_running

echo "==> setting container features (nesting, mount=nfs)"
if pve "pct config $VMID" | grep -q '^features:.*mount=nfs'; then
  echo "    already set"
else
  pve "pct set $VMID --features nesting=1,mount=nfs"
  pve "pct reboot $VMID"
  wait_running
fi

echo "==> waiting for network inside the container"
for _ in $(seq 1 30); do
  pve "pct exec $VMID -- getent hosts deb.debian.org" >/dev/null 2>&1 && break
  sleep 2
done

echo "==> installing nfs-kernel-server"
pve "pct exec $VMID -- bash -eu -c '
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -qq
  apt-get install -y -qq nfs-kernel-server
'"

echo "==> exporting $EXPORT_PATH to $EXPORT_TO"
pve "pct exec $VMID -- bash -eu -c '
  mkdir -p $EXPORT_PATH
  chown nobody:nogroup $EXPORT_PATH
  chmod 0777 $EXPORT_PATH
  echo \"$EXPORT_PATH $EXPORT_TO(rw,sync,no_subtree_check,no_root_squash)\" > /etc/exports
  exportfs -ra
  systemctl enable --now nfs-server
  exportfs -v
'"

echo "==> done"
