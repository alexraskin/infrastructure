# apps

GitOps for the k3s cluster. Flux watches this directory in the `infrastructure`
repo and reconciles it; nothing is deployed by hand.

```
clusters/k3s/         what Flux reconciles: the sync config plus the app Kustomizations
base/cloudflared/     the tunnel — the only way traffic enters the cluster
base/alexraskin-com/  the website
base/lastfm-now-playing/  the Last.fm now-playing API
base/image-automation/    scans GHCR and writes new image tags back into base/
.sops.yaml            age recipient; encrypts data/stringData in *.sops.yaml
```

## Secrets

Encrypted with SOPS + age and committed. Flux decrypts them in-cluster with the
`sops-age` secret. The private key lives at `../secrets/age.key`, is gitignored,
and is the only way to read any of it — **back it up**.

```bash
mise run age-key             # generate once, fills the recipient into .sops.yaml
mise run age-key-to-cluster  # hand the private key to Flux
mise run sops-edit base/cloudflared/token.sops.yaml
mise run sops-edit base/lastfm-now-playing/api-key.sops.yaml
```

## Bootstrap

```bash
mise run age-key
mise run age-key-to-cluster

cp base/cloudflared/token.example.yaml base/cloudflared/token.sops.yaml
$EDITOR base/cloudflared/token.sops.yaml          # paste the tunnel token
mise run sops-encrypt base/cloudflared/token.sops.yaml

git add -A && git commit && git push               # Flux reads the remote, not your disk
mise run install
```

No PAT and no `flux bootstrap`, which would commit its own manifests to the repo:
`clusters/k3s/flux-system.yaml` is committed here by hand. The cluster does need
one credential, though — a deploy key, because image automation pushes commits
back. `mise run git-deploy-key` generates it into `../secrets/flux-deploy-key`,
loads it as `flux-git-auth`, and prints the public half; paste that into
**Settings → Deploy keys** on the repo with **Allow write access** ticked.
`mise run install` refuses to continue without the secret, and fails loudly if
the key has not been registered yet.

Then `mise run status` to see what Flux thinks, and `mise run sync` to reconcile
immediately instead of waiting for the 10m interval.

## Image updates

Nothing here pins a tag by hand. `base/image-automation/` gives each app an
ImageRepository (scan GHCR every 5m) and an ImagePolicy (newest semver tag,
`v` optional), and a single ImageUpdateAutomation rewrites the tags in
`base/*/deployment.yaml` and pushes the commit — which Flux then pulls and rolls
out. The line it rewrites is found by its marker, not by position:

```yaml
image: ghcr.io/alexraskin/alexraskin.com:v2.0.1 # {"$imagepolicy": "flux-system:alexraskin-com"}
```

So shipping a release is `git tag v2.0.2 && git push --tags` in the app repo.
GitHub Actions builds and pushes the image, the controllers do the rest; expect
the rollout within ~10 minutes. Editing a tag here by hand is pointless — the
next scan puts the policy's choice back. To hold an app at an older version,
narrow the ImagePolicy range instead.

Two consequences worth knowing:

- The `image-automation` Kustomization is deliberately standalone — no app
  `dependsOn` it. If the extra controllers are missing, only it goes red.
- Commits on `main` now come from `fluxcdbot` as well as from you. Pull before
  you push, or expect rejections.

## Notes

- `ghcr.io/alexraskin/alexraskin.com` and `ghcr.io/alexraskin/lastfm-now-playing`
  are public, so no imagePullSecret.
- lastfm-now-playing takes its key from the `lastfm-api-key` secret as a plain
  env var. The app also accepts a *path* in `LASTFM_API_KEY` (that is how it read
  a docker swarm secret); the k8s form passes the key itself.
- Third-party images (`cloudflared`) are still pinned by hand — image automation
  covers our own images only.
- **Flux syncs from the remote.** Uncommitted or unpushed changes do nothing.
- `dependsOn` makes the website wait for cloudflared — there is no point serving
  something nothing can reach.
