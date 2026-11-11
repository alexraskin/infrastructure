# Plex Server

Everything needed to run and maintain a Plex Media Server on a fresh Debian/Ubuntu box with Docker.

## What's Included

| Component | Purpose |
|---|---|
| `docker-compose.yaml` | Plex container + Prometheus exporter |
| `bin/plex_backup.sh` | Stops Plex, tars config (excluding cache) to NFS, restarts Plex |
| `bin/cleanup_plex_backups.sh` | Rotates backups, keeps the latest N |
| `bin/restore_plex_backup.sh` | Interactive restore from any backup |
| `systemd/plex-backup.*` | Timer + service for 03:00 backup, every 4th day |
| `systemd/plex-cleanup.*` | Timer + service for 04:00 cleanup, every 4th day |

Discord webhook notifications on every backup/cleanup success or failure.

## Prerequisites

- Docker + Docker Compose plugin
- NFS shares accessible from the host (Tailscale or local network)
- `curl` (for Discord webhooks)

## Quick Start

```bash
git clone <your-repo-url> ~/plex-stuff
cd ~/plex-stuff

# First run creates .env from the template and exits so you can fill it in
sudo ./install.sh

# Edit .env with your actual values
nano .env

# Run again to deploy everything
sudo ./install.sh
```

The installer will:
1. Add the NFS shares (`/mnt/media`, `/mnt/plex_backup`) to `/etc/fstab`
2. Deploy backup + cleanup timers to systemd
3. Start the Plex container via Docker Compose

## Configuration

All config lives in `.env` (created from `.env.example` on first run):

| Variable | Description | Default |
|---|---|---|
| `DISCORD_WEBHOOK_URL` | Discord webhook for notifications | — |
| `NAS_IP` | Tailscale/LAN IP of your NAS | `100.109.167.97` |
| `PLEX_CONTAINER` | Docker container name | `plex` |
| `PLEX_DATA_PATH` | Host path to Plex config data | `/var/lib/plexmediaserver` |
| `BACKUP_DIR` | Where backups are written (NFS mount) | `/mnt/plex_backup` |
| `BACKUP_KEEP` | Number of backups to retain | `5` |
| `PLEX_SERVER` | Plex URL for Prometheus exporter | `http://localhost:32400` |
| `PLEX_TOKEN` | Plex auth token for Prometheus exporter | — |

## Restoring from Backup

```bash
# Interactive — lists available backups and lets you pick one
sudo ./bin/restore_plex_backup.sh

# Or pass a specific backup file directly
sudo ./bin/restore_plex_backup.sh /mnt/plex_backup/buplex-2026-03(Mar)-14_3hr_00min.tar.gz
```

## Useful Commands

```bash
# Check timer status
systemctl list-timers plex-*

# View backup logs
tail -f /mnt/plex_backup/backup.log
tail -f /mnt/plex_backup/cleanup.log

# Trigger a manual backup
sudo systemctl start plex-backup.service

# Check NFS mounts
systemctl status mnt-media.mount mnt-plex_backup.mount

# Plex container logs
docker compose logs -f plex
```
