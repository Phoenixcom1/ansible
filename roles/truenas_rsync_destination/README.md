# TrueNAS rsync destination role

Creates one or more narrowly scoped rsync-over-SSH destinations for backup clients. The role delegates TrueNAS API changes to `truenas_jsonrpc_provision` and can optionally configure `truenas_snapshot_retention`.

## Resources

- One independent generic ZFS dataset per configured client.
- Any explicitly declared parent datasets needed before client datasets.
- One dedicated group and non-login user per configured client.
- Recursive `0700` ownership for each backup account.
- One SSH-capable account per configured client for rsync remote-shell mode.
- The backup dataset itself is the account home directory.
- SSH password authentication enabled for each dedicated backup account.
- Each dedicated backup group added to the SSH service Allow Groups list.
- SSH service enabled on TrueNAS.
- Optional periodic snapshots.

No SMB, NFS, or rsync daemon share is created. Each destination has an independent account and dataset. The role requires an explicit `allowed_hosts` list, which must also be enforced with a TrueNAS or network firewall rule because TrueNAS user provisioning does not implement per-user source-address restrictions.

## Configuration

Place the TrueNAS API token and each client password/address in vaulted or ignored inventory:

```yaml
truenas_rsync_destinations:
  - name: synology-home
    dataset: tank/backups/synology-home
    export_path: /mnt/tank/backups/synology-home
    username: synology-home
    password: !vault |
      $ANSIBLE_VAULT;1.2;AES256;lab
      ...
    allowed_hosts:
      - 192.168.1.50
```

Parent datasets must already exist or be declared explicitly, in order from
the pool downward. For example, the test dataset above needs:

```yaml
truenas_rsync_destination_dataset_parents:
  - tank/backups
```

The role creates these parents as generic datasets before creating client
datasets. The pool itself, such as `tank`, is expected to already exist.

Add another independent client by adding another entry:

```yaml
  - name: linux-server
  dataset: tank/backups/linux-server
  export_path: /mnt/tank/backups/linux-server
  username: linux-server
  password: "{{ vaulted_linux_backup_password }}"
  allowed_hosts:
    - 192.168.1.60
```

Use a CIDR only when a client address is not fixed. Add a firewall rule allowing
SSH traffic only from each client.

## Synology Hyper Backup how-to

After applying the role, create an rsync task in Synology Hyper Backup with
these settings:

1. Choose **rsync** as the task type, not single-version mode.
2. Choose **rsync-compatible server** as the server type.
3. Enter the TrueNAS IP address or hostname and port `22`.
4. Enable **Transfer encryption**.
5. Enter the dedicated `username` and password from the destination entry.
6. Set **Backup module** to the full mount path from `export_path`, for
   example `/mnt/tank/backups/synology-test`.
7. Set **Directory** to the remote directory Hyper Backup should create inside
   the dataset, for example `Datenbunker`.
8. If Hyper Backup shows **Block module**, enable it. This is a Synology-side
   option; the TrueNAS role cannot configure it.
9. Click **Next** and configure the remaining backup options.

The absolute path in **Backup module** is important: it selects rsync
remote-shell mode over SSH. Do not enter a daemon module name. When testing the
settings, do not use the arrow beside **Backup module** to browse or validate
the path. Synology may show a misleading “couldn't connect” error when the
arrow is clicked even though the configuration is valid; enter the absolute
path manually and continue with **Next**.

For the lab test configured in this repository, use:

```text
Server: 192.168.1.252
Port: 22
Username: synology-test
Backup module: /mnt/tank/backups/synology-test
Directory: Datenbunker
```

Snapshot policies are opt-in:

```yaml
truenas_rsync_destinations:
  - name: synology-home
    dataset: tank/backups/synology-home
    export_path: /mnt/tank/backups/synology-home
    username: synology-home
    password: "{{ vaulted_synology_password }}"
    allowed_hosts: [192.168.1.50]
    snapshot_retention:
      daily: 14
      weekly: 8
      monthly: 12
```

## Enabling

Add the role to a play targeting the host where the TrueNAS API is reachable, for example in `fedora_base.yml`:

```yaml
- truenas_rsync_destination
```

Run with the normal inventory and vault options:

```bash
ansible-playbook --vault-id lab@prompt -i inventory/01-lab.yml \
  -i inventory/01-lab.secrets.yml fedora_base.yml
```

For each backup client, select an rsync-compatible server, enter the TrueNAS address, enter that client’s absolute `export_path` as the Backup module, and use its dedicated username and password. Enable transfer encryption if required by the Synology task.

The role does not remove existing users, ACLs, or rsync modules. Dataset encryption is not enabled by default; TrueNAS encryption must be decided when a new dataset is created and its unlock/reboot procedure tested separately. Remote-shell accounts necessarily have a valid shell so SSH can invoke rsync; they should not be reused for interactive administration. Password authentication is enabled only for these dedicated accounts and should be restricted to the Synology address with a firewall rule. The dataset is used as the user home, and its owner/group are set to the dedicated account with `0700` permissions, matching the TrueNAS SSH rsync setup requirements.
