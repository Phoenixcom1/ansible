# AdGuard Home Deployment Role

## Overview

This Ansible role deploys AdGuard Home as a containerized DNS server using Podman Quadlets. AdGuard Home is a network-wide software for blocking ads & tracking. It operates as a DNS server that re-routes tracking domains to a "black hole", preventing your devices from connecting to those servers.

### Architecture

- **Container Runtime**: Podman with systemd Quadlets
- **Network**: Isolated network (`adguardhome_net`)
- **Web Interface**: Reverse proxied through nginx (HTTPS)
- **DNS Service**: Direct port exposure on host (ports 53/tcp, 53/udp)
- **Work Directory**: `{{ adguardhome_work_dir }}` - Database, query logs, statistics
- **Config Directory**: `{{ adguardhome_conf_dir }}` - Configuration files

### Features

- **DNS Server**: Standard DNS on port 53 (TCP/UDP)
- **DNS over TLS (DoT)**: Encrypted DNS on port 853
- **DNS over QUIC (DoQ)**: Modern encrypted DNS on ports 784, 853, 8853
- **DNSCrypt**: Encrypted DNS on port 5443
- **HTTPS Admin Interface**: Secured via nginx reverse proxy
- **Optional DHCP Server**: Can be enabled if needed

---

## Prerequisites

- Ansible 2.9 or higher
- Target system running Ubuntu/Debian with Podman installed
- Nginx installed and configured for reverse proxy
- SSL certificates configured in nginx role
- Podman user created (default: `podman`)

---

## System Configuration

This role automatically configures the host system to allow AdGuard Home to function as a DNS server:

### Unprivileged Port Binding

Configures the system to allow unprivileged users (rootless Podman) to bind to port 53:

- Creates `/etc/sysctl.d/99-adguardhome-unprivileged-ports.conf`
- Sets `net.ipv4.ip_unprivileged_port_start=53`
- Applies immediately and persists across reboots

### systemd-resolved Configuration

Disables systemd-resolved's DNS stub listener to free port 53:

- Creates `/etc/systemd/resolved.conf.d/adguardhome.conf`
- Sets `DNSStubListener=no`
- Updates `/etc/resolv.conf` to point to `/run/systemd/resolve/resolv.conf`
- Host continues using upstream DNS from DHCP (not AdGuard Home)

**Important**: The host system will continue to use DNS servers provided by DHCP, while AdGuard Home serves DNS to other network clients. This ensures the host DNS remains functional even if the AdGuard Home container is stopped.

---

## Role Variables

### Required Variables

These variables should be configured in your inventory or playbook:

```yaml
# Domain for web interface access
adguardhome_domain: "adguard.example.com"

# Podman service directory (usually defined globally)
podman_service_dir: "/srv/podman"

# Podman username
podman_username: "podman"
```

### Optional Variables

Defined in `defaults/main.yml` with sensible defaults:

```yaml
# Network settings
adguardhome_network: adguardhome_net
adguardhome_admin_port: 3180 # Internal admin interface port

# DNS ports
adguardhome_dns_port_tcp: 53
adguardhome_dns_port_udp: 53

# DHCP (disabled by default)
adguardhome_dhcp_enabled: false

# Secure DNS ports
adguardhome_dot_port: 853 # DNS over TLS
adguardhome_doq_port_853: 853 # DNS over QUIC
adguardhome_doq_port_784: 784 # DNS over QUIC
adguardhome_doq_port_8853: 8853 # DNS over QUIC
adguardhome_dnscrypt_port: 5443

# Timezone
adguardhome_timezone: "Europe/Paris"
```

---

## Usage

### Including in a Playbook

```yaml
- hosts: dns_servers
  roles:
    - role: deploy_adguardhome_container
      vars:
        adguardhome_domain: "adguard.mynetwork.local"
        adguardhome_dhcp_enabled: false
```

### Initial Setup

1. **Deploy the role** - Run the playbook to create the container
2. **Access initial setup** - Navigate to `http://your-server-ip:3010`
   - **Note**: If you cannot access the server IP directly, the initial setup wizard will be available via the nginx reverse proxy at `https://{{ adguardhome_domain }}`
3. **Complete setup wizard**:
   - Set admin username and password
   - Configure listening interfaces (use 0.0.0.0 for all interfaces)
   - Admin interface should be on port 80 inside container
4. **Access via HTTPS** - After initial setup, access via `https://{{ adguardhome_domain }}`

**Note**: Port 3010 is only used during initial setup and can be removed from the quadlet after configuration is complete.

### Post-Deployment Configuration

Access the admin interface at `https://{{ adguardhome_domain }}` to configure:

- **Upstream DNS servers**: Set your preferred upstream DNS (e.g., Cloudflare, Google, Quad9)
- **Blocklists**: Enable/disable blocklists and add custom ones
- **DNS rewrites**: Add custom DNS records for local services
- **Client settings**: Configure per-client filtering rules
- **Query log retention**: Adjust log retention period
- **DHCP settings**: Enable/configure if using DHCP functionality

---

## Port Mappings

### Web Interface

- `3010/tcp` - Initial setup (temporary, exposed on all interfaces)
- `3180/tcp` - Admin interface (bound to 127.0.0.1, reverse proxied via nginx to 443)

### DNS Service

- `53/tcp`, `53/udp` - Standard DNS
- `853/tcp` - DNS over TLS (DoT)
- `853/udp`, `784/udp`, `8853/udp` - DNS over QUIC (DoQ)
- `5443/tcp`, `5443/udp` - DNSCrypt

### DHCP (Optional)

- `67/udp` - DHCP server
- `68/udp` - DHCP client

---

## Backup and Restore

### What to Backup

AdGuard Home stores all configuration and data in two directories:

- **Config Directory** (`{{ adguardhome_conf_dir }}`):
  - `AdGuardHome.yaml` - Main configuration
  - SSL certificates (if using internal HTTPS)
- **Work Directory** (`{{ adguardhome_work_dir }}`):
  - `data/` - Database files
  - `querylog.json*` - Query logs
  - `stats.db` - Statistics database
  - `filters/` - Downloaded blocklists (can regenerate)

### Manual Backup

```bash
# Stop the container
su - podman -c "systemctl --user stop adguardhome"

# Backup configuration and data
tar -czf adguardhome-backup-$(date +%Y%m%d).tar.gz \
  -C {{ podman_service_dir }}/adguardhome .

# Restart the container
su - podman -c "systemctl --user start adguardhome"
```

### Restore from Backup

```bash
# Stop the container
su - podman -c "systemctl --user stop adguardhome"

# Restore files
tar -xzf adguardhome-backup-YYYYMMDD.tar.gz \
  -C {{ podman_service_dir }}/adguardhome

# Fix permissions
chown -R podman:podman {{ podman_service_dir }}/adguardhome

# Restart the container
su - podman -c "systemctl --user start adguardhome"
```

### Automated Backup with Restic

Add to `roles/restic-backup/defaults/main.yml`:

```yaml
adguardhome:
  enabled: true
  stop_before_backup: true
  compose_file: "{{ podman_service_dir }}/adguardhome/compose_adguardhome.yml"
  project_name: adguardhome
  paths:
    - "{{ podman_service_dir }}/adguardhome/conf"
    - "{{ podman_service_dir }}/adguardhome/work"
  excludes:
    - "*/filters/*" # Blocklists can be re-downloaded
    - "querylog.json*" # Query logs (optional, can be large)
```

---

## Management

### Service Control

```bash
# Check status
su - podman -c "systemctl --user status adguardhome"

# View logs
su - podman -c "journalctl --user -u adguardhome -f"

# Restart service
su - podman -c "systemctl --user restart adguardhome"

# Stop service
su - podman -c "systemctl --user stop adguardhome"

# Start service
su - podman -c "systemctl --user start adguardhome"
```

### Container Management

```bash
# View running container
su - podman -c "podman ps | grep adguardhome"

# Execute command in container
su - podman -c "podman exec -it adguardhome /bin/sh"

# View container logs
su - podman -c "podman logs adguardhome"

# Inspect container
su - podman -c "podman inspect adguardhome"
```

### Update Container

Use the update playbook to safely update:

```bash
ansible-playbook update-container.yml --limit dns_servers --tags adguardhome
```

Or manually:

```bash
# Stop container
su - podman -c "systemctl --user stop adguardhome"

# Pull new image
su - podman -c "podman pull docker.io/adguard/adguardhome:latest"

# Start container (quadlet will recreate with new image)
su - podman -c "systemctl --user start adguardhome"
```

---

## Troubleshooting

### Container Won't Start

```bash
# Check systemd status
su - podman -c "systemctl --user status adguardhome"

# Check detailed logs
su - podman -c "journalctl --user -u adguardhome -n 50"

# Verify quadlet file
cat /home/podman/.config/containers/systemd/adguardhome.container

# Regenerate systemd units
su - podman -c "systemctl --user daemon-reload"
```

### DNS Not Resolving

1. **Check container is running**: `su - podman -c "podman ps | grep adguardhome"`
2. **Verify port binding**: `ss -tulpn | grep :53`
3. **Test DNS locally**: `dig @localhost example.com`
4. **Check firewall**: Ensure port 53 is open
5. **Review AdGuard logs**: Check the admin interface or container logs

### Can't Access Admin Interface

1. **Check nginx config**: `nginx -t`
2. **Verify reverse proxy**: `curl http://127.0.0.1:{{ adguardhome_admin_port }}`
3. **Check SSL certificates**: Ensure nginx can read cert files
4. **Review nginx logs**: `/var/log/nginx/error.log`

### Port 53 Already in Use

This role automatically handles port 53 conflicts with systemd-resolved. If you still encounter issues:

```bash
# Check what's using port 53
sudo ss -tulpn | grep ':53'

# Verify systemd-resolved configuration
cat /etc/systemd/resolved.conf.d/adguardhome.conf

# Manually restart systemd-resolved if needed
sudo systemctl restart systemd-resolved

# Verify port 53 is free
sudo ss -tulpn | grep ':53'
```

If another service (not systemd-resolved) is using port 53, you'll need to stop or reconfigure that service.

---

## Security Considerations

- **Admin Interface**: Only accessible via HTTPS through nginx reverse proxy
- **DNS Queries**: By default unencrypted; use DoT/DoQ/DNSCrypt for encryption
- **Initial Setup**: Port 3000 is exposed for initial setup - close it after configuration
- **Network Isolation**: Container runs in isolated network
- **Updates**: Regularly update the container image for security patches

---

## Dependencies

This role depends on:

- `podman` role - Installs and configures Podman
- `podman-user` role - Creates podman user with proper setup
- `nginx_reverse_proxy` role - Provides SSL termination and reverse proxy

---

## License

MIT

## Author

Generated for Ansible Automation
