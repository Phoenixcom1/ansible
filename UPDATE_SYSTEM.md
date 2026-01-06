# Container Update System

Safe container update playbooks with backup and rollback capability.

## Overview

For containers with **auto-update disabled** (like Vaultwarden), use these playbooks to safely update with automatic backups.

## Files

- **`update-container.yml`** - Generic reusable playbook for any container
- **`update-vaultwarden.yml`** - Wrapper for Vaultwarden updates
- More wrappers can be created for other containers

## Quick Start

### Update Vaultwarden

```bash
# Update to latest version
ansible-playbook update-vaultwarden.yml -i inventory/01-lab.yml -l docker-vm

# Update to specific version
ansible-playbook update-vaultwarden.yml -i inventory/01-lab.yml -l docker-vm \
  -e "vaultwarden_version=1.30.1"
```

### Update Any Container

```bash
ansible-playbook update-container.yml -i inventory/01-lab.yml \
  -e "target_host=docker-vm" \
  -e "container_name=my-container" \
  -e "backup_enabled=true"
```

## How It Works

1. **Pre-Update Check**

   - Validates container exists
   - Gets current image ID (for rollback)
   - Displays current version

2. **Backup Phase** (if enabled)

   - Stops container gracefully
   - Creates timestamped backup: `/opt/container-backups/<container>/backup-<timestamp>/`
   - Restarts container
   - Continues with update

3. **Update Phase**

   - Pulls new image
   - Checks if image changed
   - If changed:
     - Stops container
     - Removes old container
     - Systemd recreates with new image
     - Starts container

4. **Verification Phase**

   - Runs health check
   - Displays update summary
   - Provides rollback command if needed

5. **Cleanup**
   - Old image kept for rollback
   - Backup remains in `/tmp/`
   - Manual cleanup instructions provided

## Update Options

### Required Variables

| Variable         | Description         | Example       |
| ---------------- | ------------------- | ------------- |
| `target_host`    | Target server       | `docker-vm`   |
| `container_name` | Container to update | `vaultwarden` |

### Optional Variables

| Variable            | Default  | Description                   |
| ------------------- | -------- | ----------------------------- |
| `backup_enabled`    | `true`   | Create backup before update   |
| `new_image_tag`     | `latest` | Image tag to update to        |
| `skip_health_check` | `false`  | Skip post-update health check |

## Examples

### Update with Backup (Recommended)

```bash
ansible-playbook update-container.yml -i inventory/01-lab.yml \
  -e "target_host=docker-vm" \
  -e "container_name=vaultwarden" \
  -e "backup_enabled=true"
```

### Update to Specific Version

```bash
ansible-playbook update-container.yml -i inventory/01-lab.yml \
  -e "target_host=docker-vm" \
  -e "container_name=vaultwarden" \
  -e "new_image_tag=1.30.1"
```

### Update Without Backup (Not Recommended)

```bash
ansible-playbook update-container.yml -i inventory/01-lab.yml \
  -e "target_host=docker-vm" \
  -e "container_name=vaultwarden" \
  -e "backup_enabled=false"
```

## Rollback Process

If update fails or causes issues:

### Method 1: Use Old Image (Fast)

The playbook provides a rollback command in the summary:

```bash
# Stop container
sudo -u podman systemctl --user stop vaultwarden

# Remove new container
sudo -u podman podman rm vaultwarden

# Run with old image ID
sudo -u podman podman run --replace --name vaultwarden <old-image-id>

# Or restart via systemd (will use Quadlet config)
sudo -u podman systemctl --user daemon-reload
sudo -u podman systemctl --user start vaultwarden
```

### Method 2: Restore from Backup

```bash
# Stop container
sudo -u podman systemctl --user stop vaultwarden

# Restore data from backup
sudo rsync -av /opt/container-backups/vaultwarden/backup-<timestamp>/ \
  /opt/podman/vaultwarden/

# Fix ownership
sudo chown -R podman:podman /opt/podman/vaultwarden/

# Start container
sudo -u podman systemctl --user start vaultwarden
```

### Method 3: Pin to Old Version in Quadlet

Edit the Quadlet file:

```bash
sudo nano /home/podman/.config/containers/systemd/vaultwarden.container
```

Change:

```ini
Image=docker.io/vaultwarden/server:latest
```

To specific version or old image ID:

```ini
Image=docker.io/vaultwarden/server:1.29.0
# Or use image ID:
Image=sha256:abc123def456...
```

Then reload:

```bash
sudo -u podman systemctl --user daemon-reload
sudo -u podman systemctl --user restart vaultwarden
```

## Backup Locations

- **Update backups**: `/opt/container-backups/<container>/backup-<timestamp>/`
- **Restic backups**: Separate daily backups via `restic-backup` role (encrypted, on NAS)

### Cleanup Old Backups

```bash
# List backups
ls -lah /opt/container-backups/

# Remove old backups (after verifying update is stable)
sudo rm -rf /opt/container-backups/vaultwarden/backup-<old-timestamp>

# Or remove all old backups for a container, keep only latest
cd /opt/container-backups/vaultwarden/
ls -t | tail -n +2 | xargs -I {} sudo rm -rf {}
```

## Creating Wrapper Playbooks

To create a wrapper for another container (e.g., Jellyfin):

```yaml
---
# update-jellyfin.yml
- name: Update Jellyfin Container
  import_playbook: update-container.yml
  vars:
    container_name: jellyfin
    backup_enabled: true
    new_image_tag: "{{ jellyfin_version | default('latest') }}"
```

Usage:

```bash
ansible-playbook update-jellyfin.yml -i inventory/01-lab.yml -l docker-vm
```

## Best Practices

### Before Update

1. **Check changelog**: Review release notes for breaking changes
2. **Test in dev**: If possible, test in non-production environment
3. **Verify backups**: Ensure Restic backups are working
4. **Note version**: Document current working version

### During Update

1. **Use backup**: Always enable `backup_enabled=true` for critical services
2. **Specific versions**: For production, pin to specific versions
3. **Monitor health**: Watch health check results
4. **Check logs**: Review container logs after update

### After Update

1. **Verify functionality**: Test critical features
2. **Monitor performance**: Watch for issues over next 24h
3. **Keep backup**: Don't delete backup immediately
4. **Document**: Note successful version upgrade

## Troubleshooting

### Update Fails to Pull Image

```bash
# Manually pull image to see error
sudo -u podman podman pull docker.io/vaultwarden/server:latest

# Check network connectivity
curl -I https://registry.hub.docker.com
```

### Container Won't Start After Update

```bash
# Check service status
sudo -u podman systemctl --user status vaultwarden

# Check container logs
sudo -u podman podman logs vaultwarden

# Check Quadlet syntax
cat /home/podman/.config/containers/systemd/vaultwarden.container
```

### Health Check Fails

```bash
# Manual health check
sudo -u podman podman healthcheck run vaultwarden

# Check if service responds
curl -f http://localhost:5152/alive

# View detailed logs
sudo -u podman podman logs vaultwarden --tail 100
```

### Rollback Needed

See "Rollback Process" section above.

## Integration with Restic

The update system complements the Restic backup system:

- **Update playbook**: Creates immediate pre-update backup in `/opt/container-backups/`
- **Restic**: Creates daily encrypted backups to NAS at 2 AM

Both provide safety:

- Update backup: Fast local copy for immediate rollback (persistent across reboots)
- Restic backup: Long-term retention for disaster recovery (encrypted, offsite)

## Container Auto-Update Policy

| Container       | Auto-Update | Update Method       | Reason                          |
| --------------- | ----------- | ------------------- | ------------------------------- |
| **Vaultwarden** | ❌ Disabled | Manual via playbook | Critical - stores passwords     |
| **Homepage**    | ✅ Enabled  | Automatic           | Low risk - dashboard only       |
| **Jellyfin**    | ✅ Enabled  | Automatic           | Medium risk - can rollback      |
| **UniFi**       | ✅ Enabled  | Automatic           | Medium risk - has health checks |
| **Frigate**     | TBD         | TBD                 | Depends on criticality          |
| **Paperless**   | TBD         | TBD                 | Depends on criticality          |

## Related Documentation

- `roles/deploy_vaultwarden_container/README.md` - Vaultwarden deployment
- `roles/restic-backup/README.md` - Daily backup system
- `README.md` - Main project documentation
