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
  VIP alone would stay green with two of three control plane nodes dead; the
  per-node checks are what show that. `client.insecure: true` is because the
  serving cert is the cluster's own CA. These probes carry a bearer token — see below.
- **Nodes** — `tcp://<ip>:50000`, the Talos API, not `icmp://` and no longer
  `:22`: Talos runs no sshd at all. gatus' ICMP probe needs a raw socket the pod
  does not have — the chart runs it as uid 65534 with no `NET_RAW` — and a node
  whose apid answers is a node that is up.
- **Platform** — CoreDNS (a real DNS query against `10.96.0.10`; Talos' service
  CIDR is `10.96.0.0/12`, where k3s used `10.43.0.0/16`), Grafana,
  Prometheus, Loki, Alloy, by cluster DNS.
- **Apps** — the in-cluster Services, i.e. the same origins the tunnel dials.
- **Off-cluster** — the Oracle edge (`100.79.150.123`) and the NAS, *chronos*
  (`100.109.167.97`), both over the tailnet on `tcp:443`; and Plex on *morpheus*
  over the LAN. The two tailnet ones are dialled through **egress proxies**
  (`egress.yaml`), not at their tailnet addresses: the Talos nodes do not run
  tailscaled, so there is no node to SNAT pod egress onto the tailnet the way
  there was under NixOS. Each is an ExternalName Service annotated
  `tailscale.com/tailnet-ip`, which the operator turns into a proxy with its own
  device — so the ACL grant is `src: tag:k8s`, not the old `tag:k3s`.
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

**The apiserver runs with anonymous auth off**, so an unauthenticated
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
- **Each one needs an egress proxy**, declared in `egress.yaml`. The probe
  targets a ClusterIP inside the cluster; the operator carries it onto the
  tailnet from a proxy pod with its own device. Deleting the Service breaks the
  probe, not the ACL.
- **The tailnet ACL has to grant it.** `policy.hujson` is default-deny
  (`acls: []`, everything through `grants`). Two grants cover exactly these two
  probes, `tag:k8s → tag:cloud-edge:443` and `tag:k8s → 100.109.167.97:443`,
  and the `tests` block pins both the accepts and what stays denied
  (`tag:cloud-edge:22`, the NAS' `:5001`, Plex, the VIP).
  **`tag:k8s` is the src because the proxies are the ones dialling.** Under k3s
  it was `tag:k3s` — pod egress left through a node and was SNAT'd to that
  node's tailnet address. Talos nodes are not on the tailnet, so that path does
  not exist and the tag went with it.

Until that policy is applied the edge and NAS checks are red, and red for a
reason that has nothing to do with either box being down.

**Plex is the exception: it is probed over the LAN**, `http://10.0.200.87:32400/identity`
on *morpheus*, which is on the cluster's own subnet and answers unauthenticated
with an XML `MediaContainer` — a real health signal, unlike a TCP connect. No
grant is involved, and the ACL's `tag:k8s → 100.73.219.120:32400` deny is
deliberately left in place. The cost is that `10.0.200.87` is a **DHCP lease**:
if it moves, this check goes red and the address here has to follow. Switching
it to the tailnet address instead means adding a grant *and* flipping that line
in the policy's `tests` from deny to accept — the same two-line edit the edge
and NAS got.

The public path to Plex (`plex.relay.alexraskin.com` → the edge → morpheus) is
not probed. Those hostnames live in the gitignored `00-cloud-edge/edge.json` for
the same reason the tunnel's do; the `cloud-edge:443` check covers the hop that is
actually in this repo's control.

## Storage — Postgres, not sqlite

`storage.type: postgres` against the CNPG cluster, at
`postgres-rw.cnpg-system.svc.cluster.local:5432/gatus`. This replaced sqlite on a
node-pinned `local-path` PVC once `apps/base/cnpg/` existed, and the PV and its
Talos user volume went with it — there is no `gatus` entry in
`apps/base/local-path/pv.yaml` any more and none in `pv_volumes` in
`terraform/proxmox/talos.tf`.

Three things followed from dropping the PVC:

- **`deployment.strategy` is back to the chart default.** It was pinned to
  `Recreate` only because a rolling update would start a second pod that could
  never get the ReadWriteOnce volume. With no volume, `RollingUpdate` is fine.
- **The pod is no longer pinned to one node**, and the history survives that node
  being rebuilt — which the sqlite file did not.
- **`persistence.enabled: false`.** Left on, the chart claims a PVC nothing
  writes to, and against a static StorageClass that is a pod Pending forever.

`postgres-rw` is the operator's primary Service and repoints itself on failover,
which is why it and not a pod IP.

### The credential

Role `gatus`, database `gatus`, both declared in `apps/base/cnpg/cluster/` —
`spec.managed.roles` on the Cluster and a `Database` CR. The password lives in
`gatus-db.sops.yaml` **there, not here**: CNPG needs a basic-auth copy in
`cnpg-system` to set the role's password and gatus needs its own copy to build
the URL, and one encrypted file holding both Secrets is what stops the two from
drifting. That is why the Flux Kustomization for `gatus` `dependsOn:
cnpg-cluster` — it waits on the Secret as much as on the database.

The URL is assembled in the config with `${POSTGRES_PASSWORD}`, the same
`os.ExpandEnv` pass the apiserver token and the Discord webhook use, so the
password never appears in a rendered manifest. Generate it alphanumeric-only:
anything needing percent-encoding breaks the URL silently.

## Retention — mostly not a knob

Gatus does not have a "keep 30 days" setting, and the reason is that it stores
two different things with two different lifetimes:

- **Raw results and events** are capped by *count*, not age:
  `maximum-number-of-results` (100) and `maximum-number-of-events` (50), per
  endpoint. Both are set explicitly here rather than left to default so the
  bound is visible. At a 60s interval, 100 results is the last ~100 minutes —
  asking for 30 days of raw results would mean ~43k rows per endpoint and is
  not what the schema is for.
- **Uptime is aggregated and already expires at 30 days.** Gatus rolls hourly
  buckets into daily ones and deletes anything past
  `uptimeRetention = 30 * 24h` (cleanup fires above 32 days). Those constants
  are compiled in — there is no config for them. That is what the 30d figure on
  the page reads from, and it is why the sqlite file stays small on its own.

Net: the DB is bounded to single-digit MB for 22 endpoints, the 1Gi PVC is
already far more than it needs, and the way to shrink it further is fewer
results per endpoint, not a shorter window.

## Alerting

Discord, through `alerting.discord`, with `default-alert` supplying the
thresholds so each endpoint only carries `alerts: [- type: discord]`: **3
consecutive failures to fire, 2 to resolve, and `send-on-resolved: true`**. At a
60s interval that is a three-minute outage before anything is posted, which is
what keeps a single blipped probe off the channel.

The webhook URL is the credential — anyone with it can post to the channel — so
it comes from `discord.sops.yaml` (Secret `gatus-discord`, key `webhook-url`),
reaches the pod as `DISCORD_WEBHOOK_URL`, and appears in the config only as
`${DISCORD_WEBHOOK_URL}`. Gatus runs `os.ExpandEnv` over the whole config file
before parsing it, which is the same mechanism the apiserver token uses. This is
why the Flux Kustomization for `gatus` has a `decryption` block — without it the
Secret is applied still encrypted and the pod alerts nowhere.

**`discord.sops.yaml` ships with a placeholder.** It is encrypted, so the
placeholder is invisible in a diff and nothing fails loudly — alerts simply post
into a 404. Fill it in with
`cd apps && mise exec -- sops base/gatus/discord.sops.yaml`.

## Gotchas

- **The chart's `config` block is the whole gatus config**, rendered verbatim
  into a ConfigMap. A typo is not caught by `kustomize build` or by Flux — the
  pod crashloops on it. `helm template` against the chart is the check.
- **Version pinned by hand.** Image automation only tracks our own GHCR images,
  so both the chart version and the gatus image it implies move deliberately.
