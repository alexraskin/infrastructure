# apps/base/loki/ and apps/base/alloy/ — logs

Loki in **SingleBinary** mode (one StatefulSet, `-target=all`) with chunks in a
Cloudflare R2 bucket, and Grafana Alloy as a DaemonSet shipping into it. Two
Kustomizations, `alloy` depending on `loki`.

The chart fights you in three specific ways:

- **`read`, `write` and `backend` must all be set to `replicas: 0`.** The chart
  defaults to SimpleScalable, and its `validate.yaml` aborts the render with "You
  have more than zero replicas configured for both the single binary and simple
  scalable targets" if `deploymentMode: SingleBinary` is set without zeroing
  them. It is a template error, not a runtime one — `kustomize build` passes and
  the HelmRelease fails.
- **The default caches would not fit on these nodes.** `chunksCache` alone asks
  for 8 GiB of memcached, on agents that have 8 GiB total. It, `resultsCache`,
  `lokiCanary`, `test` and the nginx `gateway` are all disabled; Grafana queries
  `svc/loki:3100` directly.
- **`global.extraEnvFrom` does not reach the single binary.** Its documented
  scope is read/write/backend and the distributed targets. Credentials have to be
  attached under `singleBinary.extraEnvFrom`, together with
  `singleBinary.extraArgs: ["-config.expand-env=true"]`.

Credentials never appear in the values: `loki.storage.s3.accessKeyId` is the
literal string `${R2_ACCESS_KEY_ID}`, which survives into the rendered ConfigMap
and is expanded at startup from the `loki-r2` Secret. The **endpoint is in that
Secret too**, because it embeds the Cloudflare account id and this repo is
public — the same reason the tailnet name lives in `grafana-tailnet.sops.yaml`.

R2 needs the same two adjustments the Terraform backends make: `region: auto`
(R2 has no regions) and `s3ForcePathStyle: true` (the `use_path_style` of
`providers.tf`). The bucket is `loki` and its API token is scoped to that bucket
only — deliberately *not* the credential in `secrets/r2.tfbackend`, which can
read and write Terraform state and has no business being readable by anything
with pod-exec in the cluster. Both are created by hand in the dashboard;
`terraform/cloudflare`'s token has three permission rows and gains nothing from
being handed R2 admin to create one bucket.

Alloy reads pod logs through the Kubernetes API (`loki.source.kubernetes`) rather
than tailing `/var/log/pods`, so there is no CRI log-format parsing and no
symlink chasing; the chart's ClusterRole already grants `pods/log`. It also runs
`loki.source.journal` against `/var/log/journal` — the nodes set
`Storage=persistent`, so k3s, tailscaled, sshd and kernel messages are queryable
in Grafana as `{job="systemd-journal"}` without SSHing anywhere.

The Grafana datasource is a ConfigMap in `logging` labelled
`grafana_datasource: "1"`. The monitoring stack's sidecar runs with
`NAMESPACE=ALL`, so nothing in `apps/base/monitoring/` changes to pick it up.

`service.yaml` puts Loki on the tailnet for exactly one client: the Oracle edge
node, which is a tailnet leaf with no `--accept-routes` — and the cluster's
advertised `10.0.200.0/24` is node LAN space, so Loki's ClusterIP was never in
it and no amount of route-accepting would have reached it. Nothing in the
cluster uses this path; Grafana and the Alloy DaemonSet still dial
`svc/loki:3100`, and that ClusterIP is a different Service, untouched.

- **A `LoadBalancer` with `loadBalancerClass: tailscale`, not an Ingress.** This
  is the operator's other mode: a plain TCP proxy on the port declared here,
  where an Ingress is HTTPS on 443 (its status advertises 80 as well; nothing is
  listening there). The difference decides the URL. An Ingress' LetsEncrypt cert
  is issued for the fully-qualified `loki.<tailnet>.ts.net`, so `https://loki/`
  fails hostname verification and the tailnet name has to travel to the edge in
  a gitignored file. A LoadBalancer has no cert, so the edge pushes to the bare
  MagicDNS name `http://loki:3100` and never learns the tailnet name — the URL
  stops being a secret and lives as a literal in `logging.nix`.
- **Dropping TLS costs nothing here.** Tailnet traffic is already encrypted end
  to end by WireGuard. The grant in `tailscale/policy.hujson` is the real
  control, and it has to be, because Loki runs `auth_enabled: false` — whatever
  the ACL admits can push, query *and* delete. Keep its `src` to `tag:edge`.
- **The `tailscale.com/tags: tag:k8s-loki` annotation is load-bearing.** Left
  alone the operator tags every proxy `tag:k8s`, so a grant letting the edge
  reach Loki would also let it reach Grafana. `tag:k8s-loki` exists to make that
  grant addressable at one service, and `tailscale/policy.hujson` must own it
  under `tag:k8s-operator` or the operator's device creation is rejected. The
  policy's `tests` assert both halves: `tag:edge` accepts `tag:k8s-loki:3100`
  and is denied `tag:k8s:443`.
- **`tailscale.com/hostname: loki` is what fixes the URL.** Without it the
  device is named after the Service, `loki-tailnet`. Names are also claimed
  first-come: if a device already holds `loki` when this one is created, the new
  one silently becomes `loki-1` and the edge pushes into a name that does not
  resolve, retrying forever with no error on the cluster side.
- The Kustomization `dependsOn: tailscale-operator`, for the same reason an
  Ingress would: a `loadBalancerClass` with no controller behind it is accepted
  and then sits `<pending>` forever.

## Gotchas

- **Loki's `retention_period` does nothing without `compactor.retention_enabled`.**
  Set one without the other and chunks are never deleted: logs look like they are
  being aged out because queries stop returning them, while the R2 bucket grows
  forever. Both live in `apps/base/loki/helmrelease.yaml`.
