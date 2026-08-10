# Restic Restore Role

Prepares a host to restore an existing Restic repository. It installs Restic and
CIFS support, mounts the backup NAS, validates the existing password file, and
verifies repository access.

It never initializes a repository, generates a password, starts a backup timer,
or restores files automatically. When `restic_restore_snapshot` is supplied, it
prints the exact restore command for an operator to run manually.

## Shared Configuration

The role uses the same `restic_repository`, `restic_password_file`, and
`restic_nas_*` variables as `restic-backup`. The restore host must receive the
same `/root/.restic-password` as the backup host. The role can copy
`.smb_restic_creds` from the controller, but it deliberately refuses to create a
new repository password.

Copy the existing password from the backup host to the restore host without
writing it to the controller filesystem:

```sh
ssh ansible@source-nas 'sudo cat /root/.restic-password' \
  | ssh ansible@destination-nas \
      'sudo install -o root -g root -m 0600 /dev/stdin /root/.restic-password'
```

Confirm its owner and permissions on the restore host:

```sh
ssh ansible@destination-nas \
  'sudo stat -c "%U:%G %a %n" /root/.restic-password'
```

## Usage

Enable the opt-in role for one run:

```sh
ansible-playbook --vault-id lab@prompt \
  -i inventory/01-lab.yml \
  -i inventory/01-lab.secrets.yml \
  fedora_base.yml --limit podman-vm-pve0 \
  -e restic_restore_enabled=true
```

List all available snapshots before selecting one to restore:

```sh
sudo RESTIC_PASSWORD_FILE=/root/.restic-password \
  restic -r /mnt/backup/restic-podman snapshots
```

List only Immich snapshots with verbose progress when repository access appears
to stall:

```sh
sudo RESTIC_PASSWORD_FILE=/root/.restic-password \
  restic -r /mnt/backup/restic-podman snapshots --tag immich -vv
```

To print a specific command without executing it:

```sh
ansible-playbook --vault-id lab@prompt \
  -i inventory/01-lab.yml \
  -i inventory/01-lab.secrets.yml \
  fedora_base.yml --limit podman-vm-pve0 \
  -e restic_restore_enabled=true \
  -e restic_restore_snapshot=SNAPSHOT_ID \
  -e restic_restore_target=/var/tmp/immich-restore \
  -e '{"restic_restore_include_paths":["/opt/podman/immich/upload"]}'
```
