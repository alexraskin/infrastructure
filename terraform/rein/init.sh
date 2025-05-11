#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKEND_CONFIG="$SCRIPT_DIR/config/r2.backend.tfbackend"

if [[ ! -f "$BACKEND_CONFIG" ]]; then
  echo " Backend config not found at $BACKEND_CONFIG"
  exit 1
fi

echo "Initializing Terraform with backend config..."
terraform init -backend-config="$BACKEND_CONFIG"