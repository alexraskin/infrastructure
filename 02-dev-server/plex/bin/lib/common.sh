#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[1]}")" && pwd)"
if [[ -f "$SCRIPT_DIR/../.env" ]]; then
    source "$SCRIPT_DIR/../.env"
fi

BACKUP_DIR="${BACKUP_DIR:-/mnt/plex_backup}"
PLEX_CONTAINER="${PLEX_CONTAINER:-plex}"
PLEX_DATA_PATH="${PLEX_DATA_PATH:-/var/lib/plexmediaserver}"
DISCORD_WEBHOOK_URL="${DISCORD_WEBHOOK_URL:-}"

log_msg() {
    echo "$(date '+%Y-%b-%d at %H:%M:%S') :: $1" | tee -a "$LOG_FILE"
}

send_discord() {
    [[ -z "$DISCORD_WEBHOOK_URL" ]] && return 0
    local title=$1
    local message=$2
    local color=$3
    curl -s -X POST "$DISCORD_WEBHOOK_URL" \
        -H "Content-Type: application/json" \
        -d "{
            \"embeds\": [{
                \"title\": \"$title\",
                \"description\": \"$message\",
                \"color\": $color,
                \"timestamp\": \"$(date -u +%Y-%m-%dT%H:%M:%S.000Z)\",
                \"footer\": {
                    \"text\": \"$(hostname)\"
                }
            }]
        }" >> "${LOG_FILE:-/dev/null}" 2>&1 || true
}

require_root() {
    if [[ $EUID -ne 0 ]]; then
        echo "$(basename "$0") requires root privileges."
        echo "sudo $0 $*"
        exit 1
    fi
}
