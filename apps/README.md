# apps

GitOps for the k3s cluster. Flux watches this directory in the `infrastructure`
repo and reconciles it; nothing is deployed by hand.

```
clusters/k3s/         what Flux reconciles: the sync config plus the app Kustomizations
base/cloudflared/     the tunnel — the only way traffic enters the cluster
base/alexraskin-com/  the website
base/lastfm-now-playing/  the Last.fm now-playing API
.sops.yaml            age recipient; encrypts data/stringData in *.sops.yaml
```

## How traffic gets in

There is no ingress controller and no LoadBalancer — traefik and servicelb are
disabled on the cluster. `cloudflared` dials *out* to Cloudflare and forwards to
Services by their in-cluster DNS name, so nothing needs a public IP or an open
port. Routing lives in the Cloudflare dashboard (Zero Trust → Networks →
Tunnels); point the hostname at:

```
alexraskin.com                             -> http://alexraskin-com.web.svc.cluster.local:80
lastfm.alexraskin.com, lastfm.twizy.sh     -> http://lastfm-now-playing.lastfm.svc.cluster.local:80
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

No GitHub token needed: `flux bootstrap` would require a PAT with write access to
commit its own manifests and add a deploy key. Instead `clusters/k3s/flux-system.yaml`
is committed here by hand, and because the repo is public Flux reads it over
anonymous HTTPS. The cluster never pushes to GitHub, so it needs no write
credentials at all.

Then `mise run status` to see what Flux thinks, and `mise run sync` to reconcile
immediately instead of waiting for the 10m interval.

## Notes

- `ghcr.io/alexraskin/alexraskin.com` and `ghcr.io/alexraskin/lastfm-now-playing`
  are public, so no imagePullSecret.
- lastfm-now-playing takes its key from the `lastfm-api-key` secret as a plain
  env var. The app also accepts a *path* in `LASTFM_API_KEY` (that is how it read
  a docker swarm secret); the k8s form passes the key itself.
- The image tag is `latest` with `imagePullPolicy: Always`, so a new push is only
  picked up on pod restart — `kubectl -n web rollout restart deploy/alexraskin-com`.
  Automating that means Flux writing back to git, which *does* need a token; having
  CI commit an image digest here is the alternative.
- **Flux syncs from the remote.** Uncommitted or unpushed changes do nothing.
- `dependsOn` makes the website wait for cloudflared — there is no point serving
  something nothing can reach.
