# TrueNAS Snapshot Retention

Manages native TrueNAS periodic snapshot tasks through the JSON-RPC WebSocket
API. It only creates or updates tasks whose naming schema starts with
`ansible-`; manually managed TrueNAS tasks are left unchanged.

Each retention cadence is a separate TrueNAS task. Snapshots run at:

- hourly: minute 5
- daily: 00:10
- weekly: Monday 00:15
- monthly: day 1 at 00:20

Configure a policy in a dataset-owning role or inventory:

```yaml
truenas_snapshot_retention_policies:
  - name: example
    dataset: tank/apps/example-data
    retention:
      hourly: 24
      daily: 14
      weekly: 8
      monthly: 12
```

Retention values are positive counts in the corresponding unit. TrueNAS
deletes snapshots automatically after that lifetime. When cadences overlap,
TrueNAS retains the shared snapshot until the longest applicable lifetime
expires.

Defaults provided by the application dataset roles:

- Immich: 30 daily and 12 monthly snapshots.
- Nextcloud: 24 hourly, 14 daily, 8 weekly, and 12 monthly snapshots.
- Restic backup dataset: 30 daily and 12 monthly snapshots.
