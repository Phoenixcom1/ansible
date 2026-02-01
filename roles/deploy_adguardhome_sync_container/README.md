# AdGuard Home Sync Deployment Role

Deploys AdGuard Home Sync as a containerized service using Podman Quadlets. AdGuard Home Sync synchronizes AdGuard Home configurations from a primary (origin) instance to one or more replica instances.

## Overview

AdGuard Home Sync automates the replication of:

- DNS settings (access lists, server config, rewrites)
- Filters and blocklists
- Client settings
- Services blocking
- General settings
- Query log and stats configuration
- Web UI theme

**Project**: [bakito/adguardhome-sync](https://github.com/bakito/adguardhome-sync)

## Features

- Runs in rootless Podman container
- **Quadlet systemd integration** for automatic management
- **Automatic container updates** via `AutoUpdate=registry`
- **Dedicated network** for AdGuard Home containers isolation
- **Environment-based credentials** via `.env` file (excluded from backups)
- Web UI for monitoring sync status (optional)
- Configurable cron schedule for automatic syncing
- Selective feature syncing (enable/disable specific features)
- Support for multiple replica instances

## Prerequisites

- Ansible 2.9 or higher
- Target system with Podman installed
- Podman user created (default: `podman`)
- AdGuard Home origin instance already deployed and configured
- Network connectivity between sync container and all AdGuard Home instances

## Configuration

### Default Settings (defaults/main.yml)

```yaml
# Application settings
adguardhome_sync_domain: "adguardhome-sync.kerberos.fassbender.contact"
adguardhome_sync_api_port: 8082

# Data directory for config
adguardhome_sync_config_dir: "{{ podman_service_dir }}/adguardhome-sync"

# Cron schedule (default: every 2 hours)
adguardhome_sync_cron: "0 */2 * * *"
adguardhome_sync_run_on_start: true
adguardhome_sync_continue_on_error: false

# Origin AdGuard Home instance
adguardhome_sync_origin_url: "http://192.168.1.249" # External origin
adguardhome_sync_origin_username: "admin"
adguardhome_sync_origin_password: "changeme"

# Replica instances
adguardhome_sync_replicas:
  - url: "http://adguardhome" # Local replica via container name
    username: "admin"
    password: "changeme"

# API credentials
adguardhome_sync_api_enabled: true
adguardhome_sync_api_username: "admin"
adguardhome_sync_api_password: "changeme"
adguardhome_sync_api_dark_mode: true

# Podman user and network
podman_user: "{{ podman_username }}"
adguardhome_network: "adguardhome_net" # Dedicated isolated network
```

### Environment File (.env)

Credentials are stored in a separate `.env` file at `{{ adguardhome_sync_config_dir }}/.env`:

- **Created only on initial deployment** - won't be overwritten by subsequent runs
- **Restrictive permissions** (0600) for security
- **Can be excluded from backups** (e.g., restic)
- Managed manually after initial deployment

The `.env` file contains:

```bash
ORIGIN_URL=http://192.168.1.249
ORIGIN_USERNAME=admin
ORIGIN_PASSWORD=changeme

REPLICA1_URL=http://adguardhome
REPLICA1_USERNAME=admin
REPLICA1_PASSWORD=changeme

API_USERNAME=admin
API_PASSWORD=changeme
```

### Configuring Instances

**Origin Instance** (external AdGuard Home):

```yaml
adguardhome_sync_origin_url: "http://192.168.1.249" # Use actual IP/hostname and port
adguardhome_sync_origin_username: "admin"
adguardhome_sync_origin_password: "changeme"
```

**Replica Instances**:

For a local replica (same Podman network):

```yaml
adguardhome_sync_replicas:
  - url: "http://adguardhome" # Container name (both on adguardhome_net)
    username: "admin"
    password: "changeme"
```

For external replicas:

```yaml
adguardhome_sync_replicas:
  - url: "http://192.168.1.10:80"
    username: "admin"
    password: "changeme"
  - url: "https://adguard.example.com"
    username: "admin"
    password: "changeme"
    insecureSkipVerify: true # For self-signed certificates
```

**Important**: Use the correct port for each instance:

- External instances with macvlan: typically port 80 or 443
- Local container on same network: use container name with port 80
- Host-published ports: use the mapped external port

### Feature Flags

Control which features are synchronized:

```yaml
adguardhome_sync_features:
  dns:
    accessLists: true
    serverConfig: true
    rewrites: true
  dhcp:
    serverConfig: false # Usually don't sync DHCP
    staticLeases: false
  generalSettings: true
  queryLogConfig: true
  statsConfig: true
  clientSettings: true
  services: true
  filters: true
  theme: true
  tlsConfig: false
```

## Deployment

### Including in a Playbook

```yaml
- hosts: docker_hosts
  roles:
    - deploy_adguardhome_sync_container
  vars:
    adguardhome_sync_origin_password: "{{ vault_adguardhome_password }}"
    adguardhome_sync_replicas:
      - url: "http://192.168.1.10:3000"
        username: "admin"
        password: "{{ vault_replica1_password }}"
```

### Deploy

```bash
ansible-playbook -i inventory/01-lab.yml site.yml -l docker-vm --tags deploy_adguardhome_sync
```

## Service Management

### As Podman User

```bash
# Check service status
systemctl --user status adguardhome-sync

# View logs
journalctl --user -u adguardhome-sync -f

# Restart service
systemctl --user restart adguardhome-sync

# Trigger manual sync (via API)
curl -X POST http://localhost:8080/sync \
  -u admin:changeme
```

### Web UI

Access the web interface at `http://<server- -f

````

Common issues:

- **Authentication failures**: Verify credentials in `.env` file at `{{ adguardhome_sync_config_dir }}/.env`
- **Network connectivity**:
  - For external instances: ensure firewall allows connections
  - For local replicas: verify both containers are on `adguardhome_net` network
- **DNS resolution**: Container names only resolve within the same Podman network
- **Wrong ports**: Use port 80 for container-to-container communication, not host-mapped ports

### Network Issues

Verify network connectivity:

```bash
# Check which network containers are on
podman ps --filter name=adguardhome --format "{{.Names}}: {{.Networks}}"

# Test connectivity from sync container to replica
podman exec adguardhome-sync wget -O- http://adguardhome/control/status

# Test external origin connectivity
podman exec adguardhome-sync wget -O- http://192.168.1.249/control/status
````

### Origin/Replica URL Configuration

**For local AdGuard Home replica** (same host):

- Use container name: `http://adguardhome` or `http://adguardhome:80`
- Both containers must be on `adguardhome_net` network

**For external AdGuard Home instances**:

- Use IP/hostname with correct port: `http://192.168.1.249:80`
- Check which port the admin interface is published on (often 80, 443, or 3000)

**Do NOT use**:

- `localhost` (refers to the sync container itself)
- Host-published ports (like 3180) for container-to-container communication

### Updating Credentials

The `.env` file is only created once and won't be overwritten:

```bash
# Edit credentials manually
sudo -u podman nano /opt/podman/adguardhome-sync/.env

# Restart service to apply changes
sudo -u podman systemctl --user restart adguardhome-sync
```

Check logs for detailed error messages:

```bash
journalctl --user -u adguardhome-sync -n 100
```

{{ adguardhome_sync_config_dir }}/.env (created once, not overwritten)

````

## Backup Considerations

The `.env` file contains sensitive credentials and can be excluded from backups:

```yaml
# In restic-backup configuration
restic_global_excludes:
  - "*/cache/*"
  - "*/tmp/*"
  - "*.log"
  - "*/.env"  # Exclude all .env files
````

The YAML configuration file can be safely backed up as it no longer contains credentials.

## Security Considerations

- Store passwords in Ansible Vault for initial deployment, not in plain text
- The `.env` file has restrictive permissions (0600)
- Manually update credentials in `.env` file after initial deployment
- Use strong passwords for the sync API
- Consider using certificate-based authentication for replicas
- Restrict API access to localhost or trusted networks (`PublishPort=127.0.0.1:...`)
- Review which features should be synced (disable DHCP sync unless needed)
- Both AdGuard Home containers run on isolated `adguardhome_net` network
  The origin URL should point to the **local AdGuard Home admin interface**:

- If running on the same host: `http://localhost:3180` (AdGuard Home admin port)
- If on different host: `http://<adguardhome-ip>:<port>`

**Note**: Use the internal admin port (default 3180), not the DNS port (53)

### Container Won't Start

Check the Quadlet configuration:

```bash
cat ~/.config/containers/systemd/adguardhome-sync.container
```

Verify the configuration file exists:

```bash
cat /opt/podman/adguardhome-sync/adguardhome-sync.yaml
```

## Files Created by This Role

```
/home/{{ podman_user }}/.config/containers/systemd/adguardhome-sync.container
{{ adguardhome_sync_config_dir }}/adguardhome-sync.yaml
```

## Security Considerations

- Store passwords in Ansible Vault, not in plain text
- Use strong passwords for the sync API
- Consider using certificate-based authentication for replicas
- Restrict API access to localhost or trusted networks
- Review which features should be synced (disable DHCP sync unless needed)

## Dependencies

- Podman installed and configured
- Podman user with lingering enabled
- AdGuard Home instance running

## Related Roles

- `deploy_adguardhome_container` - Deploys the origin AdGuard Home instance
- `podman` - Installs and configures Podman
- `podman-user` - Sets up rootless Podman user

## References

- [AdGuard Home Sync GitHub](https://github.com/bakito/adguardhome-sync)
- [Podman Quadlets Documentation](https://docs.podman.io/en/latest/markdown/podman-systemd.unit.5.html)
- [AdGuard Home API](https://github.com/AdguardTeam/AdGuardHome/tree/master/openapi)

## License

MIT

## Author

Created as part of the Ansible infrastructure automation project.
