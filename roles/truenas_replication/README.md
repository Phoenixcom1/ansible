# TrueNAS Replication Role

Configures an SSH push replication task from a source TrueNAS to a destination TrueNAS through the TrueNAS WebSocket JSON-RPC API.

The role is disabled by default. Enable it for a host with:

```yaml
truenas_replication_enabled: true
```

## Replication Workflow

The source TrueNAS is the SSH client and pushes snapshots to the destination TrueNAS:

1. Ansible asks the source TrueNAS to generate or reuse an SSH keypair in its keychain. TrueNAS 25.10's `keychaincredential.generate_ssh_key_pair` API does not expose a key-algorithm parameter, so the generated key type is determined by TrueNAS.
2. The source TrueNAS keeps the private key in its keychain. The private key is never read by Ansible and is never written to inventory.
3. The JSON-RPC helper writes only the public key to `truenas_replication_public_key_path` on the managed host and asks the source TrueNAS to discover the destination host key through `keychaincredential.remote_ssh_host_key_scan`.
4. Ansible reads that public key and sends it to the destination TrueNAS API.
5. The destination dataset and `truenas_replication_remote_username` are created or updated. The public key is installed on that user.
6. Ansible configures an SSH credential on the source TrueNAS that references the source keypair, destination user, destination address, and destination host key.
7. Ansible creates or updates the source replication task. The source TrueNAS then connects to the destination over SSH and pushes the replication stream.

The task selects snapshots whose names match `truenas_replication_snapshot_name_regex` and runs according to `truenas_replication_schedule` in the source TrueNAS system timezone. The defaults match snapshots created by the `truenas_snapshot_retention` role (`ansible-*`) and run replication daily at 03:00, after the default daily snapshot time of 00:10.

The destination user is intended only for replication. It has no sudo access and is not enabled for SMB. The role configures filesystem permissions on the destination dataset for this user. TrueNAS requires a non-empty password when creating a user. Set `truenas_replication_remote_password` in vaulted inventory if the account should have a known password; otherwise the role generates a random bootstrap password. The generated password is not reported or persisted by Ansible. SSH keys are used for replication, and the role does not change the password of an existing user, so an administrator can change it directly on TrueNAS without Ansible resetting it.

The replication task defaults to `readonly: IGNORE`. This is required for the delegated non-root receiver because `readonly: SET` requires permission to change the destination dataset property. Set `truenas_replication_readonly: SET` only when the replication user is also allowed to change dataset properties.

### IMPORTANT: manual ZFS delegation required

Before running the replication task, manually delegate the minimum ZFS permissions needed for PUSH replication on the destination TrueNAS. `destroy` is required because this role configures `retention_policy: SOURCE`, so TrueNAS may delete destination snapshots that no longer exist on the source:

```sh
zfs allow <replication-user> mount,create,receive,destroy <destination-dataset>
```

For the configured lab values, run this on the destination TrueNAS as an administrator:

```sh
zfs allow truenas-repl-Enno mount,create,receive,destroy tank/Truenas_Backup_Enno
```

The role intentionally does not automate this command. TrueNAS JSON-RPC does not expose `zfs allow` as a dataset-permission operation, and the replication account must remain non-sudo. Apply delegation again if the destination dataset is recreated or replaced.

The account uses the destination dataset as its home directory by default. TrueNAS requires an SSH-key-enabled user home to be an existing writable path inside a data pool. The role creates the destination dataset before creating the user, then assigns the dataset to the replication user with mode `0700`.

The destination SSH host key is a trust value, not the replication public key. If `truenas_replication_destination_ssh_fingerprint` is empty, the source TrueNAS uses its `keychaincredential.remote_ssh_host_key_scan` API to discover the destination host key. This is TOFU (trust on first use): it is suitable when the initial run takes place on a trusted local network, but it does not protect against interception during that first scan. A verified key can be supplied explicitly when stronger first-run verification is required:

```sh
ssh-keyscan -t rsa <destination-host>
```

Do not replace the host key with an API token or with the source replication public key. The discovered key is passed to the source TrueNAS as `remote_host_key`; it is not the key used to authenticate the replication user.

## Datasets

The role builds `truenas_replication_datasets` from the datasets declared by the existing storage roles. With the current lab inventory, the resulting list is:

```yaml
- tank/apps/nextcloud-data
- tank/apps/immich-data
- tank/apps/podman-backups
```

The values are retrieved as follows:

- `tank/apps/nextcloud-data` comes from each entry in `truenas_nfs_mounts` whose `dataset` attribute is defined.
- `tank/apps/immich-data` comes from `truenas_immich_smb_dataset`, or its default when that variable is not defined.
- `tank/apps/podman-backups` comes from `truenas_smb_backup_dataset`, or its default when that variable is not defined.

The replication role intentionally keeps these application datasets in its default set even when their application roles are temporarily commented out. This prevents an Ansible rerun from dropping existing backup sources or failing to pre-create their destination child datasets. Remove a dataset only by explicitly overriding `truenas_replication_datasets`.

The list is deduplicated. Datasets such as `tank/Documents` or `tank/User` are not included unless they are explicitly added to the variables above.

Source dataset management is additive for an existing replication task. The role preserves datasets already present in the task and adds newly configured datasets, so temporarily commenting out a dataset-owning role does not remove that dataset from replication. A newly created task uses the configured dataset list.

The destination root dataset is created by this role and is configurable through `truenas_replication_destination_dataset`. Replication creates the source-derived child datasets so encrypted source datasets are received with compatible encryption metadata instead of being placed into precreated unencrypted datasets. For example, `tank/apps/immich-data` is received into `<destination-dataset>/immich-data`.

```yaml
truenas_replication_destination_dataset: "<pool>/<dataset>"
```

Only the configured destination dataset is managed. Other datasets on the destination are not referenced or modified.

## Configuration

Example inventory configuration:

```yaml
<managed-host>:
  truenas_replication_enabled: true
  truenas_replication_destination_api_url: "https://<destination-host>"
  truenas_replication_destination_api_validate_certs: false
  truenas_replication_destination_dataset: "<pool>/<dataset>"
  truenas_replication_remote_username: "truenas-repl-<source-host>"
```

The source API token is read from the existing `truenas_api_token` variable. Store the destination API token as `truenas_replication_destination_api_token` in the ignored vaulted inventory, for example:

Set `truenas_replication_destination_api_validate_certs: false` only when the destination API uses a self-signed or otherwise untrusted certificate. Prefer a trusted certificate in production and leave validation enabled.

```yaml
all:
  hosts:
    podman-vm-pve0:
      truenas_api_token: !vault |
        ...
      truenas_replication_destination_api_token: !vault |
        ...
      truenas_replication_remote_password: !vault |
        ...
```

The source and destination tokens need permissions to manage the resources used by their respective API calls: datasets, users, keychain credentials, replication tasks, and filesystem permissions.

## Main Defaults

| Variable                                          | Default                               |
| ------------------------------------------------- | ------------------------------------- |
| `truenas_replication_enabled`                     | `false`                               |
| `truenas_replication_destination_api_url`         | destination API URL                   |
| `truenas_replication_destination_dataset`         | destination dataset                   |
| `truenas_replication_remote_username`             | `truenas-replication`                 |
| `truenas_replication_task_name`                   | replication task name                 |
| `truenas_replication_keypair_name`                | source keypair name                   |
| `truenas_replication_public_key_path`             | `/run/truenas-replication-public-key` |
| `truenas_replication_destination_ssh_fingerprint` | empty; discovered automatically       |
| `truenas_replication_snapshot_name_regex`         | `^ansible-.*`                         |
| `truenas_replication_readonly`                    | `IGNORE`                              |
| `truenas_replication_schedule`                    | daily at 03:00                        |

## Deployment

Run the playbook with both the regular and vaulted inventory files:

```sh
ansible-playbook --vault-id lab@prompt \
  -i inventory/01-lab.yml \
  -i inventory/01-lab.secrets.yml \
  fedora_base.yml
```

The role creates or updates only the replication task named by `truenas_replication_task_name`.
