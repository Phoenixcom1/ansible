# Restic Backup Role

Automated backup solution using Restic for Podman containers to NAS storage.

## Features

- Encrypted, deduplicated incremental backups
- Automatic retention policy (7 daily, 4 weekly, 12 monthly)
- Systemd timer for automated daily backups
- TrueNAS NFS repository support
- Per-service backup configuration
- Comprehensive logging

## Configuration

### Required Vault Variable

Create the dedicated TrueNAS SMB account password in the vaulted companion
inventory (`inventory/01-lab.secrets.yml`):

```yaml
truenas_restic_smb_password: "use-a-long-unique-password"
```

The `truenas_smb_provision` role creates the encrypted
`tank/apps/podman-backups` dataset, its `podman-backups` SMB share, and the
`restic-backup` TrueNAS account. `restic-backup` writes the corresponding
root-only mount credentials to `/root/.smb_restic_creds`.

### Basic Setup (defaults/main.yml)

```yaml
# TrueNAS NFS configuration
restic_nas_source: "truenas.example.net:/mnt/tank/apps/podman-backups"
restic_nas_mount_point: "/mnt/backup"
restic_repository: "{{ restic_nas_mount_point }}/restic-{{ inventory_hostname }}"

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

## Pre-Backup Actions

The backup script automatically performs service-specific pre-backup tasks:

### Paperless Document Export

Before backing up Paperless files, the script automatically runs:

```bash
su - podman -c "podman exec paperless-webserver document_exporter /usr/src/paperless/export"
```

**What this does:**

- Creates a consistent JSON export of all documents and metadata
- Exports to `/opt/podman/paperless/export/` (included in backup)
- Ensures database consistency (safer than backing up SQLite while running)
- Preserves all tags, correspondents, document types, custom fields

**Benefits:**

- Guaranteed consistent backup (no corruption risk)
- Human-readable export format (JSON + files)
- Easy to restore with `document_importer`
- Can be imported into fresh Paperless instance

**Note:** If Paperless container is not running, the script continues with file backup only.

### Container Stop for Database Safety

Services with `stop_before_backup: true` are stopped before backup. Vaultwarden
uses its rootless Podman Quadlet user service:

```yaml
vaultwarden:
  enabled: true
  stop_before_backup: true
  systemd_user_unit: vaultwarden.service
  systemd_user: "{{ podman_username }}"
  paths:
    - "{{ podman_service_dir }}/vaultwarden/data"
```

**What this does:**

1. Stops the Quadlet-managed `vaultwarden.service`
2. Backs up all data while containers are stopped
3. Starts `vaultwarden.service` again

**Why use the managed service rather than an individual container stop?**

- **Managed lifecycle**: Systemd preserves the Quadlet service definition
- **Correct identity**: The command uses the owning rootless Podman user
- **Reliable restart**: Systemd restores the service in its expected state

**When to use this strategy:**

- Services with SQLite databases (Vaultwarden, potentially paperless)
- Critical data requiring zero corruption risk (passwords, financial data)
- Services without built-in export tools

**Downtime considerations:**

- Typical stop time: 5-10 seconds
- Backup window: 2:00 AM (minimal user impact)
- Compose restart is faster than individual container starts

**Alternative approaches by service type:**

| Service     | Strategy            | Reason                                 |
| ----------- | ------------------- | -------------------------------------- |
| Paperless   | `document_exporter` | Has built-in export, no downtime       |
| Vaultwarden | Stop container      | Passwords require zero corruption risk |
| UniFi       | File backup         | Built-in auto-backups, can run live    |
| Homepage    | File backup         | Static config files, no database       |

## Services Backed Up

Complete overview of all configured services:

| Service         | Strategy          | Downtime | Database Type | Why This Approach?                     |
| --------------- | ----------------- | -------- | ------------- | -------------------------------------- |
| **Homepage**    | Live backup       | None     | None          | Static config files only               |
| **UniFi**       | Live backup       | None     | MongoDB       | Has built-in auto-backups              |
| **Paperless**   | Document exporter | None     | SQLite        | App-level export ensures consistency   |
| **Vaultwarden** | Stop Quadlet      | ~5s      | SQLite        | Passwords require zero corruption risk |
| **Jellyfin**    | Stop compose      | ~5s      | SQLite        | Media library database                 |
| **Frigate**     | Stop compose      | ~5s      | SQLite        | Camera events and detection data       |

**Total downtime during backup**: ~15 seconds (services with `stop_before_backup` run simultaneously at 2:00 AM)

**Backup schedule**: Daily at 2:00 AM  
**Retention**: 7 daily, 4 weekly, 12 monthly snapshots

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
sudo restic -r /mnt/backup/restic-podman-vm-pve0 snapshots
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

**Restore Vaultwarden data (SELinux-safe):**

Stop the Vaultwarden service first, then restore directly into the data directory using the xattr filter for SELinux:

```bash
sudo systemctl stop podman.service

sudo restic -r /mnt/backup/restic-podman restore 4dcf0086 \
  --target /opt/podman/vaultwarden/data \
  --include /opt/podman/vaultwarden/data \
  --exclude-xattr 'security.*'
```

If the service is managed as a user unit instead of a system service, use the user-scoped equivalent before running the restore:

```bash
sudo -u ansible systemctl --user stop vaultwarden.service
```

Permissions have been fine in this setup, so no additional ownership change is normally required.

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
