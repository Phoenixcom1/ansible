# Homepage Container Role

Deploys Homepage dashboard in a rootless Podman container managed by **Podman Quadlets** with automatic updates.

## Features

- Homepage dashboard in rootless Podman container
- **Quadlet systemd integration** (modern Podman approach)
- **Automatic container updates** via `AutoUpdate=registry`
- Automatic nginx reverse proxy with SSL
- Persistent configuration storage
- Network capability for ping widgets

## Deployment Approach

This role uses **Podman Quadlets** - the modern, recommended way to manage containers with systemd:

1. Quadlet `.container` file is deployed to `~/.config/containers/systemd/`
2. On systemd reload, the Quadlet is automatically converted to a service unit
3. Service manages the container lifecycle
4. Podman's auto-update feature checks for new images daily

### What are Quadlets?

Quadlets are Podman's native systemd integration format (Podman 4.4+). They use simple declarative syntax similar to docker-compose but with full systemd integration.

### Benefits over podman-compose:

- ✅ **Native Podman approach** (recommended, not deprecated)
- ✅ **Simpler syntax** - declarative `.container` files
- ✅ **Automatic systemd unit generation** - no manual `podman generate systemd`
- ✅ **Built-in auto-updates** via `AutoUpdate=registry`
- ✅ **Better systemd integration** (dependencies, logging, restart policies)
- ✅ **Survives system reboots** (via user lingering)

### Benefits over manual systemd units:

- ✅ **Not deprecated** - Quadlets are the recommended approach
- ✅ **Easier to maintain** - simple key=value format
- ✅ **Less boilerplate** - systemd handles the complexity

## Configuration

### Default Settings (defaults/main.yml)

```yaml
homepage_domain: "homepage.kerberos.fassbender.contact"
homepage_port: 3000
homepage_config_dir: "/opt/podman/homepage"
podman_network: "podman_bridge"
```

## Deployment

```bash
ansible-playbook -i inventory/01-lab.yml noble_base.yml -l docker-vm
```

## Service Management

### Quadlet Location

`~/.config/containers/systemd/homepage.container`

### As Podman User

```bash
# Check service status
systemctl --user status homepage

# Stop service
systemctl --user stop homepage

# Start service
systemctl --user start homepage

# Restart service
systemctl --user restart homepage

# View logs
journalctl --user -u homepage -f

# Disable service
systemctl --user disable homepage

# Enable service
systemctl --user enable homepage

# View the Quadlet source
cat ~/.config/containers/systemd/homepage.container

# View the auto-generated systemd unit
systemctl --user cat homepage
```

### As Root (managing podman user's service)

```bash
# Check status
sudo -u podman XDG_RUNTIME_DIR=/run/user/1003 systemctl --user status homepage

# Restart
sudo -u podman XDG_RUNTIME_DIR=/run/user/1003 systemctl --user restart homepage

# View Quadlet
sudo cat /home/podman/.config/containers/systemd/homepage.container
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
Image=ghcr.io/gethomepage/homepage:latest
AutoUpdate=registry
```

This is equivalent to the old label: `--label "io.containers.autoupdate=registry"`

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

- **Image**: `ghcr.io/gethomepage/homepage:latest`
- **Network**: Connected to `podman_bridge`
- **Port**: 3000 (localhost only, proxied via nginx)
- **User**: Runs as podman user (UID:GID dynamically discovered)
- **Capabilities**: NET_RAW (for ping widgets)
- **User namespace**: keep-id mode
- **Restart policy**: unless-stopped

### Volumes

- `/app/config` → `{{ homepage_config_dir }}` (with SELinux :Z flag)

### Environment Variables

- `HOMEPAGE_ALLOWED_HOSTS`: Configured domain
- Additional vars from `.env` file in config directory

## Configuration Files

Located in `{{ homepage_config_dir }}` (default: `/opt/podman/homepage`):

- `settings.yaml` - Main settings
- `services.yaml` - Service widgets
- `widgets.yaml` - Dashboard widgets
- `bookmarks.yaml` - Bookmark links
- `.env` - Environment variables (includes podman bridge gateway)

## Systemd Unit File

Generated at: `/home/podman/.config/systemd/user/container-homepage.service`

The service file is automatically generated with `--new` flag, which means:

- Container is removed when service stops
- Fresh container is created when service starts
- Updates are applied cleanly without leftover containers

## Backup and Restore

### Backup Configuration

```bash
# Backup entire config directory
tar -czf homepage-config-$(date +%Y%m%d).tar.gz -C /opt/podman homepage/

# Or use Restic (if configured)
# Configuration is automatically backed up by restic-backup role
```

### Restore Configuration

```bash
# Stop service
systemctl --user stop container-homepage

# Restore config
tar -xzf homepage-config-YYYYMMDD.tar.gz -C /opt/podman/

# Fix permissions
sudo chown -R podman:podman /opt/podman/homepage

# Start service
systemctl --user start container-homepage
```

## Troubleshooting

### Service Won't Start

```bash
# Check service status
systemctl --user status container-homepage

# View full logs
journalctl --user -u container-homepage -n 100 --no-pager

# Check container logs directly
podman logs homepage

# Verify container exists
podman ps -a | grep homepage
```

### Auto-Update Not Working

```bash
# Check auto-update timer status
systemctl --user status podman-auto-update.timer

# Check when it last ran
systemctl --user list-timers podman-auto-update.timer

# Test auto-update manually
podman auto-update --dry-run

# Check container labels
podman inspect homepage | grep -A5 Labels
```

### Permission Issues

```bash
# Fix config directory ownership
sudo chown -R podman:podman /opt/podman/homepage

# Verify podman user can access config
ls -la /opt/podman/homepage
```

### Container Not Accessible

```bash
# Check if container is running
podman ps | grep homepage

# Check port binding
podman port homepage

# Test local connection
curl http://127.0.0.1:3000

# Check nginx proxy
curl -I https://{{ homepage_domain }}
```

### Lingering Not Enabled

If services don't start after reboot:

```bash
# Enable lingering for podman user
sudo loginctl enable-linger podman

# Verify lingering is enabled
loginctl show-user podman | grep Linger
```

## Migration from Compose

If you have an existing compose-based deployment, the role will:

1. Stop old podman-compose setup
2. Remove old container
3. Create new container with systemd management
4. Preserve existing configuration

Your config files are NOT modified during migration.

## Rolling Back to Compose

If you need to roll back:

```bash
# Stop systemd service
systemctl --user stop container-homepage
systemctl --user disable container-homepage

# Restore old compose deployment
# (backed up in main-compose.yml.bak)
podman-compose -f /opt/podman/homepage/compose_homepage.yml up -d
```

## Advanced: Customizing Auto-Update Schedule

To change update frequency:

```bash
# Edit timer (as podman user)
systemctl --user edit podman-auto-update.timer

# Add override:
# [Timer]
# OnCalendar=
# OnCalendar=weekly

# Reload and check
systemctl --user daemon-reload
systemctl --user list-timers podman-auto-update.timer
```

## Resources

- [Podman Systemd Integration](https://docs.podman.io/en/latest/markdown/podman-systemd.unit.5.html)
- [Podman Auto-Update](https://docs.podman.io/en/latest/markdown/podman-auto-update.1.html)
- [Homepage Documentation](https://gethomepage.dev/)
