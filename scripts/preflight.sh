#!/usr/bin/env bash
# Check everything Terraform is about to depend on: API token, permissions,
# node, datastores, free VM IDs, free IPs, SSH to the node, room for the VMs,
# and a local talosctl.
#
# Reads terraform/proxmox/terraform.tfvars. Never prints the token.
set -uo pipefail

repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$repo"
tfvars=terraform/proxmox/terraform.tfvars

fail=0
ok()   { printf '  \033[32mok\033[0m    %s\n' "$*"; }
bad()  { printf '  \033[31mFAIL\033[0m  %s\n' "$*"; fail=1; }
warn() { printf '  \033[33mwarn\033[0m  %s\n' "$*"; }

tfvar() { sed -n "s/^$1 *= *\"\\([^\"]*\\)\".*/\\1/p" "$tfvars" | head -1; }

[ -f "$tfvars" ] || { echo "missing $tfvars"; exit 1; }

endpoint=$(tfvar pve_endpoint); endpoint=${endpoint%/}
token=$(tfvar pve_api_token)
node=$(tfvar pve_node)
image_store=$(tfvar image_datastore); image_store=${image_store:-local}
vm_store=$(tfvar vm_datastore); vm_store=${vm_store:-local-lvm}
bridge=$(tfvar network_bridge); bridge=${bridge:-vmbr0}
ssh_user=$(tfvar pve_ssh_username); ssh_user=${ssh_user:-root}
host=${endpoint#*://}; host=${host%%:*}

curl_opts=(-sS --max-time 20 -H "Authorization: PVEAPIToken=$token")
grep -q '^pve_insecure *= *false' "$tfvars" || curl_opts+=(-k)

api() { curl "${curl_opts[@]}" "$endpoint/api2/json$1"; }

echo "Proxmox $endpoint (node $node)"

# --- auth -------------------------------------------------------------------
ver=$(api /version)
if [ -z "$ver" ]; then
  bad "no response from $endpoint — wrong endpoint, DNS, or firewall"
elif echo "$ver" | jq -e '.data.version' >/dev/null 2>&1; then
  ok "API token authenticates (PVE $(echo "$ver" | jq -r '.data.version'))"
else
  bad "API token rejected: $(echo "$ver" | jq -r '.errors // .message // .' 2>/dev/null || echo "$ver")"
fi

# --- privileges -------------------------------------------------------------
perms=$(api /access/permissions)
if echo "$perms" | jq -e '.data' >/dev/null 2>&1; then
  missing=()
  for priv in VM.Allocate VM.Config.Disk VM.Config.Network VM.Config.Options VM.PowerMgmt Datastore.AllocateSpace Datastore.Audit SDN.Use; do
    echo "$perms" | jq -e --arg p "$priv" '[.data[] | select(has($p))] | length > 0' >/dev/null 2>&1 || missing+=("$priv")
  done
  if [ ${#missing[@]} -eq 0 ]; then
    ok "token has the privileges Terraform needs"
  else
    warn "token may be missing: ${missing[*]}"
    warn "  (harmless if the token is privsep 0 on a full-access user)"
  fi
fi

# --- node and datastores ----------------------------------------------------
nodes=$(api /nodes)
if echo "$nodes" | jq -e --arg n "$node" '.data[] | select(.node==$n)' >/dev/null 2>&1; then
  ok "node '$node' exists and is $(echo "$nodes" | jq -r --arg n "$node" '.data[]|select(.node==$n)|.status')"
else
  bad "node '$node' not found — have: $(echo "$nodes" | jq -r '[.data[].node]|join(", ")' 2>/dev/null)"
fi

stores=$(api "/nodes/$node/storage")
check_store() {
  local name=$1 want=$2
  local content
  content=$(echo "$stores" | jq -r --arg s "$name" '.data[]|select(.storage==$s)|.content' 2>/dev/null)
  if [ -z "$content" ]; then
    bad "datastore '$name' not available on $node"
  elif [[ ",$content," == *",$want,"* ]]; then
    ok "datastore '$name' accepts '$want' content"
  else
    bad "datastore '$name' has content=[$content], needs '$want'"
  fi
}
check_store "$image_store" iso
check_store "$vm_store" images

# --- VM IDs -----------------------------------------------------------------
used=$(api /cluster/resources?type=vm | jq -r '.data[]?.vmid' 2>/dev/null)
clash=()
for vmid in $(jq -r '.nodes[].vmid' terraform/proxmox/cluster.auto.tfvars.json); do
  grep -qx "$vmid" <<<"$used" && clash+=("$vmid")
done
if [ ${#clash[@]} -eq 0 ]; then
  ok "VM IDs $(jq -r '[.nodes[].vmid]|join(", ")' terraform/proxmox/cluster.auto.tfvars.json) are free"
else
  bad "VM IDs already in use: ${clash[*]}"
fi

# --- bridge -----------------------------------------------------------------
if api "/nodes/$node/network" | jq -e --arg b "$bridge" '.data[]|select(.iface==$b)' >/dev/null 2>&1; then
  ok "bridge '$bridge' exists on $node"
else
  warn "bridge '$bridge' not found on $node"
fi

# --- SSH to the node --------------------------------------------------------
if ssh -o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new \
     "$ssh_user@$host" true 2>/dev/null; then
  ok "ssh $ssh_user@$host works (the provider shells out for some operations)"
else
  bad "ssh $ssh_user@$host failed — the provider shells out for disk operations"
fi

# --- addresses --------------------------------------------------------------
live=()
for ip in $(jq -r '.cluster.vip, .nodes[].ip' terraform/proxmox/cluster.auto.tfvars.json); do
  ping -c1 -W1 "$ip" >/dev/null 2>&1 && live+=("$ip")
done
if [ ${#live[@]} -eq 0 ]; then
  ok "cluster IPs and VIP are unused"
else
  bad "already answering ping: ${live[*]}"
fi

# --- room for the VMs -------------------------------------------------------
# Nine VMs, three of them with a second disk. Discovering the host is full
# halfway through an apply leaves VMs created and unconfigured.
want_mem=$(jq -r '[.nodes[].memory]|add' terraform/proxmox/cluster.auto.tfvars.json)
want_disk=$(jq -r '[.nodes[] | .disk + (.data_disk // 0)]|add' terraform/proxmox/cluster.auto.tfvars.json)
node_json=$(api "/nodes/$node/status")
max_mem=$(jq -r '.data.memory.total // 0' <<<"$node_json")
free_mem=$(( (max_mem / 1048576) ))
if [ "$free_mem" -gt "$want_mem" ]; then
  ok "host has ${free_mem}MB RAM, VMs ask for ${want_mem}MB"
else
  warn "VMs ask for ${want_mem}MB RAM, host has ${free_mem}MB total"
fi

avail=$(api "/nodes/$node/storage/$vm_store/status" | jq -r '.data.avail // 0')
avail_gb=$(( avail / 1073741824 ))
if [ "$avail_gb" -gt "$want_disk" ]; then
  ok "$vm_store has ${avail_gb}GB free, VM disks ask for ${want_disk}GB"
else
  warn "VM disks ask for ${want_disk}GB, $vm_store has ${avail_gb}GB free (thin pools may still cope)"
fi

# --- talosctl ---------------------------------------------------------------
if command -v talosctl >/dev/null 2>&1; then
  ok "talosctl $(talosctl version --client --short 2>/dev/null | head -1)"
else
  bad "no talosctl — 'mise install' provides it"
fi

echo
[ $fail -eq 0 ] && echo "preflight passed" || echo "preflight found problems"
exit $fail
