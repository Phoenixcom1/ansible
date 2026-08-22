# Immich Snapshot Backup

Creates a consistent TrueNAS snapshot of Immich media for replication.

The scheduled job:

1. Stops the Immich writer services.
2. Writes a PostgreSQL custom-format dump to
   `/srv/containers/immich-data/immich-postgres.dump`.
3. Uses TrueNAS JSON-RPC 2.0 over WebSocket to create a snapshot named
   `immich-backup-<UTC timestamp>` of
   `tank/apps/immich-data`.
4. Starts the Immich stack even when the dump or snapshot request fails.

Snapshots are created daily at 01:00 by default. TrueNAS owns snapshot
retention and replication; this role never prunes snapshots.

The role requires `truenas_api_token` in vaulted inventory. Its timer is
installed only when `immich-snapshot-backup` is included in the playbook.

Run a backup immediately:

```sh
sudo systemctl start immich-snapshot-backup.service
sudo journalctl -u immich-snapshot-backup.service -n 100 --no-pager
```

Check the scheduled run:

```sh
systemctl list-timers immich-snapshot-backup.timer
```
