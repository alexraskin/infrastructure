# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

The repo root is an HA k3s cluster: 3 servers (control plane + embedded etcd) and
3 agents, running as NixOS VMs on a single Proxmox host. Terraform creates the
VMs, NixOS owns everything inside them, Flux deploys workloads from `apps/`.

## Commands

`mise` runs everything. Three separate configs: `mise.toml` at the root
(cluster), `apps/mise.toml` (GitOps) and `00-edge-compute/mise.toml` (the Oracle
edge). `mise trust` is needed once per directory.

```bash
mise run preflight      # validate Proxmox API token, node, datastores, VM IDs, IPs, SSH — do this first
mise run image          # build the golden NixOS qcow2 into build/
mise run tf:plan        # terraform, from terraform/proxmox/
mise run tf:apply       # create the six VMs
mise run push-token     # generate secrets/k3s-token and scp it to every node
mise run push-tailscale-key   # scp secrets/tailscale-authkey to every node (no-op without one)
mise run deploy         # nixos-rebuild every node in the right order
mise run deploy-node k3s-agent-2   # one node
mise run kubeconfig     # fetch ./kubeconfig, rewritten to point at the VIP
mise run status         # kubectl get nodes + kube-system pods
mise run ts:status      # tailnet name/address/primary routes per node
mise run ts:plan        # terraform, from tailscale/ (the tailnet policy file)
mise run ts:apply       # same, applied — CI does this on push to main
mise run cf:plan        # terraform, from terraform/cloudflare/ (tunnel + DNS)
mise run cf:apply       # same, applied
mise run reset          # DESTRUCTIVE: wipe k3s state cluster-wide (typed confirmation)
```

From `00-edge-compute/` (its own mise config):

```bash
mise run tf:apply       # Oracle instance, public IP, DNS records — retries every AD on capacity errors
mise run install        # nixos-anywhere: kexec + disko + install. One shot, erases the box
mise run deploy         # push the flake and switch; repeatable
mise run status         # tailscale, haproxy, certs, backend reachability
```

Validation without touching infrastructure:

```bash
terraform -chdir=terraform/proxmox validate && terraform fmt -recursive terraform/
terraform -chdir=terraform/cloudflare validate
terraform -chdir=00-edge-compute/terraform validate
terraform -chdir=tailscale init -backend=false && terraform -chdir=tailscale validate
./scripts/nix.sh 'nix eval ".#nixosConfigurations.k3s-server-1.config.networking.hostName"'
# path:, or nix resolves to the enclosing git repo — which is the cluster flake
./scripts/nix.sh 'nix eval "path:./00-edge-compute#nixosConfigurations.edge-1.config.system.build.toplevel.drvPath"'
cd apps && mise exec -- kustomize build base/alexraskin-com
cd apps && mise exec -- kustomize build base/monitoring
cd apps && mise exec -- kustomize build base/tailscale-operator
cd apps && mise exec -- kustomize build base/loki && mise exec -- kustomize build base/alloy
```

There is no test suite. "Does it work" means `mise run preflight`, a `terraform
plan`, a `nix eval` of the affected node, and finally `mise run status`.

## Architecture

### hosts.json is the single source of truth

Both `flake.nix` (`builtins.fromJSON`) and `terraform/proxmox/main.tf` (`jsondecode`) read
it. Node IPs, VM IDs, sizes, the VIP, the NIC name and the disk device all live
there. Changing a node's cores/memory/disk is a `tf:apply`; changing its IP needs
both `tf:apply` and `deploy`.

### Two-phase node lifecycle

1. **Golden image** — `base.nix` + `image.nix`, built by nixos-generators into a
   compressed qcow2. Carries no node identity; gets hostname, IP and SSH key from
   the Proxmox cloud-init drive Terraform configures.
2. **Per-node config** — `nixosConfigurations.<host>` = `base` + `hardware` +
   `network` + `tools` + a role module. Pushed by `scripts/deploy-node.sh`, which
   replaces the generic system with a static one. cloud-init is off afterwards.

`image.nix` is deliberately **not** in the node configs, which is why
`hardware.nix` exists: it re-states the root filesystem, `boot.growPartition` and
grub settings that nixos-generators' qcow format supplies to the image. Without
it node configs fail to evaluate with "The 'fileSystems' option does not specify
your root file system".

### scripts/nix.sh — the Nix entry point

The build host (Debian) has no Nix, so this wrapper runs the given shell script
against the host's `nix` if present, otherwise inside the `nixos/nix` container
with a persistent `k3s-nix-store` volume. Every Nix invocation in the repo goes
through it. Three things it handles that are easy to break:

- **Flakes evaluate from the git tree**, which is what keeps `secrets/` and the
  ~600MB `build/` out of the nix store. Untracked files are invisible to
  evaluation, so the script refuses to run when `flake.nix`, `flake.lock`,
  `hosts.json` or `nix/` have untracked changes. **`git add` before deploying.**
- `/dev/kvm` is passed through and `system-features = kvm` declared — the qcow2 is
  assembled inside a qemu VM and the build fails without it.
- A generated gitconfig with `safe.directory = /work` is mounted, because the
  container is root, the repo is not, and libgit2 (which Nix uses) ignores
  `GIT_CONFIG_*` environment variables.

### Deploying is not nixos-rebuild

`scripts/deploy-node.sh` spells out what `nixos-rebuild switch --target-host`
does — build the closure, `nix copy --to ssh://`, `nix-env -p
/nix/var/nix/profiles/system --set`, `switch-to-configuration switch` — so it
works from a build host whose Nix lives in a container.

`mise run deploy` orders it: bootstrap server (`--cluster-init`) → wait for
`/readyz` → remaining servers (joining the bootstrap's IP directly) → wait for
the VIP → agents (joining the VIP). Waits are bounded; they fail rather than hang.

### Cluster wiring

- The k3s join token is **not** in the Nix config. It is generated into
  `secrets/k3s-token` and scp'd to `/var/lib/k3s-token` before the first deploy;
  k3s will not start without it, which is why `deploy` depends on `push-token`.
- kube-vip provides the control-plane VIP, installed via
  `services.k3s.manifests` on the bootstrap server only. Do not use
  systemd-tmpfiles for this — `/var/lib/rancher/k3s/server/manifests` does not
  exist yet when tmpfiles runs on a fresh node, so the rule silently no-ops.
- Remote access is Tailscale as a **subnet router**, not per-node tailnet
  addresses: the three servers advertise `cluster.tailscale.advertise_routes`
  (`10.0.200.0/24`), so an off-LAN kubectl still targets the VIP and stays HA.
  `nix/modules/tailscale.nix` is in the node configs but deliberately *not* in
  the golden image — the image has no identity to log in with, and the closure
  would be pushed to Proxmox for nothing. `useRoutingFeatures = "server"` on
  servers only (it enables IP forwarding); routes go in both `extraUpFlags` and
  `extraSetFlags` or they vanish after the first `tailscale up`. The module sets
  `package = unstable.tailscale`, and that line is **the only consumer of the
  `nixpkgs-unstable` input** in the whole repo — 25.05 ships 1.82.5, which the
  admin console flags as vulnerable. Only the package comes from unstable;
  everything else on the node stays on 25.05. The pre-auth
  key follows the k3s-token pattern: `secrets/tailscale-authkey` →
  `/var/lib/tailscale-authkey`, pushed before `deploy` because
  `tailscaled-autoconnect` runs during activation. **That key must be a tagged
  one** (`tag:k3s`): the tag is what the ACL's `autoApprovers` matches to approve
  `10.0.200.0/24` on its own, and — more importantly — tagged devices have no key
  expiry, where user-owned ones expire together ~180 days after they were
  enrolled and take the subnet route with them. Tags come from the auth key or
  from the admin console, never from the module: `tailscale set` has no
  `--advertise-tags`, so the flag cannot be handled the way routes are. Clients
  still need `--accept-routes`, and `--accept-dns` too if they want MagicDNS
  names like the Grafana Ingress below. The tailnet policy file itself is
  `tailscale/policy.hujson` in this repo, applied by a third Terraform root —
  see below.
- traefik and servicelb are disabled. Traffic enters only through the cloudflared
  tunnel in `apps/`, which dials out and forwards to Services by cluster DNS.
  The tunnel itself — its ingress rules and the CNAMEs pointing at it — is a
  second Terraform root, `terraform/cloudflare/` (`mise run cf:plan` /
  `cf:apply`), covered below.

### Terraform state lives in R2

Both roots — `terraform/proxmox/` and `terraform/cloudflare/`, one per set of
credentials — use the `s3` backend against Cloudflare R2 (`bucket = "terraform"`,
one `key` each). The backend block is deliberately **partial**: `access_key`,
`secret_key` and `endpoints.s3` are absent from it, because a backend block takes
no variables and this repo is public — the endpoint alone carries the account ID.
They come from `secrets/r2.tfbackend`, which `mise run tf:init` / `cf:init` pass
with `-backend-config`. `terraform init` run by hand, without that flag, will
prompt for the missing values and then write them into `.terraform/` — use the
tasks.

The R2 credential is an **R2 API token** (dashboard -> R2 -> Manage API tokens),
not the `cloudflare-api-token` the provider uses; the two are unrelated and
neither works in place of the other. `skip_*` and `use_path_style` are there
because R2 is S3-compatible but not AWS.

Terraform 1.9 is pinned, which predates `use_lockfile` (1.10+), so there is **no
state locking** — two concurrent applies would corrupt state. Single operator, so
this is accepted rather than solved; bumping the pin and setting
`use_lockfile = true` is the fix if that stops being true.

### terraform/cloudflare/ — the tunnel and DNS

A second root on purpose: different credentials, different blast radius. A DNS
change should not plan against the VMs. State holds the tunnel token in
cleartext, so the R2 bucket must stay private.

Auth is `CLOUDFLARE_API_TOKEN`, read from `secrets/cloudflare-api-token` by the
`cf:*` tasks — never a tfvars entry, never in state. The token needs exactly
three rows on a *custom* token: Account/Cloudflare Tunnel/Edit, Zone/DNS/Edit,
Zone/Zone/Read. DNS/Edit does **not** imply Zone/Read, and a token missing it
gets an empty zone list rather than a 403 — the same permission-filtering
behaviour as a privsep Proxmox token.

It **adopts** the pre-existing tunnel rather than creating one: `imports.tf`
holds `import` blocks for the tunnel, its config and every CNAME, so the
connector token already in `apps/base/cloudflared/token.sops.yaml` stays valid
and cloudflared never restarts. A correct plan is "N to import, 0 to add, 0 to
destroy". If it wants to *create* the tunnel, an import block is missing or
`tunnel_id` is wrong — applying then builds a second tunnel and moves the CNAMEs
to one with no connectors, which is the outage case.

`var.ingress` is the whole tunnel config. Order only matters for overlapping
rules (paths, wildcards), so a plan that merely reorders distinct hostnames is
inert; a rule that disappears from the list is deleted on apply. The catch-all
is appended automatically — Cloudflare requires the list to end with a rule that
has no hostname. `origin_request = {} -> null` on an adopted config is the
provider's round-trip noise, not a change. The config resource has no DELETE
endpoint, hence the standing "cannot be destroyed" warning.

Zones are matched by longest suffix, so `go.example.com` finds `example.com` in
`var.zones` with no per-entry zone. Only externally reachable apps need an entry
at all — `lhbotgo` has none, it dials Discord out.

One-time recipes, kept here rather than as tasks nobody runs twice:

```bash
# account + tunnel ID, without the dashboard: the connector token is base64 JSON
# {"a": account, "t": tunnel, "s": secret}
cd apps && SOPS_AGE_KEY_FILE=../secrets/age.key sops -d base/cloudflared/token.sops.yaml \
  | sed -n 's/.*token: //p' | base64 -d | jq '{account: .a, tunnel: .t}'

# zone name -> zone ID
curl -fsS "https://api.cloudflare.com/client/v4/zones?per_page=50" \
  -H "Authorization: Bearer $(cat secrets/cloudflare-api-token)" \
  | jq -r '.result[] | "\(.name) \(.id)"'

# the tunnel's live ingress rules, to transcribe into tfvars
curl -fsS "https://api.cloudflare.com/client/v4/accounts/$ACCT/cfd_tunnel/$TUN/configurations" \
  -H "Authorization: Bearer $(cat secrets/cloudflare-api-token)" | jq '.result.config.ingress'

# import blocks for CNAMEs that already exist
curl -fsS "https://api.cloudflare.com/client/v4/zones/$ZONE/dns_records?type=CNAME&per_page=100" \
  -H "Authorization: Bearer $(cat secrets/cloudflare-api-token)" \
  | jq -r --arg z "$ZONE" '.result[] | select(.content | endswith(".cfargotunnel.com"))
      | "import {\n  to = cloudflare_dns_record.tunnel[\"\(.name)\"]\n  id = \"\($z)/\(.id)\"\n}"'
```

If the tunnel is ever replaced, the new token has to reach the cluster:
`terraform output -raw tunnel_token` into a copy of
`apps/base/cloudflared/token.example.yaml`, then `mise run sops-encrypt`.

### tailscale/ — the tailnet policy file

A third Terraform root, holding one resource: `tailscale_acl.policy`, whose
`acl` is `file("policy.hujson")`. That is the tailnet's *entire* policy file,
not just its `acls` block — the resource name predates Tailscale's rename — so
an apply overwrites whatever is in the admin console. State is in the same R2
bucket as the other two roots, `key = "tailscale/terraform.tfstate"`.

- It **adopts**, like `terraform/cloudflare/`: `policy.tf` carries a permanent
  `import` block with `id = "acl"` (there is one policy file per tailnet). The
  import is not optional — `overwrite_existing_content` is left at `false`, and
  the provider then refuses to write a policy it has never read. That is the
  guard against a fresh state replacing a hand-edited policy. The block is
  *in* `policy.tf` rather than an `imports.tf` because `.gitignore` excludes
  that filename.
- **`terraform plan` validates the policy against the Tailscale API**, tests
  included, so a syntax error or a failing `tests` entry fails the PR instead of
  the apply. This is the whole reason to run plan on pull requests.
- **Two different credentials, by design.** CI authenticates as a *federated
  identity* — `TAILSCALE_OAUTH_CLIENT_ID` + `TAILSCALE_AUDIENCE`, both repo
  *variables*, not secrets. The provider mints the GitHub OIDC token itself and
  exchanges it, which is why the job needs `permissions: id-token: write` and
  why no Tailscale secret exists in this public repo's Actions. Running by hand
  uses an OAuth client instead, `secrets/tailscale-oauth.env`, scoped to
  `policy_file:write`. `audience` and `oauth_client_secret` conflict in the
  provider, so neither is written into `providers.tf`: `provider "tailscale" {}`
  is empty and everything arrives through the environment.
- **`tailnet` is deliberately unset**, defaulting to the tailnet that owns the
  credential — the name is the one part of this worth not publishing, same
  reasoning as `grafana-tailnet.sops.yaml`.
- The federated identity's subject claim binds to
  `repo:<owner>/<repo>:environment:tailscale`, which is why the job declares
  `environment: tailscale`. A workflow that omits it cannot authenticate even
  from this repo.
- Terraform 1.9 means no state locking here either, so the workflow's
  `concurrency: { group: tailscale, cancel-in-progress: false }` is what keeps
  two applies apart.

```bash
mise run ts:plan     # from the repo root; needs secrets/tailscale-oauth.env
mise run ts:apply    # CI does this on push to main
```

### apps/ — Flux GitOps

`apps/clusters/k3s/apps.yaml` lists what Flux reconciles; `apps/base/*` holds the
manifests. Secrets are SOPS-encrypted to an age key in `secrets/age.key`
(gitignored, outside `apps/`) and decrypted in-cluster via the `sops-age` secret.
The repo is public — encrypted `*.sops.yaml` is meant to be committed; the age
key is not. `flux bootstrap` pushes commits, so do not run it casually.

Image tags in `apps/base/*/deployment.yaml` are **owned by
image-automation-controller**, not by hand: `apps/base/image-automation/` scans
GHCR, picks the newest semver tag and pushes a commit rewriting the line marked
`# {"$imagepolicy": "flux-system:<app>"}`. Editing a tag manually is undone on
the next 5m scan; pin by narrowing the ImagePolicy range instead. This is why
the GitRepository is SSH with the `flux-git-auth` deploy key (`mise run
git-deploy-key`, needs write access on GitHub) rather than anonymous HTTPS, and
why `install` passes `--components-extra=image-reflector-controller,image-automation-controller`.
Only our own images are automated; `cloudflared` is still pinned by hand.

### apps/base/monitoring/ — Prometheus + Grafana

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
the tailscale operator (below) — Grafana itself is a plain ClusterIP and no node
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

### apps/base/tailscale-operator/ — the tailnet IngressClass

Puts Services on the tailnet from inside the cluster, which is a different
mechanism from `nix/modules/tailscale.nix`: the nodes are a **subnet router**
advertising `10.0.200.0/24`, the operator gives an individual Service its **own
tailnet device** with a real LetsEncrypt cert. Both are in use; neither replaces
the other.

An Ingress opts in with `ingressClassName: tailscale`, and the device name comes
from `tls.hosts[0]` — *not* from a rule host, which is left unset. The operator
spawns a proxy StatefulSet per Ingress; because that is a pod, losing a node
reschedules it, where a NodePort would have been pinned to node IPs.

Credentials are an **OAuth client** (`operator-oauth`, keys `client_id` and
`client_secret`), not the pre-auth key the nodes use in
`secrets/tailscale-authkey`. Unrelated things; neither works in place of the
other. The client needs the Devices Core and Auth Keys write scopes and the
`tag:k8s-operator` tag, and the ACL needs `tag:k8s-operator` plus a `tag:k8s`
owned by it — the operator tags every proxy it creates with the latter, and
device creation is rejected outright if it does not own the tag.

`oauth.clientId`/`clientSecret` are left empty in the HelmRelease on purpose:
empty means the chart mounts the pre-existing `operator-oauth` Secret, so the
credentials stay in SOPS rather than in a values block in a public repo.

The API-server proxy (`apiServerProxyConfig.mode`) is off. kubectl already
reaches the VIP through the subnet router, and enabling it means ACL grants that
map tailnet identities onto cluster RBAC.

Versions here are **not** the ones on the nodes — the operator and its proxies
run tailscaled from container images, so `nix/modules/tailscale.nix` has no
effect on them. The stable chart's appVersion is 1.98.9, which the admin console
flags as vulnerable, so `proxyConfig.image.tag` is pinned ahead of the chart at
`v1.102.2`. The operator cannot follow: `tailscale/k8s-operator` has no stable
tag past `v1.98.9` (only `unstable-v1.10x`), so the `k3s-operator` device stays
flagged until upstream ships one. Remove the pin when a stable chart carries
1.102.x or later, or it starts holding proxies back instead of pushing them
forward.

### apps/base/loki/ and apps/base/alloy/ — logs

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

`ingress.yaml` puts Loki on the tailnet, the same operator mechanism as the
Grafana Ingress. It exists for exactly one client: the Oracle edge node, which
is a tailnet leaf with no `--accept-routes` — and the cluster's advertised
`10.0.200.0/24` is node LAN space, so Loki's ClusterIP was never in it and no
amount of route-accepting would have reached it. Nothing in the cluster uses
this path; Grafana and the Alloy DaemonSet still dial `svc/loki:3100`.

- **The `tailscale.com/tags: tag:k8s-loki` annotation is load-bearing.** Left
  alone the operator tags every proxy `tag:k8s`, so a grant letting the edge
  reach Loki would also let it reach Grafana. `tag:k8s-loki` exists to make that
  grant addressable at one service, and `tailscale/policy.hujson` must own it
  under `tag:k8s-operator` or the operator's device creation is rejected. The
  policy's `tests` assert both halves: `tag:edge` accepts `tag:k8s-loki:443` and
  is denied `tag:k8s:443`.
- **Loki runs `auth_enabled: false`**, so whatever the ACL admits can push,
  query *and* delete. The grant is the only control; keep its `src` to
  `tag:edge`.
- The Kustomization now `dependsOn: tailscale-operator` for the IngressClass. An
  Ingress naming a class that does not exist yet is accepted and then never
  reconciled — no error, it simply never gets a device.

### 00-edge-compute/ — the public edge

A free Oracle Cloud ARM box running HAProxy, terminating TLS on a public IP and
forwarding to home over Tailscale. It exists because **Plex cannot go through
the cloudflared tunnel**: Cloudflare's terms 2.8 restrict serving video through
the proxy, disabling caching does not change that (2.8 is about bytes crossing
their network), and a tunnel is proxied by definition — `*.cfargotunnel.com`
only resolves orange-clouded. Oracle rather than AWS purely for egress: 10 TB/mo
free against AWS's 100 GB, and a 4K remux direct-play is ~27 GB/hour.

Its own mise config (`mise trust` once) and its own Terraform root, state in R2
under `edge-compute/terraform.tfstate`. Structure follows
[FinnPL/Homelab-Setup `cloud-edge`](https://github.com/FinnPL/Homelab-Setup/tree/main/cloud-edge).

- **`edge.json` is the single source of truth**, like `hosts.json`: shape, zone,
  sites and their backends, read by `flake.nix` (`builtins.fromJSON`) and
  `terraform/network.tf` (`jsondecode`). One entry grows a DNS record, an ACME
  cert and an HAProxy backend. It is **gitignored** — the public hostnames are
  the one part of this setup worth not publishing, the same reasoning as
  `grafana-tailnet.sops.yaml`. Structure is in `edge.json.example`; a missing
  `edge.json` fails the flake eval and every `tf:*` task.
- **The flake root is `00-edge-compute/`, not a subdirectory.** A flake's source
  is copied into the store, so a flake in `nixos/` reading `../edge.json`
  resolves it to `/nix/store/edge.json` and fails with "access to absolute path
  … is forbidden in pure evaluation mode". `terraform/` reads `../edge.json`
  instead, which is why that path looks backwards.
- **Own flake, deliberately not another `hosts.json` entry.** The cluster flake
  is x86_64 and every node in it is a k3s node from one golden image; this is one
  aarch64 box in someone else's datacentre. Sharing it would make the cluster's
  `nix eval` checks depend on an Oracle instance. Cost is a duplicated ~30-line
  tailscale module.
- **Three phases**: `tf:apply` (Ubuntu ARM instance, public IP, DNS records) →
  `install` (nixos-anywhere: kexec, disko, install, reboot — one shot, erases
  the box, refuses if already NixOS) → `deploy` (push flake, switch, repeatable).
- **Both build on the box.** The build host is x86_64 and the instance is
  aarch64, so `scripts/deploy-node.sh`'s build-locally-then-`nix copy` cannot
  work. `--build-on-remote` hands it to the instance's Ampere cores; the kexec
  image is *substituted* prebuilt, a download rather than a build, so no
  emulation is involved. `deploy` ships the tree with tar over ssh, not rsync —
  rsync must exist on both ends and is not in a minimal NixOS profile, so the
  first deploy would be the one that fails.
- **The public IP is ephemeral on purpose.** A reserved OCI IP cannot be
  attached at create time, only afterwards and only to an instance that has no
  ephemeral one — which means no internet during first boot and no unattended
  install. Taking the ephemeral address and having `terraform/dns.tf` point the
  A records at `oci_core_instance.edge.public_ip` removes that ordering problem.
  This is also why the Cloudflare provider is in *this* root and not
  `terraform/cloudflare/`: the value only exists here.
- **`proxied = false` on those records is load-bearing.** Orange-clouding puts
  the video back on Cloudflare's network and back under 2.8.
- **"Out of host capacity" is the normal failure**, not a misconfiguration.
  Always-free A1 capacity is scarce and uneven across availability domains;
  `mise run tf:apply` walks every AD, retrying on that error only.
- **TLS terminates at the edge**, unlike the reference design's SNI passthrough.
  There is no reverse proxy at home to hand the connection to, and Plex serves
  its own `*.plex.direct` cert, which is not valid for the name clients dial.
  Certs are LetsEncrypt over **DNS-01**, which is why port 80 is closed in both
  the OCI security list and the NixOS firewall.
- **Tailscale here is a leaf with no `--accept-routes`.** The Plex host is its
  own tailnet device, so the backend is a peer address; accepting the cluster's
  `10.0.200.0/24` would give the one machine with a public IP a path to the whole
  LAN, and would hairpin every stream through whichever k3s server owns the
  route. Its pre-auth key is `secrets/tailscale-authkey-edge` — tagged, so the
  ACL can grant it exactly the one `host:port` in `edge.json` and nothing else.
- **`--ssh` is on, as break-glass.** tailscaled serves port 22 on the tailnet
  address, so a dead sshd no longer means a trip to the OCI serial console —
  which is what it meant once, with 22 removed from the security list and no
  other way in. sshd still owns the public IP, which is what `scripts/deploy.sh`
  and every `mise` task here connect to (`terraform output -raw public_ip`), so
  automation is untouched. The matching rule in `tailscale/policy.hujson` is
  `autogroup:admin` → `tag:edge`, users `root`, **`accept` not `check`**: check
  puts a browser re-auth in front of every connection, fine for a human and
  fatal for anything unattended. It cannot ride on the existing rule, whose
  `dst` is `autogroup:self` — that means devices owned by the calling user, and
  a tagged node has no owner.
- **`logging.nix` ships the journal to the cluster's Loki**, over the tailnet,
  to the operator-served Ingress in `apps/base/loki/ingress.yaml`. It is
  `services.alloy`, matching what the cluster runs, not promtail.
  - HAProxy logs with `log /dev/log local0 info` and journald owns `/dev/log`,
    so haproxy, tailscaled, `acme-*.service`, sshd and the kernel are one
    journal and one `loki.source.journal` collects all of them. No rsyslog.
  - `services.journald.storage = "persistent"` — the default is volatile when
    `/var/log/journal` is absent, which drops anything not yet shipped across a
    reboot.
  - The job label is `edge-journal`, deliberately **not** `systemd-journal`:
    that is what the in-cluster DaemonSet labels the six k3s nodes with, and
    reusing it folds an Oracle box into every existing
    `{job="systemd-journal"}` query without anyone noticing.
  - Alloy's UI listens on `0.0.0.0:12345` by default, and `default.nix` sets
    `trustedInterfaces = [ "tailscale0" ]` — which opens *every* port to every
    tailnet peer regardless of `allowedTCPPorts`. `extraFlags` binds it to
    loopback instead.
  - **`--accept-dns=true` in `tailscale.nix` is a dependency of this**, not a
    preference. The push URL is a MagicDNS name and `*.ts.net` is *not*
    published in public DNS, so with `accept-dns` false the box has no resolver
    for it at all and `loki.write` logs
    `dial tcp: lookup … no such host` on a retry loop forever while Alloy
    otherwise looks perfectly healthy.
  - The push URL is a **required** `loki_push_url` in `edge.json`, because it
    contains the tailnet name and this repo is public. Missing, it `throw`s at
    eval with a pointer to `edge.json.example` rather than silently shipping
    nowhere. An `edge.json` predating this module will not have the key.
- **The first ACME run always fails, and nothing retries it.** nixos-anywhere
  activates the whole config during `install`, before `push-secrets.sh` has put
  `/etc/cloudflare/credentials` on the box, so the acme unit dies with "Failed
  to load environment files". A later `deploy` does *not* fix it: the unit's
  definition has not changed, so `switch-to-configuration` leaves the failed
  oneshot alone, and HAProxy goes on serving the self-signed placeholder that
  acme writes so services can start. The site answers on 443 and fails
  verification — `curl -w '%{ssl_verify_result}'` returns 19, not 0. `deploy.sh`
  now starts `acme-<domain>.service` explicitly after the switch, which is
  idempotent (the unit checks expiry before contacting LetsEncrypt).
- Credentials all come from `secrets/` via `scripts/tf-env.sh` as `TF_VAR_*`:
  `oci.env`, `oci_api_key.pem` (the signing key; `oci_api_key_public.pem` is
  already uploaded to OCI and unread here), and the existing
  `cloudflare-api-token`, which is also pushed to the box for ACME DNS-01.

## Gotchas discovered the hard way

- **The NIC is `eth0`**, not `ens18`. `network.nix` matches `"en* eth*"`; getting
  this wrong strands a node with no route and no SSH, recoverable only from the
  Proxmox console.
- **k3s node names are pinned with `--node-name`.** `networking.hostName` only
  writes `/etc/hostname`, which systemd reads at boot — a `switch` leaves the live
  hostname stale, so without the flag every node registers as `nixos` and the
  second one dies with "duplicate node name found". An activation script also
  writes `/proc/sys/kernel/hostname` so the live name matches immediately.
- **Never pass `--node-label=node-role.kubernetes.io/*`.** kubelet rejects
  self-assigned labels in that namespace and refuses to start. Set roles with
  `kubectl label` instead.
- **The Proxmox provider ignores `~/.ssh/config`** and needs either
  `pve_ssh_private_key_path` or a loaded ssh-agent. Missing credentials fail
  *partway* through apply, after the VMs exist.
- **A privsep API token authenticates and then sees nothing** — Proxmox filters
  lists by permission rather than returning 403, so datastores and bridges come
  back as empty arrays. `pveum user token modify <userid> <tokenid> --privsep 0`
  (two separate arguments, not `user!token`).
- `iso` content always uploads over the PVE HTTP API — no SSH, no resume. For a
  slow link use `mise run push-image root@<pve-host>` (rsync, resumable) plus
  `upload_image = false`.
- `disk[0].file_id` is in `lifecycle.ignore_changes`, so rebuilding the image does
  not recreate running VMs. Node changes ship via `deploy`, never Terraform.
- **node-exporter needs TCP 9100 open on every node.** It runs with
  `hostNetwork`, so Prometheus scrapes it at `<node-ip>:9100` and the packet
  arrives over flannel, not loopback — the NixOS firewall drops it and *every*
  node target goes DOWN at once. `nix/modules/monitoring.nix` opens it, which
  means adding monitoring to a node is a `deploy`, not just a Flux reconcile.
  The symptom reads like a broken exporter; it is the host firewall.
- **Plumbing a package set into `specialArgs` changes nothing on its own.**
  `flake.nix` passed `unstable` to every node, with a comment explaining that
  tailscale comes from it because 25.05's 1.82.5 is vulnerable — but no module
  ever took the argument or set `services.tailscale.package`, so all six nodes
  quietly ran 1.82.5 until the admin console flagged them. Docs describing a fix
  are not the fix. The check is an eval, not a grep:
  `./scripts/nix.sh 'nix eval --raw ".#nixosConfigurations.k3s-server-1.config.services.tailscale.package.version"'`
- **Renaming the Grafana admin in the UI silently breaks provisioning reloads.**
  The sidecars write dashboards and datasources into an emptyDir and then POST
  `/api/admin/provisioning/*/reload`, authenticating as `admin-user` from
  `grafana-admin.sops.yaml`. Grafana reads `GF_SECURITY_ADMIN_USER` only when it
  first creates its DB, so a rename in the UI leaves the Secret stale and every
  reload 401s with `no user found: user not found` — visible only in the Grafana
  container log, never in Flux, and the symptom is "my new datasource never
  shows up" until something restarts the pod. Fix by changing `admin-user` in
  the secret, not by renaming the user back.
- **Loki's `retention_period` does nothing without `compactor.retention_enabled`.**
  Set one without the other and chunks are never deleted: logs look like they are
  being aged out because queries stop returning them, while the R2 bucket grows
  forever. Both live in `apps/base/loki/helmrelease.yaml`.
- **Enabling `--ssh` makes the policy file load-bearing for SSH.** tailscaled
  intercepts port 22 on the tailnet address unconditionally once the flag is
  set, and if no `ssh` rule matches it **refuses** the connection rather than
  falling through to sshd. So turning it on without the matching rule is
  strictly worse than leaving it off: it breaks tailnet SSH that used to work.
- **`Connection refused` on a tailnet address does not mean "firewalled".**
  `00-edge-compute`'s `default.nix` sets `trustedInterfaces = [ "tailscale0" ]`,
  so every port is accepted on that interface regardless of `allowedTCPPorts`
  and the kernel RSTs anything with no listener. A closed port and a port whose
  daemon has died look identical, and both look nothing like a dropped packet —
  an OCI security-list removal times out instead. Probing a port nothing has
  ever served (`/dev/tcp/<ip>/9999`) tells you which of the two you are in:
  refused there means the interface is wide open and the daemon is simply gone.
- **MagicDNS and HTTPS Certificates must be on in the tailnet admin console**
  (DNS page) or the operator has no cert to fetch and the Ingress never goes
  ready. Same class of one-time manual step as approving the subnet route —
  nothing in this repo can do it.
- **`apps/base/tailscale-operator/oauth.sops.yaml` ships with placeholders.**
  It is encrypted, so the placeholder is not visible in a diff; the operator
  simply fails to authenticate until it is filled in with
  `mise exec -- sops base/tailscale-operator/oauth.sops.yaml`.
- **`mise run sops-encrypt <file>` does not receive its argument** — it fails with
  `bash: line 2: 1: usage: mise run sops-encrypt <file>`, and `--` does not help.
  Same shape in `sops-edit`. Until the tasks are fixed, encrypt with
  `cd apps && mise exec -- sops --encrypt --in-place <file>`; `SOPS_AGE_KEY_FILE`
  is already exported by `apps/mise.toml`, and encryption only needs the public
  key in `.sops.yaml` anyway.
