# sqlites-operator

Kubernetes operator (built with [Bonny](https://hex.pm/packages/bonny))
that owns the durability story for the sqlites service. The control
plane never touches pods, PVCs, or Litestream directly — it creates and
patches `SqliteDatabase` custom resources (via `Sqlites.Infra.Kubernetes`)
and this operator reconciles them.

## Resource model

```yaml
apiVersion: sqlites.supabase.com/v1alpha1
kind: SqliteDatabase
metadata:
  name: db-<database-id>
  namespace: sqlites
spec:
  databaseId: <uuid>          # control-plane database id
  tenantId: <uuid>
  node: <erlang node name>    # placement chosen by the control plane
  backup:
    requestedAt: <iso8601>    # bump to request an on-demand backup
  restore:
    backupId: <id>            # set to request a restore
status:
  backups:                    # reported by the operator
    - id: <id>
      completedAt: <iso8601>
      sizeBytes: <int>
```

## Durability design

- Each data-plane node pod mounts a PVC holding the SQLite files placed
  on that node, and runs a **Litestream sidecar** continuously
  replicating the data directory to object storage.
- On-demand backups (`spec.backup.requestedAt`) become Litestream
  snapshots recorded on `status.backups`.
- Restores (`spec.restore.backupId`) drain the database's writer process
  in the data plane, `litestream restore` the file, and restart it.
- Delete takes a final snapshot and applies the retention policy.

## Status

Scaffold: CRD, operator wiring, controller skeleton, and RBAC rules
compile and are unit-tested, but the Litestream snapshot/restore steps
are `TODO` — they need a real cluster with the sidecar deployed to
verify. Reconcile handlers currently log and update status only.

## Development

```sh
mix deps.get
mix test
mix bonny.gen.manifest   # generate CRD + deployment manifests
```

The operator only starts its watch loop when
`config :sqlites_operator, start_operator: true` (default in `:prod`).
Dev connects via `~/.kube/config`, prod via the in-cluster service
account.
