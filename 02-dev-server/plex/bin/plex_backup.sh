#!/bin/bash
set -e

source "$(cd "$(dirname "$0")" && pwd)/lib/common.sh"

LOG_FILE="$BACKUP_DIR/backup.log"

require_root "$@"

cleanup() {
    if ! docker inspect -f '{{.State.Running}}' "$PLEX_CONTAINER" 2>/dev/null | grep -q true; then
        log_msg "Ensuring Plex container is running..."
        docker start "$PLEX_CONTAINER" >> "$LOG_FILE" 2>&1 || true
    fi
}
trap cleanup EXIT

handle_error() {
    log_msg "ERROR: $1"
    send_discord "Plex Backup Failed" "$1" 15548997
    exit 1
}

if ! mountpoint -q "$BACKUP_DIR"; then
    handle_error "NFS share not mounted at $BACKUP_DIR"
fi

log_msg "Starting Backup."

log_msg "Stopping Plex container."
docker stop "$PLEX_CONTAINER" >> "$LOG_FILE" 2>&1 || handle_error "Failed to stop Plex container"

cd "$PLEX_DATA_PATH/Library/Application Support/Plex Media Server" || handle_error "Failed to access Plex directory"
backupFile="$BACKUP_DIR/buplex-$(date '+%Y-%m(%b)-%d_%Hhr_%Mmin').tar.gz"
tar cz --exclude='Cache' -f "$backupFile" . >> "$LOG_FILE" 2>&1 || handle_error "Tar backup failed"

backupSize=$(du -h "$backupFile" | cut -f1)

log_msg "Starting Plex container."
docker start "$PLEX_CONTAINER" >> "$LOG_FILE" 2>&1 || handle_error "Failed to start Plex container"

log_msg "Backup Completed."
send_discord "Plex Backup Success" "Backup completed successfully\\nSize: $backupSize" 5763719
