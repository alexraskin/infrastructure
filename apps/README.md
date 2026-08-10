# apps

GitOps for the k3s cluster. Flux watches this directory and reconciles it — this
is the whole inventory of what the cluster runs.

`clusters/k3s/apps.yaml` is the index: one Kustomization per app, each pointing
at a directory under `base/`. Ordering between them is explicit
(`dependsOn`), because some of them genuinely cannot start before another.

## What runs here

| directory | what it is |
| --- | --- |
| `base/cloudflared` | the tunnel — the only way public traffic enters the cluster |
| `base/alexraskin-com` | the website |
| `base/go-vanityurls` | vanity import paths for Go modules |
| `base/lastfm-now-playing` | the Last.fm now-playing API |
| `base/lhbotgo` | the LhCloudy Discord bot |
| `base/monitoring` | kube-prometheus-stack — Prometheus, Alertmanager, Grafana |
| `base/loki` | log storage, chunks in R2 |
| `base/alloy` | the DaemonSet that ships node journals into Loki |
| `base/tailscale-operator` | puts individual Services on the tailnet |
| `base/image-automation` | scans GHCR and writes new image tags back into `base/` |

Apps split into two shapes. The four first-party ones are plain
Deployment + Service + namespace, with their image tag owned by automation.
The rest are HelmReleases against a pinned chart version, with the values block
carrying the interesting decisions — each of those has its own `CLAUDE.md`.

Ordering that matters: everything public depends on `cloudflared`, because a
Service with no tunnel route is unreachable. `monitoring` and `loki` depend on
`tailscale-operator`, because both ask it for a tailnet device and would sit
pending forever without it. `alloy` depends on `loki`, or it just buffers failed
sends. `lhbotgo` depends on nothing — it dials Discord out, nothing dials in.

## Secrets

SOPS + age. Encrypted files are committed on purpose — the repo is public and
`*.sops.yaml` is safe there; `secrets/age.key` at the repo root is not, and is
gitignored. `.sops.yaml` names the age recipient and restricts encryption to
`data` and `stringData`, so `kind`, `metadata` and `namespace` stay readable and
Flux and `kubectl` can still tell what a file is.

Flux decrypts in-cluster with the `sops-age` Secret, which is created once by
hand rather than by Flux — it is the one credential that cannot bootstrap
itself. Each app carrying a secret has a matching `*.example.yaml` showing the
keys without the values.

## Image updates

Nothing here pins a first-party tag by hand. `base/image-automation/` gives each
app an ImageRepository (scan GHCR every 5m) and an ImagePolicy (newest semver
tag, `v` optional), and a single ImageUpdateAutomation rewrites the tags in
`base/*/deployment.yaml` and pushes the commit — which Flux then pulls and rolls
out. The line it rewrites is found by its marker, not by position:

```yaml
image: ghcr.io/alexraskin/alexraskin.com:v2.0.1 # {"$imagepolicy": "flux-system:alexraskin-com"}
```

Editing such a tag by hand is undone on the next scan; narrowing the ImagePolicy
range is how you pin one. This is also why the GitRepository is SSH with a deploy
key rather than anonymous HTTPS — the controller pushes commits.

Third-party charts are the opposite: every HelmRelease pins its chart version
explicitly, because automation only tracks our own GHCR images.

## Working on it

Commands are `mise` tasks in `apps/mise.toml` (`mise trust` once in this
directory). `CLAUDE.md` here covers the reasoning and the known sharp edges;
`base/loki/`, `base/monitoring/`, `base/alloy/` and `base/tailscale-operator/`
each have their own.
