# apps/ — Flux GitOps

`apps/clusters/k3s/apps.yaml` lists what Flux reconciles; `apps/base/*` holds the
manifests. Secrets are SOPS-encrypted to an age key in `secrets/age.key`
(gitignored, outside `apps/`) and decrypted in-cluster via the `sops-age` secret.
The repo is public — encrypted `*.sops.yaml` is meant to be committed; the age
key is not. `flux bootstrap` pushes commits, so do not run it casually.

Image tags in `apps/base/*/deployment.yaml` are **owned by
image-automation-controller**, not by hand: `apps/base/image-automation/` scans
GHCR, picks the newest semver tag and pushes a commit rewriting the line marked
`# {"$imagepolicy": "flux-system:<app>"}`. Editing a tag manually is undone on
the next 5m scan; pin by narrowing the ImagePolicy range instead. This is why
the GitRepository is SSH with the `flux-git-auth` deploy key (`mise run
git-deploy-key`, needs write access on GitHub) rather than anonymous HTTPS, and
why `install` passes `--components-extra=image-reflector-controller,image-automation-controller`.
Only our own images are automated; `cloudflared` is still pinned by hand.

## Gotchas

- **`mise run sops-encrypt <file>` does not receive its argument** — it fails with
  `bash: line 2: 1: usage: mise run sops-encrypt <file>`, and `--` does not help.
  Same shape in `sops-edit`. Until the tasks are fixed, encrypt with
  `cd apps && mise exec -- sops --encrypt --in-place <file>`; `SOPS_AGE_KEY_FILE`
  is already exported by `apps/mise.toml`, and encryption only needs the public
  key in `.sops.yaml` anyway.
