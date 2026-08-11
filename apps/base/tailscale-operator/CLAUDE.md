# apps/base/tailscale-operator/ — the tailnet IngressClass

Puts Services on the tailnet from inside the cluster. Since the move to Talos
this is the **only** way anything here reaches the tailnet: the nodes run no
tailscaled of their own, where the k3s nodes were a subnet router advertising
`10.0.200.0/24`. Three things now ride on the operator —

- **Ingress**, giving a Service its own tailnet device with a real LetsEncrypt
  cert (Grafana, the gatus status page).
- **Egress**, an ExternalName Service annotated `tailscale.com/tailnet-ip`,
  which is how gatus probes off-cluster targets (`apps/base/gatus/egress.yaml`).
- **The subnet router**, a `Connector` in `apps/base/tailscale-router/` that
  re-advertises `10.0.200.0/24` so off-LAN kubectl still reaches the VIP.

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

The API-server proxy (`apiServerProxyConfig.mode`) is off. kubectl reaches the
VIP through the Connector's subnet route instead, and enabling the proxy means
ACL grants that map tailnet identities onto cluster RBAC. It is the obvious
alternative if the Connector's circularity — the route into the cluster's subnet
living in the cluster — ever stops being acceptable.

Versions here are the only tailscaled versions in the cluster — the operator and
its proxies run it from container images, and nothing on a Talos node runs it at
all. The stable chart's appVersion is 1.98.9, which the admin console
flags as vulnerable, so `proxyConfig.image.tag` is pinned ahead of the chart at
`v1.102.2`. The operator cannot follow: `tailscale/k8s-operator` has no stable
tag past `v1.98.9` (only `unstable-v1.10x`), so the `talos-operator` device stays
flagged until upstream ships one. Remove the pin when a stable chart carries
1.102.x or later, or it starts holding proxies back instead of pushing them
forward.

## Gotchas

- **MagicDNS and HTTPS Certificates must be on in the tailnet admin console**
  (DNS page) or the operator has no cert to fetch and the Ingress never goes
  ready. Same class of one-time manual step as approving the subnet route —
  nothing in this repo can do it.
- **`apps/base/tailscale-operator/oauth.sops.yaml` ships with placeholders.**
  It is encrypted, so the placeholder is not visible in a diff; the operator
  simply fails to authenticate until it is filled in with
  `mise exec -- sops base/tailscale-operator/oauth.sops.yaml`.
