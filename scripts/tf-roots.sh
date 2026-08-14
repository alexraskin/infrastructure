#!/usr/bin/env bash

cat <<'EOF'
00-global
01-cloud-edge/terraform
tailscale
terraform/cloudflare
terraform/oracle
terraform/proxmox
EOF
