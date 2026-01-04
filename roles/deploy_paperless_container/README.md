# Paperless-ngx Container Role

Deploys Paperless-ngx document management system in Podman containers with full-text search, OCR, and workflow automation.

## Features

- Paperless-ngx with Tika and Gotenberg integration
- Redis cache for performance
- CIFS/SMB network mount for consume directory
- OCR with Tesseract
- Full-text search
- Automatic tagging and workflows
- Email document linking scripts

## Architecture

**Containers:**

- `paperless-webserver`: Main application (SQLite database)
- `paperless-redis`: Redis cache
- `paperless-gotenberg`: PDF rendering
- `paperless-tika`: Document parsing

**Data Structure:**

```
/opt/podman/paperless/
├── data/            # SQLite database + index
├── media/           # Original + archived documents
├── export/          # Bulk exports
├── consume/         # Network mount for new documents
├── scripts/         # Custom Python scripts
├── custom-cont-init.d/  # Init scripts
└── redisdata/       # Redis cache (ephemeral)
```

## Configuration

### Default Settings (defaults/main.yml)

```yaml
paperless_domain: "paperless.kerberos.fassbender.contact"
paperless_port: 8810
paperless_data_dir: "/opt/podman/paperless/data"
paperless_media_dir: "/opt/podman/paperless/media"
```

### Network Mount

Consume directory is mounted from NAS:

```yaml
paperless_network_mount_source: "//datenbunker.local/Paperless/Consume"
```

## Backup and Restore

### What to Backup

**Critical (Must Backup):**

- `/opt/podman/paperless/data` - SQLite database + search index
- `/opt/podman/paperless/media` - All document files
- `/opt/podman/paperless/export` - Export archives (optional)

**Optional:**

- `/opt/podman/paperless/scripts` - Custom scripts (if modified)
- `/opt/podman/paperless/custom-cont-init.d` - Init scripts (if modified)

**Skip:**

- `/opt/podman/paperless/redisdata` - Redis cache (regenerates automatically)
- `/opt/podman/paperless/consume` - Network mount (backed up on NAS)

### Database Considerations

Paperless uses **SQLite** by default, stored at:

```
/opt/podman/paperless/data/db.sqlite3
```

**SQLite Backup Best Practices:**

1. **Stop container for consistent backup** (recommended for critical restores)
2. **Hot backup** is usually fine for Restic (copy-on-write safe)
3. **Built-in exporter** creates JSON export with all metadata

### Method 1: Restic Automated Backup (Recommended)

Restic automatically backs up Paperless data if configured in `restic-backup` role.

**Backup includes:**

- SQLite database
- All documents (original + archived)
- Search index
- Custom scripts

**Excluded automatically:**

- Redis cache
- Consume directory (network mount)
- Thumbnails (regenerated on access)

**Verify backup:**

```bash
sudo restic -r /mnt/backup/restic-podman snapshots --tag paperless
```

### Method 2: Paperless Built-in Export

Paperless has a built-in document exporter that creates a complete JSON export:

**Create export:**

```bash
# Via container
sudo -u podman podman exec paperless-webserver document_exporter /usr/src/paperless/export

# Or via management command
sudo -u podman podman exec paperless-webserver python3 manage.py document_exporter /usr/src/paperless/export
```

**Export contains:**

- All documents (original files)
- Full database dump (JSON format)
- All metadata (tags, correspondents, document types, etc.)
- Custom fields
- Workflows

**Export location:**

```
/opt/podman/paperless/export/
```

**Download export:**

```bash
# Create export
sudo -u podman podman exec paperless-webserver document_exporter /usr/src/paperless/export

# Find latest export
ls -lh /opt/podman/paperless/export/

# Copy to safe location
sudo cp -r /opt/podman/paperless/export/export-YYYYMMDD /backup/paperless-export-$(date +%Y%m%d)
```

### Method 3: Manual Database Backup

For SQLite-specific backup:

```bash
# Stop container (ensures consistency)
sudo -u podman podman stop paperless-webserver

# Backup database file
sudo cp /opt/podman/paperless/data/db.sqlite3 /backup/paperless-db-$(date +%Y%m%d).sqlite3

# Backup entire data directory
sudo tar czf /backup/paperless-data-$(date +%Y%m%d).tar.gz /opt/podman/paperless/data

# Start container
sudo -u podman podman start paperless-webserver
```

**Hot backup (while running):**

```bash
# SQLite online backup (safer than cp)
sudo -u podman podman exec paperless-webserver sqlite3 /usr/src/paperless/data/db.sqlite3 ".backup /usr/src/paperless/data/backup.db"

# Copy backup out
sudo cp /opt/podman/paperless/data/backup.db /backup/paperless-db-$(date +%Y%m%d).sqlite3
```

## Restore Procedures

### Restore Method 1: Full Restic Restore

**Complete disaster recovery:**

```bash
# Stop containers
sudo -u podman podman-compose -f /opt/podman/paperless/compose_paperless.yml down

# Restore from Restic
sudo restic -r /mnt/backup/restic-podman restore latest \
  --target / \
  --include /opt/podman/paperless/data \
  --include /opt/podman/paperless/media \
  --include /opt/podman/paperless/export

# Fix permissions
sudo chown -R podman:podman /opt/podman/paperless

# Start containers
sudo -u podman podman-compose -f /opt/podman/paperless/compose_paperless.yml up -d

# Verify
sudo -u podman podman logs paperless-webserver -f
```

### Restore Method 2: From Paperless Export

**Restore from document_exporter archive:**

```bash
# Stop existing containers
sudo -u podman podman-compose -f /opt/podman/paperless/compose_paperless.yml down

# Clear existing data (CAUTION!)
sudo rm -rf /opt/podman/paperless/data/*
sudo rm -rf /opt/podman/paperless/media/*

# Copy export to import location
sudo mkdir -p /opt/podman/paperless/import
sudo cp -r /backup/paperless-export-YYYYMMDD/* /opt/podman/paperless/import/
sudo chown -R podman:podman /opt/podman/paperless/import

# Start containers (they need to be running for import)
sudo -u podman podman-compose -f /opt/podman/paperless/compose_paperless.yml up -d

# Wait for containers to be healthy
sleep 30

# Run document importer
sudo -u podman podman exec paperless-webserver document_importer /usr/src/paperless/import

# Monitor import progress
sudo -u podman podman logs paperless-webserver -f
```

**Note:** Document importer preserves:

- All document metadata
- Tags, correspondents, document types
- Custom fields
- Creation/modification dates
- File relationships

### Restore Method 3: Manual Database Restore

**Restore SQLite database only:**

```bash
# Stop webserver
sudo -u podman podman stop paperless-webserver

# Backup current database (just in case)
sudo cp /opt/podman/paperless/data/db.sqlite3 /opt/podman/paperless/data/db.sqlite3.old

# Restore database from backup
sudo cp /backup/paperless-db-YYYYMMDD.sqlite3 /opt/podman/paperless/data/db.sqlite3
sudo chown podman:podman /opt/podman/paperless/data/db.sqlite3

# Start webserver
sudo -u podman podman start paperless-webserver

# Rebuild search index (if needed)
sudo -u podman podman exec paperless-webserver python3 manage.py document_index reindex
```

### Restore Method 4: Selective File Restore

**Restore specific documents from Restic:**

```bash
# List files in snapshot
sudo restic -r /mnt/backup/restic-podman ls latest | grep paperless/media

# Restore specific file
sudo restic -r /mnt/backup/restic-podman restore latest \
  --target /tmp/restore \
  --include /opt/podman/paperless/media/documents/2024/01/document.pdf

# Copy restored file
sudo cp /tmp/restore/opt/podman/paperless/media/documents/2024/01/document.pdf \
  /opt/podman/paperless/media/documents/2024/01/
sudo chown podman:podman /opt/podman/paperless/media/documents/2024/01/document.pdf
```

## Maintenance

### Rebuild Search Index

If search isn't working after restore:

```bash
sudo -u podman podman exec paperless-webserver python3 manage.py document_index reindex
```

### Check Database Integrity

```bash
sudo -u podman podman exec paperless-webserver sqlite3 /usr/src/paperless/data/db.sqlite3 "PRAGMA integrity_check;"
```

### Optimize Database

```bash
sudo -u podman podman exec paperless-webserver sqlite3 /usr/src/paperless/data/db.sqlite3 "VACUUM;"
```

### Clean Thumbnails Cache

Thumbnails are regenerated automatically:

```bash
sudo rm -rf /opt/podman/paperless/media/thumbnails/*
# Access any document in UI to regenerate thumbnails
```

## Automated Backup Strategy

**Recommended approach:**

1. **Restic daily backups** (2 AM via systemd timer)

   - Backs up data, media, scripts
   - Incremental, encrypted, deduplicated
   - Retention: 7 daily, 4 weekly, 12 monthly

2. **Weekly full export** (Sunday 3 AM)

   ```bash
   # Add to crontab or systemd timer
   0 3 * * 0 podman exec paperless-webserver document_exporter /usr/src/paperless/export
   ```

3. **Monthly export to offsite** (first of month)
   ```bash
   # Copy export to external storage
   rsync -av /opt/podman/paperless/export/ user@backup-server:/backups/paperless/
   ```

## Network Mount (Consume Directory)

The consume directory is mounted from NAS:

**Check mount:**

```bash
mount | grep paperless
```

**Manual mount:**

```bash
sudo mount -t cifs //datenbunker.local/Paperless/Consume \
  /opt/podman/paperless/consume \
  -o credentials=/root/.paperless_smbcreds,uid=297607,gid=297607
```

**Consume directory is NOT backed up** - it's already on the NAS and should be backed up there.

## Troubleshooting

### Documents Not Processing

```bash
# Check consumer process
sudo -u podman podman exec paperless-webserver ps aux | grep consumer

# Check logs
sudo -u podman podman logs paperless-webserver | grep -i consume

# Restart container
sudo -u podman podman restart paperless-webserver
```

### Database Locked Errors

```bash
# Check for hung processes
sudo -u podman podman exec paperless-webserver ps aux

# Restart if needed
sudo -u podman podman restart paperless-webserver
```

### Import Fails

```bash
# Check import directory permissions
ls -la /opt/podman/paperless/import

# Check logs
sudo -u podman podman logs paperless-webserver -f

# Retry import
sudo -u podman podman exec paperless-webserver document_importer /usr/src/paperless/import
```

## Files and Directories

- **Compose file**: `/opt/podman/paperless/compose_paperless.yml`
- **Environment**: `/opt/podman/paperless/paperless.env`
- **Database**: `/opt/podman/paperless/data/db.sqlite3`
- **Documents**: `/opt/podman/paperless/media/documents/`
- **Exports**: `/opt/podman/paperless/export/`
- **Nginx config**: `/etc/nginx/conf.d/paperless.kerberos.fassbender.contact.conf`

## Security Notes

- Database contains document metadata (consider encryption at rest)
- Media directory contains all original documents
- Redis cache is ephemeral (no sensitive data persistence)
- Consume directory should have restricted permissions
- Backups should be encrypted (Restic does this automatically)

## Additional Resources

- [Paperless-ngx Documentation](https://docs.paperless-ngx.com/)
- [Backup/Restore Guide](https://docs.paperless-ngx.com/administration/#backup)
- [Document Exporter](https://docs.paperless-ngx.com/administration/#exporter)
- [Database Management](https://docs.paperless-ngx.com/administration/#database)
