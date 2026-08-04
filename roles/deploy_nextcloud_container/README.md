# Nextcloud Container Role

Deploys Nextcloud on a Fedora-compatible Podman host using Podman Quadlets and PostgreSQL.

## Features

- Nextcloud web application in a rootless Podman container
- PostgreSQL database container for recommended production deployment
- Separate data, config, apps, and themes volumes
- Optional EuroOffice integration
- Support for external Talk server setup via separate host
- Modern Podman Quadlet + systemd integration

## Architecture

This role creates:

- `nextcloud-postgres.container` – PostgreSQL database
- `nextcloud.container` – Nextcloud web app
- `nextcloud.network` – Podman network for the stack

The role uses Podman Quadlets for clean systemd-managed container deployment.

The stack is published to `127.0.0.1:{{ nextcloud_port }}` by default, so reverse proxy configuration can be applied from the host.

## Recommended database

Nextcloud is deployed with PostgreSQL, which is recommended over SQLite and more suitable than MariaDB for a medium-sized home deployment.

## Variables

The role uses these defaults from `roles/deploy_nextcloud_container/defaults/main.yml`:

```yaml
nextcloud_domain: "cloud.kerberos.bitsnbyt.es"
nextcloud_port: 8080
nextcloud_internal_port: 80
nextcloud_admin_user: "admin"
nextcloud_admin_password: "nextcloud"
nextcloud_admin_email: "admin@kerberos.bitsnbyt.es"
nextcloud_overwritehost: "https://{{ nextcloud_domain }}"
nextcloud_table_prefix: "oc_"

nextcloud_db_name: "nextcloud"
nextcloud_db_user: "nextcloud"
nextcloud_db_password: "nextcloud"

nextcloud_image: "docker.io/nextcloud:29-fpm"
postgres_image: "docker.io/postgres:16-alpine"
```

### EuroOffice integration

Use `nextcloud_enable_eurooffice: true` to deploy EuroOffice alongside Nextcloud.

```yaml
nextcloud_enable_eurooffice: true
nextcloud_eurooffice_image: "ghcr.io/euro-office/documentserver:latest"
nextcloud_eurooffice_domain: "eurooffice.kerberos.bitsnbyt.es"
```

### EuroOffice JWT secret (without committing secrets)

EuroOffice enables JWT by default. This role supports loading the JWT secret from an environment variable on the Ansible controller, so no secret needs to be committed to the repository.

Secret format restrictions (for safe parsing):
- Maximum 128 characters
- Alphanumeric characters, dots (.), underscores (_), and dashes (-) only
- No spaces or special characters

Default behavior:

- `nextcloud_eurooffice_jwt_secret` stays empty in repo-managed vars
- `nextcloud_eurooffice_jwt_secret_from_env` reads `NEXTCLOUD_EUROOFFICE_JWT_SECRET` on the controller
- secret is written on the target host to `{{ nextcloud_repo_path }}/eurooffice-jwt.env` with mode `0600`
- EuroOffice Quadlet loads it via `EnvironmentFile`

Set the secret before running Ansible (example with alphanumeric + dashes):

```bash
export NEXTCLOUD_EUROOFFICE_JWT_SECRET='Your-Long-Random-Secret-With-Dashes-12345'
ansible-playbook -i inventory/01-lab.yml fedora_base.yml --limit podman-vm -v
```

In Nextcloud Admin settings for EuroOffice, use:

- Document server URL: `https://eurooffice.<your-nextcloud-domain>`
- JWT secret: same value as `NEXTCLOUD_EUROOFFICE_JWT_SECRET`
- JWT header: `AuthorizationJwt`

### Talk server integration

Use an external Talk server by configuring:

```yaml
nextcloud_talk_server_url: "https://talk.example.com"
nextcloud_talk_server_public_url: "https://talk.example.com"
```

This allows the talk component to be hosted outside your homelab.

## Usage

Include the role in your playbook:

```yaml
- hosts: all
  roles:
    - deploy_nextcloud_container
```

## Notes

- The role assumes `podman_user` and `podman_username` are defined globally in your existing inventory.
- The role writes Quadlet files to `/home/{{ podman_user }}/.config/containers/systemd/`.
- Stack target files are written to `/home/{{ podman_user }}/.config/systemd/user/`.
- The Nextcloud stack uses PostgreSQL and does not rely on the AIO image.
- The stack is available at `127.0.0.1:{{ nextcloud_port }}` on the host system.
- Nginx reverse proxy or similar should be configured to handle TLS termination and route to the stack port.

## Stack Management

```bash
# View the stack target status
systemctl --user status nextcloud-stack.target

# Restart the entire stack
systemctl --user restart nextcloud-stack.target

# View individual service logs
journalctl --user -xeu nextcloud.service -n 50
journalctl --user -xeu nextcloud-postgres.service -n 50
journalctl --user -xeu nextcloud-eurooffice.service -n 50  # if enabled
```

## Reverse Proxy Integration

Configure your reverse proxy to forward to `http://localhost:{{ nextcloud_port }}` with the following headers:

```
X-Real-IP: $remote_addr;
X-Forwarded-For: $proxy_add_x_forwarded_for;
X-Forwarded-Proto: $scheme;
X-Forwarded-Host: {{ nextcloud_domain }};
```
