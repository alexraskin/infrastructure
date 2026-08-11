# Proxmox VE 8 → 9 upgrade: `bunker`

Runbook for taking the single Proxmox host from PVE 8.4 (Debian 12 Bookworm,
kernel 6.8) to PVE 9 (Debian 13 Trixie, kernel 6.14, QEMU 10). Written against
the host's actual state on 2026-08-10; re-check the facts table before running
it if much time has passed.

Upstream: <https://pve.proxmox.com/wiki/Upgrade_from_8_to_9>

## Why, and what it costs

PVE 8 rides Bookworm, which is leaving general support. Nothing is broken today;
this is a base-OS move to stay supported, and it brings kernel 6.14 and QEMU 10.

It takes **the entire cluster down** for the window — all six k3s VMs, so Flux,
the cloudflared tunnel, `alexraskin.com`, Grafana, Loki and gatus with them.
Unaffected: the Oracle edge (`00-cloud-edge/`), and Plex, which runs on
`morpheus`, not on `bunker`.

## The host as it stands

| | |
|---|---|
| version | `pve-manager/8.4.20`, Debian 12.15, kernel `6.8.12-29-pve` |
| node | `bunker`, standalone — no cluster, no corosync, no Ceph cluster |
| boot | UEFI + GRUB, ESP `9B09-BC24` at `/boot/efi`; `proxmox-boot-tool` **not** in use; `/boot` lives on the root LV |
| storage | LVM only, no ZFS. `pve/root` 96G ext4 (19G used, 71G free), `pve/data` thin 816G at 5%, VG free **16G** |
| network | `enp89s0` → `vmbr0` (VLAN-aware), host `10.0.54.205/24`; the VMs are tagged VLAN 200 |
| guests | 141-143 servers, 151-153 agents, all running, all `onboot: 1`, guest agent answers on all six |
| NFS | `backups` + `iso` from the NAS `10.0.54.235` (27T free) |
| extra | docker installed and enabled but **zero containers**; `ceph-common`/`ceph-fuse` 17.2.7, client libraries only |

`pve8to9 --full` on that state: **34 PASS, 4 WARN, 1 FAIL**. Phase 2 clears each
one; nothing found is a blocker.

## Decisions this plan assumes

- **Physical access to the box during the window.** A NIC rename or a failed
  boot is recoverable at the console, so the interface name is not pinned up
  front — it is pinned afterwards only if it actually moves.
- **Back up all six VMs first**, even though they are reproducible from git.
- **Suppress gatus alerts with a `maintenance:` window** rather than scaling
  gatus down, so the outage is still recorded.

## Phase 0 — repo prep, before touching the host

Add a top-level `maintenance:` block under `config:` in
`apps/base/gatus/helmrelease.yaml`, as a sibling of `storage:` and `alerting:`:

```yaml
    config:
      maintenance:
        start: "HH:MM"      # local start of the window
        duration: 3h
        timezone: America/Phoenix
```

Gatus keeps probing and recording during a maintenance window; it only
suppresses alerts. The block **recurs daily** — it is not a one-shot, which is
why Phase 6 removes it again. Note the same in `apps/base/gatus/CLAUDE.md`.

Commit, push, and confirm Flux applied it — a window that has not reconciled is
not a window:

```bash
flux reconcile kustomization gatus --with-source
kubectl -n gatus get cm -o yaml | grep -A4 maintenance
```

## Phase 1 — backups

The nightly job from `terraform/proxmox/backups.tf` covers these guests, but a
scheduled backup up to 24 hours old is not a pre-upgrade restore point. Take a
fresh one by hand. Snapshot mode, guests stay up (the agent answers on all six):

```bash
ssh root@<pve-host> \
  'vzdump 141 142 143 151 152 153 --storage backups --mode snapshot --compress zstd --notes-template "pre-pve9"'
```

Verify six new `vzdump-qemu-1[45][123]-*.vma.zst` under
`/mnt/pve/backups/dump/`, each `.log` ending in `INFO: Backup job finished
successfully`. Then take the host config off the box as well:

```bash
ssh root@<pve-host> 'tar czf - /etc/pve /etc/network/interfaces /etc/apt' > ~/bunker-etc-pre-pve9.tgz
```

## Phase 2 — clear the `pve8to9` findings, still on PVE 8

```bash
apt update && apt dist-upgrade          # picks up the pending ca-certificates
pveversion                              # must still read 8.4.x
```

1. **FAIL — `systemd-boot` meta-package installed** while the host boots via
   GRUB. On Trixie it fights the other boot packages. Remove it:
   ```bash
   apt remove systemd-boot
   dpkg -l grub-efi-amd64                # must be installed; if not: apt install grub-efi-amd64
   ```
2. **WARN — removable bootloader at `/boot/efi/EFI/BOOT/BOOTX64.efi` is not
   kept up to date by GRUB.** That is the fallback path some firmware actually
   boots:
   ```bash
   echo 'grub-efi-amd64 grub2/force_efi_extra_removable boolean true' | debconf-set-selections -v -u
   apt install --reinstall grub-efi-amd64
   ```
3. **NOTICE — LVM autoactivation** on `local-lvm` guest volumes:
   ```bash
   /usr/share/pve-manager/migrations/pve-lvm-disable-autoactivation
   ```
4. **WARN — `intel-microcode` missing** on this TigerLake host. It needs the
   `non-free-firmware` component, which the Phase 4 sources add — install it
   after the upgrade rather than adding a Bookworm component now.
5. Re-run `pve8to9 --full`. The FAIL should be gone and only the "6 running
   guests" WARN left; Phase 3 clears that.

## Phase 3 — quiesce the cluster

Shut the guests down cleanly so etcd is consistent — agents first, bootstrap
server (141) last:

```bash
for v in 151 152 153 142 143 141; do qm shutdown $v --timeout 180; done
qm list          # all six 'stopped'
```

Cheap rollback insurance, given 16G free in the VG: an LVM snapshot of the root
LV. `/boot` is on that LV, so the pre-upgrade kernel is inside the snapshot.

```bash
lvcreate -s -n root-pre9 -L 12G pve/root
```

Two caveats. The ESP (`/boot/efi`) is a separate vfat partition and is **not**
covered. And if the snapshot fills it is dropped — harmless to the origin, but
the rollback goes with it, so watch `lvs` during the upgrade.

## Phase 4 — repositories, Bookworm → Trixie

The host has four `deb` lines in `/etc/apt/sources.list` plus
`/etc/apt/sources.list.d/docker.list`. Replace with deb822, which is what PVE 9
expects:

```bash
# Debian base. trixie-security moved to security.debian.org/debian-security,
# and non-free-firmware is added here for intel-microcode.
cat > /etc/apt/sources.list.d/debian.sources <<'EOF'
Types: deb
URIs: http://ftp.us.debian.org/debian
Suites: trixie trixie-updates
Components: main contrib non-free-firmware
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg

Types: deb
URIs: http://security.debian.org/debian-security
Suites: trixie-security
Components: main contrib non-free-firmware
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg
EOF

# Proxmox, no-subscription — there is no enterprise key on this host.
cat > /etc/apt/sources.list.d/proxmox.sources <<'EOF'
Types: deb
URIs: http://download.proxmox.com/debian/pve
Suites: trixie
Components: pve-no-subscription
Signed-By: /usr/share/keyrings/proxmox-archive-keyring.gpg
EOF

: > /etc/apt/sources.list
sed -i 's/bookworm/trixie/' /etc/apt/sources.list.d/docker.list
apt update
```

Before going further: `/usr/share/keyrings/proxmox-archive-keyring.gpg` must
exist (`apt install proxmox-archive-keyring` if not), `apt update` must finish
with no errors, `grep -r bookworm /etc/apt/` must come back empty, and
`apt policy` should show the Trixie suites.

`ceph-common`/`ceph-fuse` are the one package pair that might block the
upgrade. No Ceph storage is configured here, so if apt complains the answer is
`apt remove ceph-fuse ceph-common`, not a Ceph repository.

## Phase 5 — the upgrade

```bash
apt dist-upgrade        # 5-60 min; watch for the conffile prompts
```

Conffile answers for this host — nothing under `/etc` is customised, and
`/etc/network/interfaces` is stock PVE and not an apt conffile at all:

| prompt | answer |
|---|---|
| `/etc/issue` | **N** — cosmetic, regenerated |
| `/etc/lvm/lvm.conf` | **Y** — carries PVE-relevant changes |
| `/etc/ssh/sshd_config` | **Y** — drops deprecated auth options |
| `/etc/default/grub` | **N** — unmodified here |
| `/etc/chrony/chrony.conf` | **Y** |
| anything else | keep the default |

Then:

```bash
pve8to9 --full          # expect clean
apt install intel-microcode
reboot                  # required — 6.8 → 6.14
```

**Watch the console through the reboot.** The one failure mode that costs the
host its network is a NIC rename: `enp89s0` is named in
`/etc/network/interfaces` as `vmbr0`'s bridge port, and a 6.14 kernel that
recognises the card differently will rename it. If that happens, `ip -br link`
at the console gives the new name — edit `/etc/network/interfaces`, then
`ifreload -a`. Pin it afterwards with a `/etc/systemd/network/10-nic.link`
matching the NIC's MAC, from `ip -br link` at the console.

## Phase 6 — bring back and verify

The VMs are `onboot: 1` and start on their own; the k3s servers rejoin etcd
regardless of order.

```bash
ssh root@<pve-host> 'pveversion; uname -r; qm list'
```

Expect `pve-manager/9.x`, kernel `6.14.x`, six VMs running. Then from the build
host:

```bash
mise run status                                  # nodes Ready, kube-system healthy
kubectl get nodes -o wide
flux get kustomizations -A                       # all Ready
mise run tf:plan                                 # must be a no-op
```

`tf:plan` earns its place here: the VMs carry no `machine:` line, so QEMU 10
gives them `pc-i440fx-10.0` on this first start. That is a PVE-side change the
Terraform config does not describe — the plan should still come back empty, and
if it does not, that is the thing to understand before applying anything.

Then revert the gatus maintenance window from Phase 0, push, and confirm with
`flux reconcile kustomization gatus --with-source`. Check the status page is
green end to end.

Drop the rollback snapshot once the host has been up long enough to trust it —
a lingering snapshot costs write performance:

```bash
lvremove pve/root-pre9
```

## Rollback

- **Boot fails, or PVE 9 misbehaves** — boot the PVE ISO in rescue mode, or
  merge the snapshot: `lvconvert --merge pve/root-pre9`, then reboot. Root,
  including `/boot` and the 6.8 kernel, returns to its pre-upgrade state. The
  ESP does not; that is the known gap.
- **A guest will not boot under QEMU 10** — pin its machine version back:
  `qm set <vmid> --machine pc-i440fx-9.2`.
- **A guest is unrecoverable** — restore the Phase 1 dump
  (`qmrestore /mnt/pve/backups/dump/vzdump-qemu-<vmid>-*.vma.zst <vmid>`), or
  rebuild it outright with `mise run tf:apply` + `mise run deploy` and let Flux
  restore the workloads. Only node-local PVC data is genuinely lost — the Loki
  WAL, gatus history, the Prometheus TSDB.

## Files this touches

| file | change |
|---|---|
| `apps/base/gatus/helmrelease.yaml` | `config.maintenance` block added, then removed |
| `apps/base/gatus/CLAUDE.md` | short note on the window and that it recurs |

Nothing in `terraform/proxmox/`, `hosts.json` or the NixOS configs changes — a
host upgrade does not touch the guests, and the Phase 6 `tf:plan` is the check
on that claim.
