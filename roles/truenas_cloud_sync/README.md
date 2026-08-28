# TrueNAS Cloud Sync Role

Creates native TrueNAS Cloud Sync push tasks through the JSON-RPC API. It
supports multiple named destinations and selects datasets per job. Each
dataset/destination pair is a separate task.

Remote encryption and the TrueNAS `snapshot` option are enabled by default.
Encryption passwords and salts should be vaulted values. Destination
credentials are passed to the TrueNAS keychain and can also contain vaulted
attributes.

```yaml
truenas_cloud_sync_enabled: true
truenas_cloud_sync_destinations:
  - name: remote-webdav
    credential:
      name: remote-webdav
      provider:
        type: WEBDAV
        url: "https://backup.example.invalid:5006/backup"
        user: "{{ remote_backup_username }}"
        pass: "{{ remote_backup_password }}"
truenas_cloud_sync_jobs:
  - name: critical
    datasets:
      - /mnt/tank/apps/vaultwarden
      - /mnt/tank/apps/nextcloud-data
    destinations:
      - remote-webdav
    folder: truenas/podman-vm-pve0
    encryption_password: "{{ vaulted_cloud_sync_encryption_password }}"
    encryption_salt: "{{ vaulted_cloud_sync_encryption_salt }}"
    schedule:
      minute: "30"
      hour: "2"
      dom: "*"
      month: "*"
      dow: "*"
```

For SFTP, use `type: SFTP` with `host`, `port`, `user`, `pass`, and
`private_key: null` for password authentication. `SSH_CREDENTIALS` is a
separate key-based credential type used by replication and is not suitable for
Cloud Sync password authentication. Provider schemas can vary by TrueNAS
release, so verify them against the target UI/API version.
