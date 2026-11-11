#!/bin/bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"

if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root: sudo ./install.sh"
    exit 1
fi

echo "==> Plex Server Installer"
echo "    Repo: $REPO_DIR"
echo ""

# --- .env setup ---
if [[ ! -f "$REPO_DIR/.env" ]]; then
    cp "$REPO_DIR/.env.example" "$REPO_DIR/.env"
    echo "Created .env from .env.example."
    echo "Edit $REPO_DIR/.env with your values (webhook URL, Plex token, etc)."
    echo "Then re-run: sudo ./install.sh"
    exit 1
fi

source "$REPO_DIR/.env"

# --- Validate required vars ---
if [[ "${DISCORD_WEBHOOK_URL:-}" == *"CHANGE_ME"* ]] || [[ "${PLEX_TOKEN:-}" == *"CHANGE_ME"* ]]; then
    echo "ERROR: .env still contains CHANGE_ME placeholders."
    echo "Edit $REPO_DIR/.env and re-run."
    exit 1
fi

# --- Prerequisites ---
echo "==> Checking prerequisites..."
for cmd in docker curl; do
    if ! command -v "$cmd" &>/dev/null; then
        echo "ERROR: $cmd is not installed."
        exit 1
    fi
done

if ! docker compose version &>/dev/null; then
    echo "ERROR: docker compose plugin is not installed."
    exit 1
fi

if ! dpkg -s nfs-common &>/dev/null 2>&1; then
    echo "ERROR: nfs-common is not installed. Run: apt install nfs-common"
    exit 1
fi

echo "    docker, curl, docker compose, nfs-common: OK"

# --- Mount points ---
echo "==> Creating mount points..."
mkdir -p /mnt/media /mnt/plex_backup

# --- Scripts ---
echo "==> Setting script permissions..."
chmod +x "$REPO_DIR/bin/"*.sh

# --- fstab NFS entries (idempotent) ---
# fstab is the source of truth for the NFS mounts. systemd auto-generates
# mnt-media.mount / mnt-plex_backup.mount from these lines; _netdev orders
# them after network-online.target.
echo "==> Ensuring NFS entries in /etc/fstab..."
NFS_OPTS="defaults,noatime,rsize=8192,_netdev"
ensure_fstab() {
    local src=$1 mnt=$2
    if grep -qsE "^[^#]*[[:space:]]${mnt}[[:space:]]" /etc/fstab; then
        echo "    $mnt: already in fstab"
    else
        echo "$src $mnt nfs $NFS_OPTS 0 0" >> /etc/fstab
        echo "    $mnt: added to fstab"
    fi
}
ensure_fstab "${NAS_IP}:/volume1/media" /mnt/media
ensure_fstab "${NAS_IP}:/volume1/plex_backup" /mnt/plex_backup

# --- Gate Docker (and Plex) on the NFS mounts ---
echo "==> Installing docker.service NFS wait drop-in..."
mkdir -p /etc/systemd/system/docker.service.d
cp "$REPO_DIR/systemd/docker-wait-nfs.conf" \
    /etc/systemd/system/docker.service.d/wait-nfs.conf

# --- Systemd service units ---
echo "==> Installing systemd service units..."
for unit in plex-backup.service plex-cleanup.service; do
    sed -e "s|__REPO_DIR__|${REPO_DIR}|g" \
        "$REPO_DIR/systemd/$unit" > "/etc/systemd/system/$unit"
done

# --- Systemd timer units ---
echo "==> Installing systemd timer units..."
for unit in plex-backup.timer plex-cleanup.timer; do
    cp "$REPO_DIR/systemd/$unit" "/etc/systemd/system/$unit"
done

# --- Enable everything ---
# daemon-reload regenerates mount units from fstab and picks up the
# docker.service drop-in.
echo "==> Reloading systemd..."
systemctl daemon-reload

echo "==> Mounting NFS shares..."
mount -a

echo "==> Enabling backup timers..."
systemctl enable --now plex-backup.timer plex-cleanup.timer

# --- Docker ---
echo "==> Starting Plex containers..."
cd "$REPO_DIR"
docker compose up -d

echo ""
echo "================================================"
echo "  Installation complete!"
echo "================================================"
echo ""
echo "  NFS mounts:    /mnt/media, /mnt/plex_backup"
echo "  Backup:        22:00 America/Denver every 4th day (keeps ${BACKUP_KEEP:-5})"
echo "  Cleanup:       04:00 every 4th day"
echo "  Plex:          http://$(hostname -I | awk '{print $1}'):32400/web"
echo ""
echo "  Useful commands:"
echo "    systemctl status plex-backup.timer"
echo "    systemctl status plex-cleanup.timer"
echo "    journalctl -u plex-backup.service"
echo "    docker compose -f $REPO_DIR/docker-compose.yaml logs -f plex"
echo ""
