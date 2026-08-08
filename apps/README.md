# apps

GitOps for the k3s cluster. Flux watches this directory in the `infrastructure`
repo and reconciles it; nothing is deployed by hand.

```
clusters/k3s/         what Flux reconciles on this cluster (flux bootstrap adds flux-system/ here)
base/cloudflared/     the tunnel — the only way traffic enters the cluster
base/alexraskin-com/  the website
.sops.yaml            age recipient; encrypts data/stringData in *.sops.yaml
```

## How traffic gets in

There is no ingress controller and no LoadBalancer — traefik and servicelb are
disabled on the cluster. `cloudflared` dials *out* to Cloudflare and forwards to
Services by their in-cluster DNS name, so nothing needs a public IP or an open
port. Routing lives in the Cloudflare dashboard (Zero Trust → Networks →
Tunnels); point the hostname at:

```
http://alexraskin-com.web.svc.cluster.local:80
```

## Secrets

Encrypted with SOPS + age and committed. Flux decrypts them in-cluster with the
`sops-age` secret. The private key lives at `../secrets/age.key`, is gitignored,
and is the only way to read any of it — **back it up**.

```bash
mise run age-key             # generate once, fills the recipient into .sops.yaml
mise run age-key-to-cluster  # hand the private key to Flux
mise run sops-edit base/cloudflared/token.sops.yaml
```

## Bootstrap

```bash
mise run age-key
mise run age-key-to-cluster

cp base/cloudflared/token.example.yaml base/cloudflared/token.sops.yaml
$EDITOR base/cloudflared/token.sops.yaml          # paste the tunnel token
mise run sops-encrypt base/cloudflared/token.sops.yaml

export GITHUB_TOKEN=...                            # PAT with repo scope
mise run bootstrap
```

Then `mise run status` to see what Flux thinks, and `mise run sync` to reconcile
immediately instead of waiting for the 10m interval.

## Notes

- `ghcr.io/alexraskin/alexraskin.com` is public, so no imagePullSecret.
- The image tag is `latest` with `imagePullPolicy: Always`, so a new push is only
  picked up on pod restart. For automatic rollout, either have CI write a digest
  into this repo or enable Flux's image-automation controllers (already installed
  by `mise run bootstrap`).
- `dependsOn` makes the website wait for cloudflared — there is no point serving
  something nothing can reach.
