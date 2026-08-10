# apps/base/gatus/ — the status page

Gatus (`twin/gatus` chart, pinned) probing this cluster from inside it and
serving the result at **`https://status.<tailnet>.ts.net`**. Tailnet-only by
construction: the Ingress is `ingressClassName: tailscale`, there is no rule in
`terraform/cloudflare/` pointing at it and no Service of type LoadBalancer, so
nothing outside the tailnet can reach it.

The Ingress shape is the same as Grafana's — `hosts: []` and exactly one entry
in `tls.hosts`. The operator takes the device name from `tls.hosts[0]`; a rule
host is not read. MagicDNS and HTTPS Certificates have to be on in the tailnet
admin console or the cert never issues and the Ingress never goes ready
(`apps/base/tailscale-operator/CLAUDE.md`).

## What it probes, and why in that shape

Five groups, and the split between them is the point — which group is red says
where the fault is.

- **Control plane** — `/readyz` on the VIP and on each server's own `:6443`. The
  VIP alone would stay green with two of three servers dead; the per-server
  checks are what show that. `/readyz` answers unauthenticated (k3s grants it to
  `system:public-info-viewer`), so no token is involved; `client.insecure: true`
  is because the serving cert is k3s' own CA.
- **Nodes** — `tcp://<ip>:22`, not `icmp://`. `base.nix` opens 22 on every node,
  and gatus' ICMP probe needs a raw socket the pod does not have: the chart runs
  it as uid 65534 with no `NET_RAW`. Giving it that capability to ping a host
  whose sshd already answers is not worth it.
- **Platform** — CoreDNS (a real DNS query against `10.43.0.10`), Grafana,
  Prometheus, Loki, Alloy, by cluster DNS.
- **Apps** — the in-cluster Services, i.e. the same origins the tunnel dials.
- **Public** — `https://alexraskin.com` end to end, with a cert-expiry
  condition. Red here with its **Apps** twin green means cloudflared, DNS or the
  tunnel, not the workload.

**Public hostnames beyond `alexraskin.com` stay out of this file.** The tunnel's
list lives in `terraform/cloudflare/terraform.tfvars` and the edge's in
`00-cloud-edge/edge.json`, both gitignored on purpose — this repo is public. To
probe them anyway, take the same route `monitoring/` takes for the tailnet name:
put the extra endpoints in a SOPS-encrypted ConfigMap, mount it into `/config`
with `extraVolumeMounts`, and point `GATUS_CONFIG_PATH` at the directory — gatus
merges every file in a config *directory*, which is how a second file can carry
what this one cannot.

## Storage and the strategy

sqlite on a 1Gi `local-path` PVC at `/data/data.db`. local-path is node-local,
so the pod is pinned to whichever node the PVC landed on and the uptime history
is gone if that node is rebuilt — acceptable, the config is in git and the
history is not load-bearing. That pinning is also why `deployment.strategy` is
**`Recreate`**: the chart defaults to `RollingUpdate`, which would start a second
pod that cannot get the ReadWriteOnce volume and sit there until the rollout
times out.

Postgres would remove both problems and is what the upstream example this was
modelled on uses. There is no Postgres in this cluster, and standing one up to
hold a status page's history is the wrong trade.

## Alerting

None configured. Gatus evaluates conditions and shows them on the page; nothing
is paged. Same position as `alertmanager: enabled: false` in `monitoring/` — no
route exists yet. To add one, an `alerting:` block plus `alerts:` on the
endpoints that matter, with the webhook coming from a SOPS secret through `env:`
and referenced as `${VAR}` in the config, never inlined.

## Gotchas

- **The chart's `config` block is the whole gatus config**, rendered verbatim
  into a ConfigMap. A typo is not caught by `kustomize build` or by Flux — the
  pod crashloops on it. `helm template` against the chart is the check.
- **Version pinned by hand.** Image automation only tracks our own GHCR images,
  so both the chart version and the gatus image it implies move deliberately.
