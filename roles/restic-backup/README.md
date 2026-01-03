# Restic Backup Role

Automated backup solution using Restic for Podman containers to NAS storage.

## Features

- Encrypted, deduplicated incremental backups
- Automatic retention policy (7 daily, 4 weekly, 12 monthly)
- Systemd timer for automated daily backups
- NAS mount support (CIFS/SMB)
- Per-service backup configuration
- Comprehensive logging

## Configuration

### Basic Setup (defaults/main.yml)

```yaml
# NAS configuration
restic_nas_source: "//datenbunker.local/Backup"
restic_nas_mount_point: "/mnt/backup"

# Services to backup
restic_backup_services:
  homepage:
    enabled: true
    paths:
      - "{{ podman_service_dir }}/homepage"
```

### Adding More Services

Edit `defaults/main.yml` and add services:

```yaml
restic_backup_services:
  homepage:
    enabled: true
    paths:
      - "{{ podman_service_dir }}/homepage"

  unifi:
    enabled: true
    paths:
      - "{{ podman_service_dir }}/unifi"
    excludes:
      - "*/logs/*"

  paperless:
    enabled: true
    paths:
      - "{{ podman_service_dir }}/paperless/data"
      - "{{ podman_service_dir }}/paperless/media"
      - "{{ podman_service_dir }}/paperless/export"
    excludes:
      - "*/redisdata/*"
```

## Usage

### Deploy with Ansible

```bash
ansible-playbook -i inventory/01-lab.yml noble_base.yml -l docker-vm
```

### Manual Operations

**Test backup immediately:**

```bash
sudo systemctl start restic-backup.service
```

**Watch backup progress:**

```bash
sudo journalctl -u restic-backup.service -f
# or
sudo tail -f /var/log/restic-backup.log
```

**List backups:**

```bash
sudo restic -r /mnt/backup/restic-podman snapshots
```

**List files in a snapshot:**

```bash
sudo restic -r /mnt/backup/restic-podman ls <snapshot-id>
```

**Restore specific files:**

```bash
sudo restic -r /mnt/backup/restic-podman restore <snapshot-id> \
  --target /tmp/restore \
  --include /opt/podman/homepage
```

**Check backup integrity:**

```bash
sudo restic -r /mnt/backup/restic-podman check
```

**View repository stats:**

```bash
sudo restic -r /mnt/backup/restic-podman stats
```

## Timer Management

**Check timer status:**

```bash
sudo systemctl status restic-backup.timer
```

**View next scheduled run:**

```bash
sudo systemctl list-timers restic-backup.timer
```

**Disable automatic backups:**

```bash
sudo systemctl stop restic-backup.timer
sudo systemctl disable restic-backup.timer
```

**Enable automatic backups:**

```bash
sudo systemctl enable --now restic-backup.timer
```

## Password Management

The restic password is stored in `/root/.restic-password`.

**IMPORTANT:** Save this password securely! You cannot restore backups without it.

To view the password:

```bash
sudo cat /root/.restic-password
```

## Troubleshooting

**NAS mount issues:**

```bash
# Check mount status
mount | grep backup

# Manually mount
sudo mount -t cifs //datenbunker.local/Backup /mnt/backup \
  -o credentials=/root/.smbcredentials
```

**Service failures:**

```bash
# View detailed logs
sudo journalctl -u restic-backup.service --no-pager

# Check service status
sudo systemctl status restic-backup.service
```

**Repository locked:**

```bash
# If backup was interrupted
sudo restic -r /mnt/backup/restic-podman unlock
```

## Files Created

- `/opt/scripts/restic-backup.sh` - Backup script
- `/etc/systemd/system/restic-backup.service` - Systemd service
- `/etc/systemd/system/restic-backup.timer` - Systemd timer
- `/root/.restic-password` - Encryption password
- `/var/log/restic-backup.log` - Backup log
- `/mnt/backup/restic-podman/` - Restic repository
