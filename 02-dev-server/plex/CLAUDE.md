# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Bash + systemd + Docker Compose deployment for a Plex Media Server on a Debian/Ubuntu host. No build step, no test suite — it's shell scripts and unit files. Changes are validated by running the scripts or inspecting systemd state on the host.

## Deploy / operate

```bash
sudo ./install.sh                       # idempotent installer (see flow below)
sudo systemctl start plex-backup.service # manual backup now
sudo ./bin/restore_plex_backup.sh        # interactive restore (or pass a .tar.gz path)
docker compose up -d                     # bring up plex + exporter
systemctl list-timers plex-*             # check schedule
tail -f /mnt/plex_backup/backup.log      # backup/cleanup logs live on the NFS share
```

`install.sh` must run as root. First run copies `.env.example` → `.env` and exits; fill in `.env`, then re-run. It refuses to proceed while `CHANGE_ME` placeholders remain.

## Architecture

Three layers, wired together by `install.sh`:

1. **Docker Compose** (`docker-compose.yaml`) — `plex` (host networking, `/dev/dri` for HW transcode, config bind-mounted from `PLEX_DATA_PATH` on host, media bind-mounted read-only from `/mnt/media`) + a Prometheus exporter on port 9001.
2. **systemd units** (`systemd/`) — `.service`/`.timer` pairs for backup and cleanup (templated with `__REPO_DIR__`, substituted via `sed`), plus `docker-wait-nfs.conf`, a `docker.service` drop-in that `install.sh` copies to `/etc/systemd/system/docker.service.d/` so Docker/Plex won't start before the NFS mounts are live.
3. **Scripts** (`bin/`) — the actual backup/cleanup/restore logic, invoked by the services.

### NFS mounts

`/etc/fstab` is the source of truth for the two NFS shares (`/mnt/media`, `/mnt/plex_backup`). `install.sh` ensures both lines idempotently using `NAS_IP` from `.env`. systemd auto-generates the `mnt-media.mount` / `mnt-plex_backup.mount` units from fstab — those generated unit names are what the backup/cleanup services `Requires=`. The `_netdev` option orders the mounts after `network-online.target`. There are no hand-written `.mount` units.

`install.sh` is the source of truth: it templates units into `/etc/systemd/system/`, `daemon-reload`s, enables mounts + timers, and runs `docker compose up -d`. Editing a unit in `systemd/` does **not** take effect until copied to `/etc/systemd/system/` and reloaded — the live system can drift from the repo. Always re-apply changes:

```bash
sudo cp systemd/<unit> /etc/systemd/system/<unit>   # or re-run install.sh
sudo systemctl daemon-reload
```

### Backup flow (`bin/plex_backup.sh`)

Verifies `BACKUP_DIR` is a live mountpoint → `docker stop plex` → `tar cz --exclude=Cache` of `Plex Media Server` dir → `docker start plex`. An `EXIT` trap guarantees Plex restarts even on failure. Backups named `buplex-<date>.tar.gz`.

### Cleanup (`bin/cleanup_plex_backups.sh`)

Lexically sorts `buplex-*.tar.gz`, deletes all but the newest `BACKUP_KEEP` (default 5). Relies on the date-format filename sorting chronologically.

### Shared lib (`bin/lib/common.sh`)

Sourced by every script. Loads `.env`, applies env-var defaults, and provides `log_msg`, `send_discord` (webhook is a no-op if `DISCORD_WEBHOOK_URL` unset), and `require_root`. New scripts should source this rather than re-implement config loading or notifications.

## Config

All runtime config is in `.env` (gitignored; see `.env.example`). Both the scripts (via `common.sh`) and the systemd services (via `EnvironmentFile=`) read it. Key vars: `NAS_IP`, `PLEX_DATA_PATH`, `BACKUP_DIR`, `BACKUP_KEEP`, `DISCORD_WEBHOOK_URL`, `PLEX_TOKEN`.

## Schedule

Backup and cleanup run on systemd timers (`OnCalendar`, `Persistent=true`) — cleanup offset one hour after backup so it follows each run. Change cadence by editing both `systemd/plex-backup.timer` and `systemd/plex-cleanup.timer`, then re-applying (see above).
