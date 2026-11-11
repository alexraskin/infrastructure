#!/bin/bash
set -e

source "$(cd "$(dirname "$0")" && pwd)/lib/common.sh"

LOG_FILE="$BACKUP_DIR/cleanup.log"
keep="${BACKUP_KEEP:-5}"

if [ ! -d "$BACKUP_DIR" ]; then
    log_msg "ERROR: Backup directory $BACKUP_DIR does not exist!"
    send_discord "Plex Cleanup Failed" "Backup directory does not exist" 15548997
    exit 1
fi

totalBackups=$(ls -1 "$BACKUP_DIR"/buplex-*.tar.gz 2>/dev/null | wc -l)

filesToDelete=$(ls "$BACKUP_DIR"/buplex-*.tar.gz 2>/dev/null | sort | head -n -"$keep")

if [ -n "$filesToDelete" ]; then
    deletedCount=$(echo "$filesToDelete" | grep -c '\S')
    while IFS= read -r f; do
        rm "$f"
    done <<< "$filesToDelete"
    log_msg "Deleted $deletedCount old backup(s). Kept latest $keep backups."
    send_discord "Plex Cleanup Success" "Deleted $deletedCount old backup(s)\\nTotal backups: $totalBackups → $keep" 5763719
else
    log_msg "No cleanup needed. Total backups: $totalBackups"
    send_discord "Plex Cleanup Success" "No cleanup needed\\nTotal backups: $totalBackups" 5763719
fi
