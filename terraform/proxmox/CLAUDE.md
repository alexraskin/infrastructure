# terraform/proxmox/ — the six cluster VMs

Creates the VMs and nothing inside them. Node identity comes from `hosts.json`
(`jsondecode`) and reaches the guest through the cloud-init drive configured
here; everything after first boot ships via `mise run deploy`, never Terraform.

State is in R2 — see "Terraform state lives in R2" in the root `CLAUDE.md`, and
use `mise run tf:init` rather than a bare `terraform init`.

## Gotchas

- **The Proxmox provider ignores `~/.ssh/config`** and needs either
  `pve_ssh_private_key_path` or a loaded ssh-agent. Missing credentials fail
  *partway* through apply, after the VMs exist.
- **A privsep API token authenticates and then sees nothing** — Proxmox filters
  lists by permission rather than returning 403, so datastores and bridges come
  back as empty arrays. `pveum user token modify <userid> <tokenid> --privsep 0`
  (two separate arguments, not `user!token`).
- `iso` content always uploads over the PVE HTTP API — no SSH, no resume. For a
  slow link use `mise run push-image root@<pve-host>` (rsync, resumable) plus
  `upload_image = false`.
- `disk[0].file_id` is in `lifecycle.ignore_changes`, so rebuilding the image does
  not recreate running VMs. Node changes ship via `deploy`, never Terraform.
