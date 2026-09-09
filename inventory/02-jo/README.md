# Jo Inventory

The Jo environment is loaded with `-i inventory/02-jo`.

## Layout

- `hosts.yml`: host addresses, groups, and SSH connection settings.
- `group_vars/proxmox.yml`: Proxmox ACME configuration.
- `group_vars/all/secrets.yml`: local vaulted secrets; ignored by Git.
- `host_vars/podman-vm/services.yml`: service, domain, and certificate settings.
- `host_vars/podman-vm/storage.yml`: TrueNAS mounts and datasets.
- `host_vars/podman-vm/backups.yml`: Restic and TrueNAS replication settings.

## Dry run

```bash
ansible-playbook 02-jo-setup.yml \
  -i inventory/02-jo \
  --limit podman-vm \
  --vault-id jo@prompt \
  --check \
  --diff \
  -vv
```

## Apply changes

```bash
ansible-playbook 02-jo-setup.yml \
  -i inventory/02-jo \
  --limit podman-vm \
  --vault-id jo@prompt \
  -vv
```

Replace all temporary secret placeholders in `group_vars/all/secrets.yml` with
real vaulted values before applying changes.
