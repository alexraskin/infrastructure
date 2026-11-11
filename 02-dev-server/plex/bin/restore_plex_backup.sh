#!/bin/bash
set -e

source "$(cd "$(dirname "$0")" && pwd)/lib/common.sh"

restoreTarget="$PLEX_DATA_PATH/Library/Application Support/Plex Media Server"

require_root "$@"

backups=()
while IFS= read -r f; do
    backups+=("$f")
done < <(ls -1t "$BACKUP_DIR"/buplex-*.tar.gz 2>/dev/null)

if [[ ${#backups[@]} -eq 0 ]]; then
    echo "No backups found in $BACKUP_DIR"
    exit 1
fi

if [[ -n "$1" ]]; then
    backupFile="$1"
    if [[ ! -f "$backupFile" ]]; then
        backupFile="$BACKUP_DIR/$1"
    fi
    if [[ ! -f "$backupFile" ]]; then
        echo "ERROR: Backup file not found: $1"
        exit 1
    fi
else
    echo ""
    echo "Available backups (newest first):"
    echo ""
    for i in "${!backups[@]}"; do
        size=$(du -h "${backups[$i]}" | cut -f1)
        name=$(basename "${backups[$i]}")
        printf "  [%d] %s (%s)\n" "$((i + 1))" "$name" "$size"
    done
    echo ""
    read -rp "Select backup to restore [1]: " choice
    choice="${choice:-1}"

    if ! [[ "$choice" =~ ^[0-9]+$ ]] || [[ "$choice" -lt 1 ]] || [[ "$choice" -gt ${#backups[@]} ]]; then
        echo "Invalid selection."
        exit 1
    fi

    backupFile="${backups[$((choice - 1))]}"
fi

backupName=$(basename "$backupFile")
backupSize=$(du -h "$backupFile" | cut -f1)

echo ""
echo "  Backup:  $backupName ($backupSize)"
echo "  Target:  $restoreTarget"
echo ""
echo "  WARNING: This will stop Plex and overwrite all server data"
echo "           (libraries, preferences, watch history, etc)."
echo ""
read -rp "Continue? [y/N]: " confirm
if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 0
fi

echo ""
echo "==> Stopping Plex container..."
docker stop "$PLEX_CONTAINER" 2>&1 || true

echo "==> Clearing existing data (preserving Cache)..."
find "$restoreTarget" -mindepth 1 -maxdepth 1 ! -name 'Cache' -exec rm -rf {} +

echo "==> Extracting $backupName..."
tar xzf "$backupFile" -C "$restoreTarget"

echo "==> Starting Plex container..."
docker start "$PLEX_CONTAINER"

echo ""
echo "Restore complete. Plex is starting up."
send_discord "Plex Restore Success" "Restored from $backupName ($backupSize)" 5763719
