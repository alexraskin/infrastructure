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


# Wait until no one is watching Plex, up to 2 hours, so the stop does not
# interrupt a viewer in another timezone. Polls the local Plex sessions API
# every 5 minutes. Uses PLEX_TOKEN from .env when set, otherwise reads the
# token from Plex Preferences.xml. The token is never printed. If the check
# cannot run, the backup proceeds rather than being skipped.
wait_for_plex_idle() {
    local token="$PLEX_TOKEN"
    local prefs="$PLEX_DATA_PATH/Library/Application Support/Plex Media Server/Preferences.xml"
    local sessions=""
    local waited=0
    local max_wait=120

    if [[ -z "$token" && -f "$prefs" ]]; then
        token=$(sed -n 's/.*PlexOnlineToken="\([^"]*\)".*/\1/p' "$prefs" | head -1)
    fi

    if [[ -z "$token" ]]; then
        log_msg "WARNING: No Plex token available. Continuing backup without session check."
        return 0
    fi

    while true; do
        sessions=$(curl -s -m 10 "${PLEX_SERVER}/status/sessions?X-Plex-Token=${token}" 2>/dev/null | sed -n 's/.*<MediaContainer[^>]* size="\([0-9][0-9]*\)".*/\1/p' | head -1)
        if [[ -z "$sessions" ]]; then
            log_msg "WARNING: Plex sessions check failed. Continuing backup."
            return 0
        fi
        if [[ "$sessions" == "0" ]]; then
            log_msg "No active Plex sessions. Continuing backup."
            return 0
        fi
        if [[ $waited -ge $max_wait ]]; then
            log_msg "Plex still in use after ${max_wait} minutes ($sessions session(s)). Continuing backup anyway."
            return 0
        fi
        log_msg "Plex in use ($sessions active session(s)). Waiting 5 minutes."
        sleep 300
        waited=$((waited + 5))
    done
}

wait_for_plex_idle

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
