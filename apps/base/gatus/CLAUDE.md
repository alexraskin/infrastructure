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
  checks are what show that. `client.insecure: true` is because the serving cert
  is k3s' own CA. These probes carry a bearer token — see below.
- **Nodes** — `tcp://<ip>:22`, not `icmp://`. `base.nix` opens 22 on every node,
  and gatus' ICMP probe needs a raw socket the pod does not have: the chart runs
  it as uid 65534 with no `NET_RAW`. Giving it that capability to ping a host
  whose sshd already answers is not worth it.
- **Platform** — CoreDNS (a real DNS query against `10.43.0.10`), Grafana,
  Prometheus, Loki, Alloy, by cluster DNS.
- **Apps** — the in-cluster Services, i.e. the same origins the tunnel dials.
- **Off-cluster** — the Oracle edge (`100.79.150.123`) and the NAS, *chronos*
  (`100.109.167.97`), both over the tailnet on `tcp:443`; and Plex on *morpheus*
  over the LAN. See below; the first two are not reachable without a grant in
  `tailscale/policy.hujson`.
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

## The apiserver token

**k3s runs the apiserver with anonymous auth off**, so an unauthenticated
`/readyz` is a 401 with a `Status` body, not `ok` — the first version of this
config had no token and every control-plane check failed on exactly that. Any
*authenticated* caller gets `ok`, through the default `system:public-info-viewer`
ClusterRoleBinding, so `gatus-probe` needs **no Role or ClusterRole of its own**;
being a ServiceAccount is the whole qualification.

`serviceaccount.yaml` also creates a `kubernetes.io/service-account-token`
Secret. That is the long-lived, non-projected kind on purpose: gatus takes a
bearer token only through `${ENV_VAR}` substitution in a header, and a projected
token is a file it cannot read. Nothing secret is committed — the token
controller fills the Secret in, and the `HelmRelease` reaches it with a
`secretKeyRef`. The 1-year cleanup of *unused* legacy tokens does not apply; this
one is used every 30s.

Kept as a bearer token rather than dropping the conditions to `[STATUS] == 401`:
a 401 proves only that something is listening and terminating TLS. `ok` from
`/readyz` is the actual readiness signal, which is the point of the group.

## Reaching the edge and the NAS

Both are probed **over the tailnet, by IP, with a TCP check** — three
constraints stacked, none of them arbitrary.

- **Tailnet, not LAN.** The NAS' LAN address `10.0.54.235` is on a different
  subnet from the cluster's `10.0.200.0/24` and nothing on 22/80/443/5000/5001
  answers from either a node or the build host, only the tailscale UDP endpoint
  does — it is firewalled off at the router, which no change in this repo fixes.
  Its tailnet address answers on 80/443/5000/5001. The edge has no LAN address
  at all.
- **TCP, not ICMP.** Same reason as the Nodes group: the pod has no `NET_RAW`.
- **The tailnet ACL has to grant it.** `policy.hujson` is default-deny
  (`acls: []`, everything through `grants`) and `tag:k3s` was the src of no
  grant at all — the cluster nodes could reach nothing on the tailnet. Two
  grants now cover exactly these two probes, `tag:k3s → tag:edge:443` and
  `tag:k3s → 100.109.167.97:443`, and the `tests` block pins both the accepts
  and what stays denied (`tag:edge:22`, the NAS' `:5001`, Plex, the VIP).
  **`tag:k3s` is the right src, not `tag:k8s`**: the gatus pod is not one of the
  operator's tailnet proxies, its egress leaves through a node and tailscale
  SNATs it to that node's tailnet address.

Until that policy is applied the edge and NAS checks are red, and red for a
reason that has nothing to do with either box being down.

**Plex is the exception: it is probed over the LAN**, `http://10.0.200.87:32400/identity`
on *morpheus*, which is on the cluster's own subnet and answers unauthenticated
with an XML `MediaContainer` — a real health signal, unlike a TCP connect. No
grant is involved, and the ACL's `tag:k3s → 100.73.219.120:32400` deny is
deliberately left in place. The cost is that `10.0.200.87` is a **DHCP lease**:
if it moves, this check goes red and the address here has to follow. Switching
it to the tailnet address instead means adding a grant *and* flipping that line
in the policy's `tests` from deny to accept — the same two-line edit the edge
and NAS got.

The public path to Plex (`plex.relay.alexraskin.com` → the edge → morpheus) is
not probed. Those hostnames live in the gitignored `00-cloud-edge/edge.json` for
the same reason the tunnel's do; the `edge-1:443` check covers the hop that is
actually in this repo's control.

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
