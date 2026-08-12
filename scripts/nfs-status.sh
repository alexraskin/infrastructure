#!/usr/bin/env bash
#
# What the NFS LXC is exporting, how full it is, and whether the StorageClass
# still points at the same place. Reaches the container through the PVE host,
# whose address is the one part of this that is not in cluster.auto.tfvars.json.
set -euo pipefail

repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$repo"

cfg=terraform/proxmox/cluster.auto.tfvars.json
ip=$(jq -r '.nfs.ip' "$cfg")
share=$(jq -r '.nfs.export_path' "$cfg")
vmid=$(jq -r '.nfs.vmid' "$cfg")
host=$(sed -n 's|^pve_endpoint *= *"https*://\([^:/]*\).*|\1|p' terraform/proxmox/terraform.tfvars | head -1)

[ -n "$host" ] || {
  echo "could not read pve_endpoint out of terraform/proxmox/terraform.tfvars" >&2
  exit 1
}

echo "== export ($ip:$share, vmid $vmid)"
ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new "root@$host" \
  "pct exec $vmid -- sh -c 'exportfs -v; df -h $share | tail -1'"

echo
echo "== StorageClass"
kubectl get sc nfs -o jsonpath='{.parameters.server}:{.parameters.share}{"\n"}'
echo "   expected $ip:$share"
