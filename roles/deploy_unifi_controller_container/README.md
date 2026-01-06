# UniFi Controller Container Role

Deploys UniFi Network Controller in a rootless Podman container managed by **Podman Quadlets** with automatic updates.

## Features

- UniFi Network Controller in rootless Podman container
- **Quadlet systemd integration** (modern Podman approach)
- **Automatic container updates** via `AutoUpdate=registry`
- **Built-in health checks** - monitors controller readiness
- Automatic nginx reverse proxy with SSL
- Built-in automatic backups
- Persistent configuration storage
- All required ports properly exposed

## Deployment Approach

This role uses **Podman Quadlets** - the modern, recommended way to manage containers with systemd:

1. Quadlet `.container` file is deployed to `~/.config/containers/systemd/`
2. On systemd reload, the Quadlet is automatically converted to a service unit
3. Service manages the container lifecycle with health checks
4. Podman's auto-update feature checks for new images daily

### Benefits over podman-compose:

- ✅ **Native Podman approach** (recommended, not deprecated)
- ✅ **Simpler syntax** - declarative `.container` files
- ✅ **Automatic systemd unit generation**
- ✅ **Built-in auto-updates** via `AutoUpdate=registry`
- ✅ **Built-in health checks** - proper startup monitoring
- ✅ **Better systemd integration** (dependencies, logging, restart policies)
- ✅ **Survives system reboots** (via user lingering)

## Configuration

### Default Settings (defaults/main.yml)

```yaml
unifi_domain: "unifi.kerberos.fassbender.contact"
unifi_port: 8443
unifi_config_dir: "/opt/podman/unifi/data"

# Podman
podman_user: "podman"
podman_network: "podman_bridge"
```

### Required Ports

- **8443**: Web UI (HTTPS, proxied via nginx to localhost only)
- **8080**: Device communication (inform protocol)
- **3478**: STUN server (device discovery, UDP)
- **6789**: Speed test
- **8880**: HTTP portal redirect
- **8843**: HTTPS portal redirect
- **10001**: AP discovery (UDP broadcast)

## Deployment

```bash
ansible-playbook -i inventory/01-lab.yml noble_base.yml -l docker-vm
```

**Note**: First startup takes 5-10 minutes while UniFi initializes the database and services.

## Service Management

### Quadlet Location

`~/.config/containers/systemd/unifi.container`

### As Podman User

```bash
# Check service status
systemctl --user status unifi

# Stop service
systemctl --user stop unifi

# Start service
systemctl --user start unifi

# Restart service
systemctl --user restart unifi

# View logs
journalctl --user -u unifi -f

# Check health
podman healthcheck run unifi

# View the Quadlet source
cat ~/.config/containers/systemd/unifi.container

# View the auto-generated systemd unit
systemctl --user cat unifi
```

### As Root (managing podman user's service)

```bash
# Check status
sudo -u podman XDG_RUNTIME_DIR=/run/user/1003 systemctl --user status unifi

# Restart
sudo -u podman XDG_RUNTIME_DIR=/run/user/1003 systemctl --user restart unifi

# View logs
sudo -u podman XDG_RUNTIME_DIR=/run/user/1003 journalctl --user -u unifi -n 100
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
Image=docker.io/jacobalberty/unifi:latest
AutoUpdate=registry
```

### Manual Update

```bash
# Check for updates (as podman user)
podman auto-update --dry-run

# Apply updates
podman auto-update
```

## Health Checks

The Quadlet includes built-in health monitoring:

```ini
HealthCmd=curl -f -k https://localhost:8443/manage || exit 1
HealthInterval=30s
HealthTimeout=10s
HealthRetries=3
HealthStartPeriod=300s
```

- **Checks every**: 30 seconds
- **Startup grace period**: 5 minutes (UniFi takes time to initialize)
- **Failure threshold**: 3 consecutive failures

Check health manually:

```bash
podman healthcheck run unifi
```

## Backup and Restore

### Automatic Backups

UniFi Controller creates automatic backups internally:

- **Location**: `/opt/podman/unifi/data/backup/autobackup/`
- **Frequency**: Configured to **daily** (adjusted in UniFi Settings → System → Backup)
- **Timing**: Daily before 2:00 AM (before Restic backup runs)
- **Format**: `.unf` files (complete UniFi configuration snapshots)

### Restic Backup Integration

The Restic backup system backs up **only the autobackup folder**, not the live database:

- **What's backed up**: `/opt/podman/unifi/data/backup/autobackup/*.unf` files
- **Why this approach**: UniFi's autobackups are already complete snapshots, no need to backup live MongoDB database
- **Retention**: Follows Restic retention policy (7 daily, 4 weekly, 12 monthly)
- **Schedule**: Restic runs daily at 2:00 AM, backing up the previous day's autobackup

**Benefits:**

- ✅ No live database backup needed (reduces backup size and complexity)
- ✅ UniFi autobackups are consistent snapshots
- ✅ Restic deduplication works efficiently on stable `.unf` files
- ✅ Long-term retention via Restic (7 daily, 4 weekly, 12 monthly)

**Configuration:**
Make sure UniFi is configured to create daily backups:

1. Open UniFi Controller → Settings → System → Maintenance
2. Set "Auto Backup" to "Daily"
3. Keep retention at desired number of days (internal cleanup)

### Manual Backup

**Via UniFi Web UI:**

1. Log into UniFi Controller at https://unifi.kerberos.fassbender.contact
2. Go to **Settings** → **System** → **Backup**
3. Click **Download Backup**
4. Save the `.unf` file securely

**Via Command Line:**

```bash
# Copy latest autobackup
sudo cp /opt/podman/unifi/data/backup/autobackup/autobackup_*.unf ~/unifi-backup-$(date +%Y%m%d).unf
```

### Restore from Backup

#### Method 1: Via Web UI (Recommended)

1. **Deploy fresh UniFi Controller** (if needed):

   ```bash
   ansible-playbook -i inventory/01-lab.yml noble_base.yml -l docker-vm --tags deploy_unifi_controller_container
   ```

2. **Access UniFi Controller** at https://unifi.kerberos.fassbender.contact

3. **During initial setup**:

   - Select **"Restore from Backup"**
   - Upload your `.unf` backup file
   - Wait for restoration to complete (controller will restart)

4. **If already initialized**:
   - Go to **Settings** → **System** → **Backup**
   - Click **"Choose File"** under "Restore Backup"
   - Select your `.unf` file
   - Click **"Restore"**
   - Controller will restart automatically

#### Method 2: Via File System

1. **Stop UniFi container**:

   ```bash
   sudo -u podman podman stop unifi
   ```

2. **Clear existing data** (CAUTION: This deletes current config):

   ```bash
   sudo rm -rf /opt/podman/unifi/data/*
   ```

3. **Place backup file** in autobackup directory:

   ```bash
   sudo mkdir -p /opt/podman/unifi/data/backup/autobackup
   sudo cp your-backup.unf /opt/podman/unifi/data/backup/autobackup/
   sudo chown -R podman:podman /opt/podman/unifi/data
   ```

4. **Start UniFi container**:

   ```bash
   sudo -u podman podman start unifi
   ```

5. **Controller will auto-detect and restore** from the backup file

#### Method 3: Full Directory Restore (Restic)

If using Restic backups:

```bash
# Stop container
sudo -u podman podman stop unifi

# Restore from Restic
sudo restic -r /mnt/backup/restic-podman restore latest \
  --target / \
  --include /opt/podman/unifi

# Fix permissions
sudo chown -R podman:podman /opt/podman/unifi

# Start container
sudo -u podman podman start unifi
```

### Re-adopting Devices After Restore

After restoring a backup, UniFi devices may need to be re-adopted to the controller:

**Method 1: Via Device SSH (Most Reliable)**

1. **Get SSH credentials**:

   - UniFi Controller → **Settings** → Search for **"SSH"**
   - Note the username and password

2. **SSH into each device**:

   ```bash
   ssh <username>@<device-ip>
   ```

3. **Run set-inform command**:

   ```bash
   set-inform http://<controller_ip>:8080/inform
   ```

   Example:

   ```bash
   set-inform http://192.168.1.118:8080/inform
   ```

4. **Verify adoption**:
   - Device should appear in UniFi Controller
   - Adopt device if shown as "Pending Adoption"

**Method 2: Via UniFi Controller (If Devices Visible)**

1. Go to **Devices** in UniFi Controller
2. Click on any "Disconnected" or "Pending" device
3. Click **"Adopt"** or **"Re-adopt"**

**Common Issues:**

- **Devices not appearing**: Ensure layer 2 connectivity between controller and devices
- **Adoption fails**: Check firewall rules, ensure port 8080 is accessible
- **Different IP**: Use DNS name if available: `http://unifi.kerberos.fassbender.contact:8080/inform`

## Maintenance

### View Container Logs

```bash
# Via systemd (recommended)
journalctl --user -u unifi -f

# Or via Podman directly
podman logs unifi -f
```

### Restart Container

```bash
# Via systemd (recommended)
systemctl --user restart unifi

# Or via Podman directly
podman restart unifi
```

### Access Container Shell

```bash
podman exec -it unifi bash
```

### Check Container Status

```bash
# Via systemd
systemctl --user status unifi

# Via Podman
podman ps -a | grep unifi

# Check health
podman healthcheck run unifi
```

## Troubleshooting

### Controller Not Accessible

1. **Check service status**:

   ```bash
   systemctl --user status unifi
   ```

2. **Check container health**:

   ```bash
   podman healthcheck run unifi
   ```

3. **Check nginx config**:

   ```bash
   sudo nginx -t
   sudo systemctl status nginx
   ```

4. **Check logs**:
   ```bash
   journalctl --user -u unifi -n 100
   # Or
   podman logs unifi --tail 100
   ```

### Service Won't Start

```bash
# Check systemd logs
journalctl --user -u unifi -n 100

# Check Quadlet syntax
cat ~/.config/containers/systemd/unifi.container

# Verify systemd generated the service
systemctl --user list-unit-files | grep unifi

# Force reload
systemctl --user daemon-reload
systemctl --user restart unifi
```

### Container Stuck in Unhealthy State

```bash
# Check health status
podman healthcheck run unifi

# View detailed logs
podman logs unifi | grep -i error

# Check if UniFi is still initializing (may take 5-10 minutes)
podman logs unifi | grep "Initialization"

# If stuck, restart
systemctl --user restart unifi
```

### Devices Not Connecting

1. **Verify port 8080 is open**:

   ```bash
   sudo ss -tulpn | grep 8080
   ```

2. **Check firewall**:

   ```bash
   sudo ufw status
   ```

3. **Test inform URL** from device:
   ```bash
   curl http://<controller_ip>:8080/inform
   ```

### Database Corruption

If controller fails to start after restore:

```bash
# Check logs
journalctl --user -u unifi -n 100
# Or
podman logs unifi

# If database error, may need to restore from earlier backup
# or reset and reconfigure manually
```

### Auto-update Not Working

```bash
# Check auto-update timer
systemctl --user status podman-auto-update.timer

# Check last run
systemctl --user list-timers podman-auto-update.timer

# Manual update check
podman auto-update --dry-run

# Check Quadlet has AutoUpdate
grep AutoUpdate ~/.config/containers/systemd/unifi.container
```

## Container Details

### Runtime Configuration

- **Image**: `docker.io/jacobalberty/unifi:latest`
- **Network**: `podman_bridge` (default)
- **Ports**:
  - `127.0.0.1:8443:8443/tcp` - Web interface (proxied by nginx)
  - `8080:8080/tcp` - Device inform
  - `3478:3478/udp` - STUN
  - `6789:6789/tcp` - Speed test
  - `8880:8880/tcp` - HTTP portal
  - `8843:8843/tcp` - HTTPS portal
  - `10001:10001/udp` - AP discovery
- **Volume**: `/opt/podman/unifi/data` → `/unifi` (Z flag)
- **Environment**:
  - `TZ=Europe/Paris`
  - `LOG_LEVEL=warn`
- **User namespace**: `keep-id` (maps to podman user UID/GID)
- **Restart policy**: `always`
- **Health check**: HTTPS endpoint test every 30s

## Migration from Compose

If migrating from the old podman-compose setup:

1. **Note current settings** (in case you need to rollback)

2. **Stop old service**:

   ```bash
   podman-compose -f /opt/podman/unifi/compose_unifi.yml down
   ```

3. **Deploy Quadlet** (via Ansible):

   ```bash
   ansible-playbook -i inventory noble_base.yml -l target-host
   ```

4. **Wait for initialization** (5-10 minutes):

   ```bash
   podman healthcheck run unifi
   journalctl --user -u unifi -f
   ```

5. **Verify**:

   ```bash
   systemctl --user status unifi
   podman ps
   curl -k https://localhost:8443/manage
   ```

6. **Cleanup old files** (optional):
   ```bash
   rm /opt/podman/unifi/compose_unifi.yml
   ```

## Files and Directories

- **Quadlet file**: `~/.config/containers/systemd/unifi.container`
- **Generated service**: `~/.config/systemd/user/unifi.service` (auto-generated)
- **Container config**: `/opt/podman/unifi/data/`
- **Auto backups**: `/opt/podman/unifi/data/backup/autobackup/`
- **Nginx config**: `/etc/nginx/conf.d/unifi.conf`

## Security Notes

- ✅ **Rootless Podman** - Container runs as non-root user
- ✅ Controller uses self-signed certificate internally (nginx terminates SSL)
- ✅ Web UI only accessible via nginx proxy (localhost binding)
- ✅ Device ports exposed to network for management (required)
- ✅ **User namespace mapping** - Isolates container user from host
- ⚠️ Change default SSH credentials in UniFi settings after setup

## Related Roles

- `podman` - Sets up Podman and rootless environment
- `podman-user` - Creates the podman user
- `nginx_reverse_proxy` - Manages nginx proxy configuration
- `restic-backup` - Handles automated backups (autobackup folder only)

## Additional Resources

- **UniFi Controller**: https://help.ui.com/hc/en-us/categories/200320654-UniFi-Controller
- **Device SSH Access**: https://help.ui.com/hc/en-us/articles/204909374-UniFi-Device-SSH-Connection
- **Backup/Restore**: https://help.ui.com/hc/en-us/articles/226218448
- **Podman Quadlets**: `man podman-systemd.unit`
- **Quadlet docs**: https://docs.podman.io/en/latest/markdown/podman-systemd.unit.5.html
