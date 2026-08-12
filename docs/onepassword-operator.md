# 1Password operator

`apps/base/onepassword/` runs the 1Password Kubernetes operator so a Secret can
be declared as a pointer to a vault item instead of an encrypted blob in git.
It does not replace SOPS — see "Which one to use" below.

## What is deployed

The `connect` chart (2.4.1, operator 1.12.0) from
`https://1password.github.io/connect-helm-charts`, with the Connect server
turned off:

```yaml
connect:
  create: false
operator:
  create: true
  authMethod: service-account
```

So the cluster runs one `onepassword-connect-operator` Deployment and nothing
else. The chart's other half — `connect-api` and `connect-sync`, a self-hosted
copy of the vault data reached over HTTP — is the alternative auth path and is
deliberately unused. Connect needs two bootstrap secrets
(`1password-credentials.json` plus a Connect token) instead of one, and keeps a
second copy of the vault contents inside the cluster. The service account token
is a single credential and the operator calls 1password.com directly.

The tradeoff to know: with no Connect server there is no local cache. If
1password.com is unreachable the operator cannot refresh items — already-created
Kubernetes Secrets keep working, new ones do not appear.

`watchNamespace: []` means all namespaces, which is what makes the chart create
a ClusterRole rather than per-namespace RoleBindings.

## The token

`token.sops.yaml` holds the service account token, SOPS-encrypted to the same
age key as everything else in `apps/`. The chart can render this Secret itself
from `operator.serviceAccountToken.value`, which is why that value is left
unset: a value in a HelmRelease is plaintext in git.

It ships with the placeholder `ops_REPLACE_ME`. Put the real token in before
this reaches the cluster:

```bash
cd apps
mise run sops-edit base/onepassword/token.sops.yaml
```

The token comes from a 1Password service account (1Password → Developer →
Service Accounts) granted **read** access to the vaults the cluster needs, and
nothing else. Service account tokens expire; the operator starts failing to
refresh items when it does, so rotation is the same `sops-edit` and a
`kubectl -n onepassword rollout restart deploy/onepassword-connect-operator`.

## Using it

A Secret becomes a `OnePasswordItem`, which the operator resolves into a real
Secret of the same name:

```yaml
apiVersion: onepassword.com/v1
kind: OnePasswordItem
metadata:
  name: lastfm-api
  namespace: lastfm
spec:
  itemPath: "vaults/kubernetes/items/lastfm-api"
```

Every field on the vault item becomes a key in the Secret, and the Secret takes
the name of the CR — not of the item — so pointing a CR at an item does not
require touching the workload that reads it.

A field label that is already a valid ConfigMap key (`[-._a-zA-Z0-9]+`) is used
**verbatim**, case and all: a field labelled `api-key` gives the key `api-key`.
Only invalid labels are rewritten, and every run of invalid characters becomes a
`-`, so `API Key` arrives as `API-Key` rather than `api_key`. Label the field
with the key the workload already expects and nothing else has to change.
`apps/base/lastfm-now-playing/` is the worked example: the deployment still asks
for `secretKeyRef: {name: lastfm-api-key, key: api-key}`, and the only change was
swapping the SOPS Secret for a `OnePasswordItem` of the same name.

**The CRD and any `OnePasswordItem` need separate Flux Kustomizations.** The CRD
arrives with this HelmRelease, so a CR in `apps/base/onepassword/` would fail
the dry-run with `no matches for kind "OnePasswordItem"`. Put CRs with the app
that consumes them, and add `dependsOn: [onepassword]`.

`pollingInterval: 600` is how long a rotated vault item takes to reach the
cluster. `autoRestart: false` means a refreshed Secret does not roll the
workloads holding it — a pod reading its Secret through an env var keeps the old
value until it restarts. Turn it on per item with the
`operator.1password.io/auto-restart: "true"` annotation rather than globally.

## Which one to use

SOPS stays the default. It is the only thing that works during a rebuild:
`sops-age` is created by hand and Flux decrypts from git, whereas the operator
is itself a workload that needs its own SOPS secret first. Anything the cluster
needs in order to come up — the Cloudflare tunnel token, the tailscale OAuth
credentials, the CNPG backup credentials — belongs in a `*.sops.yaml`.

The operator is worth it for secrets that also live in 1Password for a human to
use, or that rotate often enough that editing an encrypted file is friction.
That is a pull rather than a push: the vault becomes the source of truth and git
holds only the item path.
