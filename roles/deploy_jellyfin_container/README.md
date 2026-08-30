# Jellyfin Container Role

Deploys Jellyfin media server in a rootless Podman container managed by **Podman Quadlets** with automatic updates.

## Features

- Jellyfin media server in rootless Podman container
- **Quadlet systemd integration** (modern Podman approach)
- **Automatic container updates** via `AutoUpdate=registry`
- Network media mount support (NFS or SMB/CIFS)
- Automatic nginx reverse proxy with SSL
- Persistent configuration and cache storage
- Read-only media access (security)
- Service discovery support (UDP port)

## Deployment Approach

This role uses **Podman Quadlets** - the modern, recommended way to manage containers with systemd:

1. Quadlet `.container` file is deployed to `~/.config/containers/systemd/`
2. On systemd reload, the Quadlet is automatically converted to a service unit
3. Service manages the container lifecycle
4. Podman's auto-update feature checks for new images daily

### Benefits over podman-compose:

- ✅ **Native Podman approach** (recommended, not deprecated)
- ✅ **Simpler syntax** - declarative `.container` files
- ✅ **Automatic systemd unit generation**
- ✅ **Built-in auto-updates** via `AutoUpdate=registry`
- ✅ **Better systemd integration** (dependencies, logging, restart policies)
- ✅ **Survives system reboots** (via user lingering)
- ✅ **Proper mount dependencies** - waits for network mounts

## Configuration

### Default Settings (defaults/main.yml)

```yaml
# Container settings
jellyfin_project_name: jellyfin
jellyfin_config_dir: "/opt/podman/jellyfin/config"
jellyfin_cache_dir: "/opt/podman/jellyfin/cache"
jellyfin_media_dir: "/mnt/jellyfin-media"

# Network mount (NFS or SMB/CIFS)
jellyfin_enable_network_mount: true
jellyfin_network_mount_source: "//datenbunker.local/Movies"
jellyfin_network_mount_type: "cifs" # or "nfs"
jellyfin_network_mount_options: "vers=3.1.1,_netdev,credentials=/root/.smbcredentials,defaults,uid=1031,gid=100,rw"

# Application
jellyfin_domain: "jellyfin.{{ customer_domain }}"
jellyfin_port: 8096
jellyfin_discovery_port: 7359

# Podman
podman_user: "podman"
podman_network: "podman"
```

## Network Mount Setup

### SMB/CIFS Mount

1. **Create credentials file** on the host:

   ```bash
   sudo nano /root/.smbcredentials
   ```

   Content:

   ```
   username=your_smb_user
   password=your_smb_password
   ```

   Secure it:

   ```bash
   sudo chmod 600 /root/.smbcredentials
   ```

2. **Configure in inventory/defaults**:
   ```yaml
   jellyfin_enable_network_mount: true
   jellyfin_network_mount_source: "//nas-server.local/Movies"
   jellyfin_network_mount_type: "cifs"
   jellyfin_network_mount_options: "vers=3.1.1,_netdev,credentials=/root/.smbcredentials,uid=1003,gid=1003,rw"
   ```

### NFS Mount

```yaml
jellyfin_enable_network_mount: true
jellyfin_network_mount_source: "192.168.1.100:/export/Movies"
jellyfin_network_mount_type: "nfs"
jellyfin_network_mount_options: "defaults,_netdev"
```

### Disable Network Mount

Use local directory instead:

```yaml
jellyfin_enable_network_mount: false
jellyfin_media_dir: "/opt/podman/jellyfin/media"
```

## Deployment

```bash
ansible-playbook -i inventory/01-lab.yml noble_base.yml -l docker-vm
```

## Service Management

### Quadlet Location

`~/.config/containers/systemd/jellyfin.container`

### As Podman User

```bash
# Check service status
systemctl --user status jellyfin

# Stop service
systemctl --user stop jellyfin

# Start service
systemctl --user start jellyfin

# Restart service
systemctl --user restart jellyfin

# View logs
journalctl --user -u jellyfin -f

# Disable service
systemctl --user disable jellyfin

# Enable service
systemctl --user enable jellyfin

# View the Quadlet source
cat ~/.config/containers/systemd/jellyfin.container

# View the auto-generated systemd unit
systemctl --user cat jellyfin
```

### As Root (managing podman user's service)

```bash
# Check status
sudo -u podman XDG_RUNTIME_DIR=/run/user/1003 systemctl --user status jellyfin

# Restart
sudo -u podman XDG_RUNTIME_DIR=/run/user/1003 systemctl --user restart jellyfin

# View logs
sudo -u podman XDG_RUNTIME_DIR=/run/user/1003 journalctl --user -u jellyfin -n 100
```

## Automatic Updates

### How It Works

The Quadlet includes `AutoUpdate=registry`, which enables Podman's auto-update feature:

1. **Daily check**: Podman checks registry for new images (via systemd timer)
2. **Automatic pull**: If new image available, pulls it automatically
3. **Graceful restart**: Stops old container, starts new one with same configuration
4. **Rollback safety**: Old image kept for rollback if needed

### Quadlet Auto-Update Syntax

In the `.container` file:

```ini
[Container]
Image=docker.io/jellyfin/jellyfin:latest
AutoUpdate=registry
```

### Manual Update

```bash
# Check for updates (as podman user)
podman auto-update --dry-run

# Apply updates
podman auto-update

# Or via systemd timer (triggers daily automatically)
systemctl --user status podman-auto-update.timer
```

### Update Schedule

The auto-update timer runs daily. To check schedule:

```bash
# As podman user
systemctl --user list-timers podman-auto-update.timer
```

### Force Immediate Update

```bash
# As podman user
systemctl --user start podman-auto-update.service
```

## Container Details

### Runtime Configuration

- **Image**: `docker.io/jellyfin/jellyfin:latest`
- **Network**: `podman` (Podman's built-in rootless network)
- **Ports**:
  - `127.0.0.1:8096:8096/tcp` - Web interface (proxied by nginx)
  - `7359:7359/udp` - Service discovery
- **Volumes**:
  - `/opt/podman/jellyfin/config` → `/config` (configuration, Z flag)
  - `/opt/podman/jellyfin/cache` → `/cache` (transcoding cache, Z flag)
  - `/mnt/jellyfin-media` → `/media` (read-only, ro,Z flags)
- **User namespace**: `keep-id` (maps to podman user UID/GID)
- **Restart policy**: `always`

### Security Features

- ✅ **Rootless Podman** - Container runs as non-root user
- ✅ **Read-only media** - Media directory mounted with `:ro` flag
- ✅ **User namespace mapping** - Isolates container user from host
- ✅ **SELinux labels** - `:Z` flag for proper labeling

## Directory Structure

```
/opt/podman/jellyfin/
├── config/          # Jellyfin configuration and database
└── cache/           # Transcoding cache

/mnt/jellyfin-media/ # Network mount (or local media)
├── Movies/
├── TV Shows/
└── Music/
```

## Nginx Reverse Proxy

The role automatically deploys an nginx reverse proxy configuration:

- **Location**: `/etc/nginx/conf.d/jellyfin.conf`
- **SSL**: Uses certificates from `group_vars/all.yml` (ssl_cert/ssl_key)
- **Domain**: Configured via `jellyfin_domain`
- **Upstream**: Proxies to `127.0.0.1:8096`

### Nginx Configuration Features

- HTTP/2 support
- WebSocket support (required for Jellyfin)
- Proper headers for reverse proxy
- Client max body size: 20M (for uploads)

## Backup Integration

This role integrates with the `restic-backup` role. Jellyfin backups:

- **What's backed up**: Config directory only
- **What's excluded**: Cache and transcoding directories
- **Method**: Container stopped before backup (SQLite safety)
- **Frequency**: Daily at 2:00 AM
- **Retention**: 7 daily, 4 weekly, 12 monthly

See `roles/restic-backup/README.md` for details.

### Manual Backup

```bash
# Stop container
systemctl --user stop jellyfin

# Backup config
sudo rsync -av /opt/podman/jellyfin/config/ /backup/jellyfin-config/

# Start container
systemctl --user start jellyfin
```

### Restore

```bash
# Stop container
systemctl --user stop jellyfin

# Restore config
sudo rsync -av /backup/jellyfin-config/ /opt/podman/jellyfin/config/

# Fix ownership
sudo chown -R podman:podman /opt/podman/jellyfin/config

# Start container
systemctl --user start jellyfin
```

## Troubleshooting

### Service won't start

```bash
# Check service status
systemctl --user status jellyfin

# Check systemd logs
journalctl --user -u jellyfin -n 100

# Check Podman logs
podman logs jellyfin

# Verify Quadlet syntax
cat ~/.config/containers/systemd/jellyfin.container
```

### Network mount issues

```bash
# Check if mount is active
mount | grep jellyfin-media

# Check fstab entry
cat /etc/fstab | grep jellyfin

# Test mount manually
sudo mount /mnt/jellyfin-media

# Check SMB credentials
sudo cat /root/.smbcredentials
sudo chmod 600 /root/.smbcredentials
```

### Permission issues

```bash
# Check ownership
ls -la /opt/podman/jellyfin/config
ls -la /opt/podman/jellyfin/cache

# Fix ownership
sudo chown -R podman:podman /opt/podman/jellyfin/config
sudo chown -R podman:podman /opt/podman/jellyfin/cache

# Check UID/GID in Quadlet
grep "User=" ~/.config/containers/systemd/jellyfin.container
```

### Container won't access media

```bash
# Check mount
mount | grep jellyfin-media

# Check permissions
ls -la /mnt/jellyfin-media

# Check SELinux context
ls -Z /mnt/jellyfin-media

# Relabel if needed
sudo chcon -Rt svirt_sandbox_file_t /mnt/jellyfin-media
```

### Auto-update not working

```bash
# Check auto-update timer
systemctl --user status podman-auto-update.timer

# Check last run
systemctl --user list-timers podman-auto-update.timer

# Manual update check
podman auto-update --dry-run

# Check Quadlet has AutoUpdate
grep AutoUpdate ~/.config/containers/systemd/jellyfin.container
```

## Migration from Compose

If migrating from the old podman-compose setup:

1. **Stop old service**:

   ```bash
   podman-compose -f /opt/podman/jellyfin/compose_jellyfin.yml down
   ```

2. **Deploy Quadlet** (via Ansible):

   ```bash
   ansible-playbook -i inventory noble_base.yml -l target-host
   ```

3. **Verify**:

   ```bash
   systemctl --user status jellyfin
   podman ps
   ```

4. **Cleanup old files** (optional):
   ```bash
   rm /opt/podman/jellyfin/compose_jellyfin.yml
   ```

## Performance Tips

### Transcoding

- **Hardware acceleration**: Jellyfin container doesn't currently expose GPU
- **Cache directory**: Ensure `/cache` has enough space for transcoding
- **Cache location**: Can be changed in Jellyfin web UI

### Database Performance

- **SQLite location**: `/config/data/library.db`
- **Backups**: Stop container before backing up SQLite database
- **Vacuum**: Periodically vacuum database for performance

## Related Roles

- `podman` - Sets up Podman and rootless environment
- `podman-user` - Creates the podman user
- `nginx_reverse_proxy` - Manages nginx proxy configuration
- `restic-backup` - Handles automated backups

## Documentation

- **Jellyfin**: https://jellyfin.org/docs/
- **Podman Quadlets**: `man podman-systemd.unit`
- **Quadlet docs**: https://docs.podman.io/en/latest/markdown/podman-systemd.unit.5.html
