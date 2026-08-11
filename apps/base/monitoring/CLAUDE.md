# apps/base/monitoring/ — Prometheus + Grafana

The only Helm in the repo: a `HelmRepository` plus a `HelmRelease` for
`kube-prometheus-stack`, pinned by hand (image automation only tracks our own
GHCR images). helm-controller is already there — it is a default component of
`flux install`, so nothing extra had to be added to `--components-extra`.

Every setting lives in `spec.values` in `helmrelease.yaml`, and four of them are
load-bearing:

- **The control-plane scrapes are on, except kube-proxy.** Talos runs the
  controller-manager, scheduler and etcd as real static pods, and the machine
  config in `terraform/proxmox/talos.tf` binds their metrics outward
  (`bind-address: 0.0.0.0`, `listen-metrics-urls`). Enabling these without those
  arguments puts the targets permanently DOWN, so the two changes travel
  together. `kubeProxy` stays `enabled: false` forever: there is no kube-proxy —
  `cluster.proxy.disabled` is set and Cilium replaces it.
- **`*SelectorNilUsesHelmValues: false`** on all four selectors. Left at the
  default, Prometheus only picks up ServiceMonitors labelled with this release's
  name, and a monitor written anywhere else in the repo is ignored *silently* —
  no error, the target simply never appears.
- **Alertmanager is disabled.** Nothing routes alerts yet; the rules still
  evaluate and fire in the Prometheus and Grafana UIs.
- **Prometheus' storage is `local-path`**, which on Talos is a static,
  no-provisioner StorageClass with hand-written PVs in `apps/base/local-path/`.
  It is node-local: Prometheus is pinned to the node its PV names and the
  history dies with that node. Growing the claim means editing the PV too —
  nothing provisions on demand. Dashboards, rules and datasources come from git,
  so a rebuild costs history and nothing else.
- **Grafana has no PVC at all.** Its database is Postgres in the CNPG cluster
  (`apps/base/cnpg/`), so it is not pinned to a node and survives one being
  rebuilt. See below.

## Grafana's database

`grafana.ini`'s `database` section points at
`postgres-rw.cnpg-system.svc.cluster.local:5432/grafana` — the operator's
primary Service, which repoints itself on failover, never a pod IP. Role
`grafana` and database `grafana` are declared in `apps/base/cnpg/cluster/`
(`spec.managed.roles` and a `Database` CR), and the password lives in
`grafana-db.sops.yaml` **there, not here**: CNPG needs a basic-auth copy in
`cnpg-system` to set the role's password and Grafana needs one in `monitoring`.
One encrypted file holds both Secrets so they cannot drift, which is why this
Kustomization `dependsOn: cnpg-cluster`.

The password reaches the pod as `GF_DATABASE_PASSWORD` rather than appearing in
`grafana.ini`: Grafana maps `GF_<SECTION>_<KEY>` onto the ini file, so
`database.password` is overridden without the value ever being in a rendered
manifest.

This replaced sqlite on a node-pinned `local-path` PVC, and the PV and its Talos
user volume went with it — there is no `grafana` entry in
`apps/base/local-path/pv.yaml` or in `pv_volumes` in `terraform/proxmox/talos.tf`.
That also retires a real failure mode: the volume root's ownership was reset by
every Talos volume reconcile, and sqlite needs to create a `-journal` file in it
on every write, so Grafana would return 500 on login while still serving pages.
See the gotcha in the root `CLAUDE.md`.

The Grafana admin login is `grafana-admin.sops.yaml`, not the chart's generated
password — the generated one is rewritten on every reconcile. Grafana reads it
only when it initialises its own DB, so changing the secret afterwards does
nothing; change it in the UI, or drop and recreate the `grafana` database.

Dashboards are `.json` files under `dashboards/`, turned into ConfigMaps by
`configMapGenerator` with `disableNameSuffixHash: true` and the label
`grafana_dashboard: "1"`, which is what the Grafana sidecar selects on
(cluster-wide, `searchNamespace: ALL`). They load within ~30s, with no restart
and no UI import. Without `disableNameSuffixHash` every edit writes a
differently-named ConfigMap and leaves the old one behind for the sidecar to
load as a second copy.

Off-cluster targets go in `prometheus.prometheusSpec.additionalScrapeConfigs` as
plain `scrape_config` syntax — currently the `plex-exporter` job at
`10.0.200.87:9001`. Prometheus dials it straight from its pod, so the source
address is in the Cilium pod CIDR and reachability is the exporter host's
firewall's business, not this repo's.

Access is over the tailnet only, at `https://grafana.<tailnet>.ts.net`, served by
the tailscale operator (`apps/base/tailscale-operator/CLAUDE.md`) — Grafana
itself is a plain ClusterIP and no node
port is involved. **The tailnet name is not in this repo**: it would otherwise
be the one piece of the setup a public repo hands out, so it lives in
`grafana-tailnet.sops.yaml` and reaches Grafana as `GF_SERVER_DOMAIN` /
`GF_SERVER_ROOT_URL` through `grafana.envValueFrom`, where env beats the ini
file. They have to match the name the operator actually serves on: wrong values
and the page still loads while login redirects and static assets break, which
reads like a Grafana bug rather than a config one. Nothing
goes through the cloudflared tunnel, which is why the monitoring Kustomization
has no `dependsOn: cloudflared` — it depends on `tailscale-operator` instead, for
the IngressClass. Its `timeout` is 15m, not the 3m the other apps use: first
install lays down CRDs, five workloads and a PVC.

## Gotchas

- **node-exporter needs nothing opened on Talos.** It runs with `hostNetwork`
  and Prometheus scrapes it at `<node-ip>:9100`; Talos has no host firewall
  unless a `NetworkRuleConfig` declares one. Under NixOS this was a per-node
  firewall rule and a redeploy, and forgetting it put *every* node target DOWN
  at once — if that symptom ever returns here, the cause is a machine config
  that grew an ingress firewall, not the exporter.
- **Renaming the Grafana admin in the UI silently breaks provisioning reloads.**
  The sidecars write dashboards and datasources into an emptyDir and then POST
  `/api/admin/provisioning/*/reload`, authenticating as `admin-user` from
  `grafana-admin.sops.yaml`. Grafana reads `GF_SECURITY_ADMIN_USER` only when it
  first creates its DB, so a rename in the UI leaves the Secret stale and every
  reload 401s with `no user found: user not found` — visible only in the Grafana
  container log, never in Flux, and the symptom is "my new datasource never
  shows up" until something restarts the pod. Fix by changing `admin-user` in
  the secret, not by renaming the user back.
