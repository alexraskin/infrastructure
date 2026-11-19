# infrastructure

My AWS account and my homelab, as code.

- **AWS** (`00-global/`): CI roles over GitHub OIDC, SSM secrets, IAM Identity
  Center, and the `alexraskin.com` domain on Route 53.
- **Homelab** (`terraform/proxmox/`, `apps/`): an HA Talos Kubernetes cluster on
  one Proxmox host, deployed by Flux.
- **Edge** (`01-cloud-edge/`): a NixOS box on Oracle Cloud that fronts public
  traffic over Tailscale, so nothing at home is exposed.

Everything runs through `mise`. Terraform state lives in S3, and secrets are
either SOPS-encrypted or in SSM. The repo is public, but it isn't a template:
the addresses and IDs in it are mine.

Layout and setup are in [CLAUDE.md](CLAUDE.md).
