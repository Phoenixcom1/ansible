# Vaultwarden Backup and Restore Guide

## Overview

Vaultwarden uses SQLite as its database backend (stored at `/data/db.sqlite3` inside the container). This guide covers backup and restore procedures for your password vault.

### Architecture

- **Database**: SQLite at `{{ vaultwarden_config_dir }}/db.sqlite3`
- **Attachments**: `{{ vaultwarden_config_dir }}/attachments/`
- **Sends**: `{{ vaultwarden_config_dir }}/sends/`
- **Icon Cache**: `{{ vaultwarden_config_dir }}/icon_cache/` (excluded from backup - regenerates automatically)
- **Config**: `{{ vaultwarden_config_dir }}/config.json`

### Backup Strategy

Our automated backup uses the **compose stack stop method** for maximum safety:

1. Entire compose stack is stopped using `podman-compose down`
2. SQLite database and data files are backed up while offline
3. Stack is immediately restarted using `podman-compose up -d`

This approach ensures **zero corruption risk** for your password vault - critical for security data.

**Why use podman-compose instead of stopping individual containers?**

- Handles multi-container stacks correctly (if you add database/cache later)
- Respects container dependencies and stop order
- Compatible with current compose-based deployment
- Easy migration path to systemd units in the future

---

## Automated Backup (via Restic)

### Configuration

Backup is configured in `roles/restic-backup/defaults/main.yml`:

```yaml
vaultwarden:
  enabled: true
  stop_before_backup: true # Compose stack stopped for safe SQLite backup
  compose_file: "{{ podman_service_dir }}/vaultwarden/compose_vaultwarden.yml"
  project_name: vaultwarden
  paths:
    - "{{ podman_service_dir }}/vaultwarden/data"
  excludes:
    - "*.log"
    - "*/icon_cache/*"
```

### Schedule

- **Frequency**: Daily at 2:00 AM
- **Retention**: 7 daily, 4 weekly, 12 monthly snapshots
- **Downtime**: ~5-10 seconds during backup window

### What's Backed Up

✅ **Included:**

- SQLite database (`db.sqlite3`, `db.sqlite3-wal`, `db.sqlite3-shm`)
- Password attachments
- Sends (temporary shared items)
- Configuration files
- RSA keys

❌ **Excluded:**

- Log files
- Icon cache (regenerates automatically)

---

## Manual Backup Methods

### Method 1: SQLite Backup (Container Running)

Use SQLite's built-in `.backup` command for a consistent backup while the container is running:

```bash
# Backup the database safely
su - podman -c "podman exec vaultwarden sqlite3 /data/db.sqlite3 '.backup /data/db-backup.sqlite3'"

# Copy backup out of container
su - podman -c "podman cp vaultwarden:/data/db-backup.sqlite3 /tmp/vaultwarden-db-$(date +%Y%m%d).sqlite3"

# Clean up backup inside container
su - podman -c "podman exec vaultwarden rm /data/db-backup.sqlite3"

# Also backup attachments and config
tar -czf /tmp/vaultwarden-data-$(date +%Y%m%d).tar.gz -C {{ vaultwarden_config_dir }} .
```

**Pros:** No downtime
**Cons:** Requires SQLite CLI in container, attachments may be inconsistent

### Method 2: Compose Stack Stop (Safest - Recommended)

Stop the compose stack and copy files directly:

```bash
# Stop compose stack
su - podman -c "podman-compose -f {{ podman_service_dir }}/vaultwarden/compose_vaultwarden.yml \
    --project-name vaultwarden down"

# Create backup
tar -czf /tmp/vaultwarden-backup-$(date +%Y%m%d).tar.gz \
    -C {{ vaultwarden_config_dir }} \
    --exclude="icon_cache" \
    --exclude="*.log" \
    .

# Restart compose stack
su - podman -c "podman-compose -f {{ podman_service_dir }}/vaultwarden/compose_vaultwarden.yml \
    --project-name vaultwarden up -d"
```

**Pros:** Guaranteed consistency, handles dependencies, matches automated backup strategy
**Cons:** Brief downtime (~5-10 seconds)

### Method 3: Full Data Directory Copy

Quick copy of entire data directory (use when compose stack is stopped):

```bash
# Stop compose stack
su - podman -c "podman-compose -f {{ podman_service_dir }}/vaultwarden/compose_vaultwarden.yml \
    --project-name vaultwarden down"

# Copy data directory
cp -a {{ vaultwarden_config_dir }} {{ vaultwarden_config_dir }}.backup-$(date +%Y%m%d)

# Restart compose stack
su - podman -c "podman-compose -f {{ podman_service_dir }}/vaultwarden/compose_vaultwarden.yml \
    --project-name vaultwarden up -d"
```

**Pros:** Fastest, simplest
**Cons:** Requires disk space, compose stack must be stopped

---

## Restore Procedures

### Method 1: Restore from Restic Backup

```bash
# List available snapshots
export RESTIC_REPOSITORY=/mnt/backup/restic-podman
export RESTIC_PASSWORD_FILE=/root/.restic_password
restic snapshots --tag=vaultwarden

# Stop compose stack
su - podman -c "podman-compose -f {{ podman_service_dir }}/vaultwarden/compose_vaultwarden.yml \
    --project-name vaultwarden down"

# Backup current data (safety)
mv {{ vaultwarden_config_dir }} {{ vaultwarden_config_dir }}.old-$(date +%Y%m%d)

# Restore from snapshot
restic restore <snapshot-id> \
    --tag=vaultwarden \
    --target /

# Fix permissions
chown -R 1003:1003 {{ vaultwarden_config_dir }}

# Start compose stack
su - podman -c "podman-compose -f {{ podman_service_dir }}/vaultwarden/compose_vaultwarden.yml \
    --project-name vaultwarden up -d"

# Verify service is accessible
curl -f http://localhost:<port>/alive || echo "Service health check failed"
```

### Method 2: Restore from Manual Backup

```bash
# Stop compose stack
su - podman -c "podman-compose -f {{ podman_service_dir }}/vaultwarden/compose_vaultwarden.yml \
    --project-name vaultwarden down"

# Backup current data
mv {{ vaultwarden_config_dir }} {{ vaultwarden_config_dir }}.old-$(date +%Y%m%d)

# Extract backup
mkdir -p {{ vaultwarden_config_dir }}
tar -xzf /path/to/vaultwarden-backup.tar.gz -C {{ vaultwarden_config_dir }}

# Fix permissions
chown -R 1003:1003 {{ vaultwarden_config_dir }}

# Start compose stack
su - podman -c "podman-compose -f {{ podman_service_dir }}/vaultwarden/compose_vaultwarden.yml \
    --project-name vaultwarden up -d"
```

### Method 3: Restore Individual Users/Items

If you need to restore specific data, use the Vaultwarden admin panel or API:

```bash
# Access admin panel (if enabled)
# Navigate to: https://{{ vaultwarden_domain }}/admin
# Enter admin token from config

# Export user vault via web interface:
# 1. Login as user
# 2. Tools → Export Vault
# 3. Choose format (JSON, CSV, encrypted JSON)

# Import to restored instance:
# 1. Tools → Import Data
# 2. Select format and file
# 3. Import
```

---

## Important Notes

### Database Integrity

**⚠️ Critical**: SQLite databases MUST NOT be copied while the database is being written to. Our backup strategy handles this by:

- **Automated backups**: Stop container (5s downtime)
- **Manual backups**: Use SQLite `.backup` command OR stop container

**Never** use `cp` or `rsync` on `db.sqlite3` while the container is running - this can cause corruption.

### Admin Token Recovery

If you lose access to the admin panel:

```bash
# Generate new admin token
echo -n "your-new-password" | argon2 "$(openssl rand -base64 32)" -e -id -k 65540 -t 3 -p 4

# Update config (compose stack must be stopped)
su - podman -c "podman-compose -f {{ podman_service_dir }}/vaultwarden/compose_vaultwarden.yml \
    --project-name vaultwarden down"

# Edit config.json or set environment variable in compose file
# ADMIN_TOKEN=<your-new-argon2-hash>

su - podman -c "podman-compose -f {{ podman_service_dir }}/vaultwarden/compose_vaultwarden.yml \
    --project-name vaultwarden up -d"
```

Or disable admin token in compose file:

```yaml
environment:
  - ADMIN_TOKEN= # Empty = disabled (NOT recommended for production)
```

### Data Recovery Priority

In disaster recovery scenarios, prioritize:

1. **Database** (`db.sqlite3`) - Contains all passwords, TOTP seeds, secure notes
2. **Attachments** - User-uploaded files
3. **Config** - Settings and admin token
4. **Sends** - Temporary shares (time-limited, less critical)

### Testing Restores

**Best Practice**: Test your backup/restore procedure quarterly:

```bash
# Create test environment
mkdir -p /tmp/vaultwarden-test
tar -xzf /path/to/backup.tar.gz -C /tmp/vaultwarden-test

# Verify database integrity
sqlite3 /tmp/vaultwarden-test/db.sqlite3 "PRAGMA integrity_check;"
# Should output: ok

# Check user count
sqlite3 /tmp/vaultwarden-test/db.sqlite3 "SELECT COUNT(*) FROM users;"

# Clean up
rm -rf /tmp/vaultwarden-test
```

---

## Troubleshooting

### Container Won't Start After Restore

```bash
# Check logs
su - podman -c "podman logs vaultwarden"

# Common issues:
# 1. Permission problems
chown -R 1003:1003 {{ vaultwarden_config_dir }}

# 2. Corrupted database
sqlite3 {{ vaultwarden_config_dir }}/db.sqlite3 "PRAGMA integrity_check;"

# 3. WAL file issues (if using WAL mode)
rm -f {{ vaultwarden_config_dir }}/db.sqlite3-wal
rm -f {{ vaultwarden_config_dir }}/db.sqlite3-shm
```

### Database Locked Errors

```bash
# Check for stale processes
su - podman -c "podman exec vaultwarden fuser /data/db.sqlite3"

# Restart compose stack
su - podman -c "podman-compose -f {{ podman_service_dir }}/vaultwarden/compose_vaultwarden.yml \
    --project-name vaultwarden restart"

# If persistent, check database integrity
sqlite3 {{ vaultwarden_config_dir }}/db.sqlite3 "PRAGMA integrity_check;"
```

### Users Can't Login After Restore

```bash
# Verify database is readable
su - podman -c "podman exec vaultwarden sqlite3 /data/db.sqlite3 'SELECT COUNT(*) FROM users;'"

# Check container logs
su - podman -c "podman logs vaultwarden | tail -50"

# Verify web vault is accessible
curl -f http://localhost:<port>/ || echo "Web vault not responding"

# Check DNS/domain configuration
curl -f https://{{ vaultwarden_domain }}/ || echo "Domain not accessible"
```

### Missing Attachments

Attachments are stored separately from the database:

```bash
# List attachments
ls -lah {{ vaultwarden_config_dir }}/attachments/

# Verify attachment directory permissions
chown -R 1003:1003 {{ vaultwarden_config_dir }}/attachments

# Check attachment paths in database
su - podman -c "podman exec vaultwarden sqlite3 /data/db.sqlite3 'SELECT * FROM attachments;'"
```

---

## Migration Scenarios

### From Bitwarden Cloud to Self-Hosted

1. Export from Bitwarden cloud (JSON format)
2. Import to Vaultwarden via web interface
3. Verify all items imported correctly
4. Change master password (recommended)

### To PostgreSQL (Optional)

Vaultwarden supports PostgreSQL for larger deployments:

```bash
# Install PostgreSQL tools
apt install postgresql-client

# Export SQLite to SQL dump
su - podman -c "podman exec vaultwarden sqlite3 /data/db.sqlite3 .dump > /tmp/vaultwarden.sql"

# Convert and import to PostgreSQL (manual schema mapping required)
# This is complex - only needed for large deployments (>1000 users)
```

---

## Security Recommendations

1. **Encrypt Backups**: Restic provides encryption by default
2. **Test Restores**: Quarterly restore tests to verify backup integrity
3. **Secure Admin Token**: Store admin token hash securely, never in plaintext
4. **Monitor Logs**: Check logs after backups for any errors
5. **Offsite Backup**: Consider additional backup to cloud storage (S3, B2)
6. **Access Control**: Restrict access to backup files - they contain encrypted vaults

---

## Backup Verification

Verify your backup is valid:

```bash
# Check database integrity
sqlite3 /path/to/backup/db.sqlite3 "PRAGMA integrity_check;"

# Count users
sqlite3 /path/to/backup/db.sqlite3 "SELECT COUNT(*) FROM users;"

# Count ciphers (password entries)
sqlite3 /path/to/backup/db.sqlite3 "SELECT COUNT(*) FROM ciphers;"

# List tables
sqlite3 /path/to/backup/db.sqlite3 ".tables"
```

Expected tables: `attachments`, `ciphers`, `collections`, `devices`, `folders`, `users`, `organizations`, etc.

---

## Resources

- [Vaultwarden Wiki](https://github.com/dani-garcia/vaultwarden/wiki)
- [SQLite Backup Documentation](https://www.sqlite.org/backup.html)
- [Restic Backup Tool](https://restic.net/)

**Remember**: Your password vault is critical security infrastructure. Always test backups and restores in a non-production environment first!
