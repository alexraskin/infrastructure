# apps/base/monitoring/ — Prometheus + Grafana

The only Helm in the repo: a `HelmRepository` plus a `HelmRelease` for
`kube-prometheus-stack`, pinned by hand (image automation only tracks our own
GHCR images). helm-controller is already there — it is a default component of
`flux install`, so nothing extra had to be added to `--components-extra`.

Every setting lives in `spec.values` in `helmrelease.yaml`, and four of them are
load-bearing:

- **The k3s control-plane scrapes are off.** `kubeControllerManager`,
  `kubeScheduler`, `kubeProxy` and `kubeEtcd` are `enabled: false`, because k3s
  runs all of them inside one process bound to `127.0.0.1`; the chart's
  ServiceMonitors for them would sit permanently DOWN. Turning them on is a
  `k3s-server.nix` change (`--kube-controller-manager-arg=bind-address=0.0.0.0`
  and friends, `--etcd-expose-metrics=true`) plus firewall ports, not a values
  edit.
- **`*SelectorNilUsesHelmValues: false`** on all four selectors. Left at the
  default, Prometheus only picks up ServiceMonitors labelled with this release's
  name, and a monitor written anywhere else in the repo is ignored *silently* —
  no error, the target simply never appears.
- **Alertmanager is disabled.** Nothing routes alerts yet; the rules still
  evaluate and fire in the Prometheus and Grafana UIs.
- **Storage is `local-path`**, the k3s default StorageClass, which is node-local:
  Prometheus is pinned to whichever node its PVC landed on and the history dies
  with that node. Dashboards, rules and datasources come from git, so a rebuild
  costs history and nothing else.

The Grafana admin login is `grafana-admin.sops.yaml`, not the chart's generated
password — the generated one is rewritten on every reconcile. Grafana reads it
only when it initialises its own DB, so changing the secret afterwards does
nothing; change it in the UI, or delete the grafana PVC.

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
address is in the flannel range and reachability is the exporter host's
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

- **node-exporter needs TCP 9100 open on every node.** It runs with
  `hostNetwork`, so Prometheus scrapes it at `<node-ip>:9100` and the packet
  arrives over flannel, not loopback — the NixOS firewall drops it and *every*
  node target goes DOWN at once. `nix/modules/monitoring.nix` opens it, which
  means adding monitoring to a node is a `deploy`, not just a Flux reconcile.
  The symptom reads like a broken exporter; it is the host firewall.
- **Renaming the Grafana admin in the UI silently breaks provisioning reloads.**
  The sidecars write dashboards and datasources into an emptyDir and then POST
  `/api/admin/provisioning/*/reload`, authenticating as `admin-user` from
  `grafana-admin.sops.yaml`. Grafana reads `GF_SECURITY_ADMIN_USER` only when it
  first creates its DB, so a rename in the UI leaves the Secret stale and every
  reload 401s with `no user found: user not found` — visible only in the Grafana
  container log, never in Flux, and the symptom is "my new datasource never
  shows up" until something restarts the pod. Fix by changing `admin-user` in
  the secret, not by renaming the user back.
