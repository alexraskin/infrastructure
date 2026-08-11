# apps/base/cnpg/ — CloudNativePG

The operator (chart `0.29.0` = operator `1.30.0`) plus one `Cluster`: three
Postgres instances, one per db node. That is what the three tainted db nodes and
the three `db-local` PVs exist for.

## Two Kustomizations, not one

`cluster/` is a separate directory with its own Flux Kustomization
(`cnpg-cluster`, `dependsOn: cnpg`) purely because the `Cluster` CRD arrives
with the operator's chart. In one Kustomization, Flux server-side dry-runs every
resource in the set before applying any of it, so the `Cluster` fails validation
against an API that does not have the kind yet:

```
Cluster/cnpg-system/postgres dry-run failed: no matches for kind "Cluster" in version "postgresql.cnpg.io/v1"
```

`dependsOn` alone would not fix it — the split has to be at the Kustomization
boundary. Same shape as `tailscale-operator` / `tailscale-router`.

## Scheduling is the point

The db nodes carry `dedicated=database:NoSchedule`, set by kubelet in
`terraform/proxmox/talos.tf`, and the label `dedicated=database`. A pod needs
**both** a toleration and the selector — the taint alone would let anything
tolerating it land there, the label alone would not keep anything else out. The
`Cluster` sets both under `spec.affinity`, which is CNPG's own block, not a raw
pod spec.

`enablePodAntiAffinity` with `topologyKey: kubernetes.io/hostname` and
`podAntiAffinityType: required` is what keeps the three instances on three
different nodes. Without it two could share a node, and a node failure would
take out two thirds of the cluster.

## Storage

`storageClass: db-local`, 90Gi, which is exactly the size of the PVs in
`apps/base/local-path/pv.yaml`. Those are `local` PVs on the db nodes' second
disk, mounted by Talos at `/var/mnt/db`.

**Those PVs deliberately have no `claimRef`**, where the `local-path` ones do.
CNPG names its claims `postgres-1`..`postgres-3` but does not decide which
instance lands on which node; reserving a specific volume for a specific claim
would deadlock as soon as the scheduler disagreed. The three are identical, so
first-come binding is right.

## No backups yet, and what that means

`spec.backup` is unset. Storage is node-local, so:

- losing one db node loses that instance's copy; the other two carry on and CNPG
  rebuilds the third from the primary. The *cluster* survives.
- losing the data on all three, or a bad `DROP`, is unrecoverable. There is no
  point-in-time restore.

The fix when this holds anything worth keeping is `spec.backup.barmanObjectStore`
against R2 — the account already holds Loki's chunks and the Terraform state, so
it is a bucket and a token, not a new dependency.

## Consumers get their own role and database

`initdb` makes `app`, but nothing uses it. Each consumer instead gets a login
role (`spec.managed.roles` on the Cluster) and a database owned by it (a
`Database` CR, which is CNPG's declarative form — the CRD ships with the chart).
Today that is `gatus`, in `cluster/gatus-database.yaml`.

The password is the awkward part, because two namespaces need it: CNPG reads a
**basic-auth** Secret in `cnpg-system` — the `username` key must equal the role
name or the operator rejects it — and the consumer reads its own copy to build a
connection URL. `cluster/gatus-db.sops.yaml` holds **both Secrets in one
encrypted file** so they cannot drift, which is why the `cnpg-cluster`
Kustomization has a `decryption` block and why `gatus` `dependsOn` it.

Generate the password alphanumeric-only. It goes into a `postgres://` URL, and
anything needing percent-encoding breaks it silently.

## Bootstrap

`initdb` creates database `app` owned by `app`. The operator generates the
credentials into a Secret named `postgres-app` — nothing to commit, and nothing
in SOPS for this. An application consumes it with
`valueFrom.secretKeyRef: {name: postgres-app, key: uri}`.

Connect through the Services the operator maintains, never a pod IP:
`postgres-rw` (primary, writes), `postgres-ro` (replicas), `postgres-r` (any).
Failover repoints `-rw` on its own; `primaryUpdateStrategy: unsupervised` lets
the operator do that without a human.

## Metrics

`monitoring.enablePodMonitor: true` on the Cluster and `podMonitorEnabled` on
the operator. No release label is needed — the monitoring stack sets
`podMonitorSelectorNilUsesHelmValues: false`, so Prometheus picks up PodMonitors
from anywhere. There is a CNPG dashboard upstream; drop its JSON into
`apps/base/monitoring/dashboards/` to get it, same as the Plex one.
