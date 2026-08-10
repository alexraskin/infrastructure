# apps/base/tailscale-operator/ — the tailnet IngressClass

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

## Gotchas

- **MagicDNS and HTTPS Certificates must be on in the tailnet admin console**
  (DNS page) or the operator has no cert to fetch and the Ingress never goes
  ready. Same class of one-time manual step as approving the subnet route —
  nothing in this repo can do it.
- **`apps/base/tailscale-operator/oauth.sops.yaml` ships with placeholders.**
  It is encrypted, so the placeholder is not visible in a diff; the operator
  simply fails to authenticate until it is filled in with
  `mise exec -- sops base/tailscale-operator/oauth.sops.yaml`.
