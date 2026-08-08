# Nextcloud Container Role

Deploys Nextcloud, PostgreSQL, and Redis on a Fedora-compatible host with rootless Podman Quadlets. Nginx on the host terminates TLS and proxies to Nextcloud on loopback.

## Components

- `nextcloud-postgres.service`: PostgreSQL database
- `nextcloud-redis.service`: Redis cache and transactional file locking
- `nextcloud.service`: Nextcloud web application
- `nextcloud-eurooffice.service`: optional EuroOffice document server
- `nextcloud-stack.target`: systemd user target for the stack

The Nextcloud service listens on `127.0.0.1:{{ nextcloud_port }}`. The host reverse proxy publishes the configured Nextcloud domain.

## Storage

By default, Nextcloud stores data in `{{ nextcloud_html_dir }}/data`. A host can instead use a dedicated NFS mount:

```yaml
nextcloud_data_external: true
nextcloud_data_dir: "/srv/containers/nextcloud-data"
```

When external data is enabled, the Quadlet requires the mount before startup and mounts it at `/var/www/html/data`.

The container runs rootless as `podman`, while the Nextcloud process runs as `www-data` (`33:33`). For NFS-backed data, the role uses:

```yaml
nextcloud_external_data_userns: "keep-id:uid=33,gid=33"
```

This maps container `www-data` to the host `podman` identity. The Quadlet also grants only `CAP_NET_BIND_SERVICE`, allowing Apache to bind its internal port `80` under this mapping.

Set `nextcloud_data_check_container_write: true` to run a disposable `www-data` container that verifies write access to the external data mount before the stack starts.

## TrueNAS NFS Storage

`fedora_base.yml` runs these roles before `deploy_nextcloud_container`:

1. `truenas_nfs_provision`: manages datasets, NFS exports, and dataset permissions through the TrueNAS REST API.
2. `truenas_nfs_client`: installs NFS utilities and mounts the declared exports on the Fedora host.

Define the storage per host or customer inventory:

```yaml
truenas_nfs_server: "truenas.{{ dns_search_domains | first }}"
truenas_nfs_mounts:
  - dataset: "tank/apps/nextcloud-data"
    export_path: "/mnt/tank/apps/nextcloud-data"
    path: "/srv/containers/nextcloud-data"

nextcloud_data_external: true
nextcloud_data_dir: "/srv/containers/nextcloud-data"
```

### Optional Dataset Encryption

TrueNAS encryption is applied only when a dataset is created; an existing
dataset cannot be encrypted in place. To create a new passphrase-encrypted
dataset, opt in on that mount and provide
`truenas_nfs_dataset_encryption_passphrase` through the ignored vaulted
inventory, or set `TRUENAS_NFS_DATASET_ENCRYPTION_PASSPHRASE` on the Ansible
controller:

```yaml
truenas_nfs_mounts:
  - dataset: "tank/apps/nextcloud-data-encrypted"
    export_path: "/mnt/tank/apps/nextcloud-data-encrypted"
    path: "/srv/containers/nextcloud-data"
    encrypted: true
```

TrueNAS does not store this passphrase. After a TrueNAS restart, unlock the
dataset manually before starting services that use its NFS export. With the
current mount settings, Nextcloud remains unavailable until the dataset is
unlocked and its NFS mount becomes available.

The API token needs permission to create datasets and NFS shares, manage the NFS service, and set filesystem attributes. For dedicated container-data datasets, the provisioner sets the dataset owner/group to the Fedora `podman` UID/GID and mode `0770`. No matching TrueNAS user is required because NFS authorizes the numeric IDs supplied by the Fedora host.

Keep `truenas_api_token` in an ignored companion inventory such as `inventory/01-lab.secrets.yml`, or supply it through `TRUENAS_API_TOKEN`. Add this pattern to `.gitignore`:

```gitignore
inventory/*.secrets.yml
```

The companion inventory contains the secrets for the matching host. The
`nextcloud_db_password` value is used to initialize a new PostgreSQL data
directory; alternatively, provide it through `NEXTCLOUD_DB_PASSWORD` on the
Ansible controller.

```yaml
all:
  hosts:
    podman-vm-pve0:
      truenas_api_token: !vault |
        $ANSIBLE_VAULT;1.2;AES256;lab
        ...
      nextcloud_db_password: !vault |
        $ANSIBLE_VAULT;1.2;AES256;lab
        ...
      truenas_nfs_dataset_encryption_passphrase: !vault |
        $ANSIBLE_VAULT;1.2;AES256;lab
        ...
```

Generate the vaulted value without exposing it in shell history:

```bash
ansible-vault encrypt_string --vault-id lab@prompt \
  --name nextcloud_db_password --prompt
```

Enter the existing `lab` vault password when prompted, then enter the database
password to encrypt. Copy the resulting `nextcloud_db_password` block into
`inventory/01-lab.secrets.yml` under the target host.

Deploy with both inventory files:

```bash
ansible-playbook --vault-id lab@prompt \
  -i inventory/01-lab.yml \
  -i inventory/01-lab.secrets.yml \
  fedora_base.yml \
  --limit podman-vm-pve0
```

## Redis

Redis provides the distributed cache and transactional file locking configuration mounted into Nextcloud as `redis.config.php`. It is internal to `nextcloud_net` and has no published host port.

Container images use `Pull=missing` by default. This avoids Docker Hub manifest requests on every restart. Pull image updates explicitly or use Podman auto-update. If Docker Hub rate limits unauthenticated pulls, authenticate as the rootless service user:

```bash
sudo -iu podman podman login docker.io
```

## Credentials

`nextcloud_admin_password` is only used during the first Nextcloud installation.
Change that initial password when signing in for the first time. The database
password must be supplied as `nextcloud_db_password` through the ignored vaulted
inventory shown above, or as `NEXTCLOUD_DB_PASSWORD` on the Ansible controller.

### Rotate the database password

Changing `nextcloud_db_password` alone does not rotate an existing PostgreSQL
role. Back up the database first, then update the password in Nextcloud while it
can still connect and immediately update PostgreSQL interactively:

```bash
sudo -u podman XDG_RUNTIME_DIR=/run/user/$(id -u podman) \
  podman exec -u www-data nextcloud php occ config:system:set dbpassword --value='NEW_PASSWORD'

sudo -u podman XDG_RUNTIME_DIR=/run/user/$(id -u podman) \
  podman exec -it --user postgres nextcloud-postgres \
  psql -d postgres -c '\password nextcloud'
```

Enter the same new value when prompted, update `nextcloud_db_password` in the
vaulted inventory, and run the playbook. Do not leave `NEW_PASSWORD` in shell
history; use a securely generated value.

## EuroOffice

Enable EuroOffice with:

```yaml
nextcloud_enable_eurooffice: true
nextcloud_eurooffice_image: "ghcr.io/euro-office/documentserver:latest"
nextcloud_eurooffice_domain: "eurooffice.example.com"
```

The role enables the `eurooffice` Nextcloud connector and configures its `DocumentServerUrl`, `jwt_secret`, and `jwt_header` settings. JWT uses the `Authorization` header. Supply a persistent 32-character secret with `nextcloud_eurooffice_jwt_secret` or `NEXTCLOUD_EUROOFFICE_JWT_SECRET`; otherwise a new secret is generated during deployment.

## Core Variables

```yaml
nextcloud_domain: "cloud.example.com"
nextcloud_port: 8080
nextcloud_image: "docker.io/nextcloud:latest"
postgres_image: "docker.io/postgres:16-alpine"
nextcloud_redis_image: "docker.io/redis:7-alpine"
nextcloud_pull_policy: "missing"
nextcloud_redis_pull_policy: "missing"

nextcloud_trusted_proxies:
  - "10.89.0.0/16"
nextcloud_maintenance_window_start: 1
nextcloud_default_phone_region: "DE"
```

`nextcloud_trusted_proxies` must match the network from which the reverse proxy reaches the container.

## Stack Management

Run user-scoped systemd commands as `podman`:

```bash
sudo -u podman XDG_RUNTIME_DIR=/run/user/$(id -u podman) \
  systemctl --user status nextcloud-stack.target

sudo -u podman XDG_RUNTIME_DIR=/run/user/$(id -u podman) \
  journalctl --user -u nextcloud.service -n 100 --no-pager
```

## Reverse Proxy

Proxy to `http://127.0.0.1:{{ nextcloud_port }}` and pass the forwarded host, protocol, and client address headers. The `nginx_reverse_proxy` role manages the deployed nginx configuration and TLS certificate paths.
