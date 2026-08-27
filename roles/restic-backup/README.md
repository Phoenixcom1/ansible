# Restic Backup Role

Automated backup solution using Restic for Podman containers to NAS storage.

## Features

- Encrypted, deduplicated incremental backups
- Automatic retention policy (7 daily, 4 weekly, 12 monthly)
- Systemd timer for automated daily backups
- TrueNAS NFS/CIFS repository support, plus REST server (`rest:`) destinations
- Back up to multiple destinations at once (e.g. local NAS + off-site REST server)
- Per-service backup configuration, including restricting a service to specific destinations
- Per-destination fault isolation and timeouts - one bad destination never blocks the others
- Comprehensive, timestamped logging

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

### Backing Up to Multiple Destinations

By default, every enabled service is backed up only to the primary
`restic_repository` (mounted from `restic_nas_source`). To also back up to a
second (or third, ...) destination, e.g. an off-site NAS, set
`restic_additional_destinations` in the host/group vars:

```yaml
restic_additional_destinations:
  - name: offsite
    repository: "/mnt/backup-offsite/restic-{{ inventory_hostname }}"
    password_file: "/root/.restic-password-offsite"
    nas:
      enabled: true
      fstype: nfs
      source: "truenas2.example.net:/mnt/tank/apps/podman-backups-offsite"
      mount_point: "/mnt/backup-offsite"
      mount_options: "_netdev"
```

Each entry needs its own `repository` and `password_file` (restic
repositories cannot be shared between independent password secrets/dirs).
Omit `nas` entirely if the destination path is already mounted some other
way (e.g. a local disk, or a share mounted outside this role).

Every enabled service is backed up to the primary destination and to each
entry in `restic_additional_destinations`, in turn, using a single
pre-/post-backup service stop/start cycle. Pruning and repository statistics
also run once per destination.

To compare snapshots on a non-primary destination:

```bash
sudo /opt/scripts/restic-compare.sh immich offsite
```

### Restricting a Service to Specific Destinations

By default every enabled service is backed up to every configured
destination. To send a service to only a subset (e.g. it already has its
own backup elsewhere and only needs the off-site copy), add a
`destinations` list (matching each destination's `name`) to that service:

```yaml
restic_backup_services:
  immich:
    ...
    destinations:
      - rest-offsite
```

Services without a `destinations` key keep going to every destination, so
existing configs are unaffected.

### Overriding a Service Per Host

`restic_backup_services` is a shared role default. Rather than redefining a
whole service's config in inventory just to tweak one field, use
`restic_service_overrides` to merge specific keys (`paths`, `excludes`,
`destinations`, etc.) onto a service for that host only:

```yaml
restic_service_overrides:
  immich:
    destinations:
      - rest-offsite
    paths:
      - /srv/containers/immich-data # real upload dir, if it differs from the role's default guess
      - "{{ podman_service_dir }}/immich/postgres"
      - "{{ podman_service_dir }}/immich/immich.env"
```

This is the recommended way to correct a service's paths when they don't
match this role's built-in defaults for that service (e.g. when
`deploy_immich_container`'s `immich_upload_dir` points at an external
mount instead of the default guess), without affecting other hosts that
might use different paths for the same service name.

**Note:** each path is checked with `[ -e ... ]` (exists, file or
directory) before backing it up - both directories (e.g. an upload folder)
and single files (e.g. `immich.env`) are backed up correctly.

### REST Server Destinations

A `rest:` repository (restic's own REST server backend, e.g. `restic/rest-server`)
needs no mount at all - restic talks to it directly over HTTP(S). If the REST
server requires HTTP basic auth, add a `rest` block instead of `nas`:

```yaml
restic_additional_destinations:
  - name: rest-offsite
    repository: "rest:https://backup.example.net/example-repo"
    password_file: "/root/.restic-password-rest-offsite"
    rest:
      username: "restic-user"
      password: "{{ vaulted_restic_rest_offsite_password }}"
```

The username/password are written to a root-only (`0600`) credentials file
(`/root/.restic-rest-<name>-creds` by default) rather than embedded in the
world-readable backup script; the script sources it before talking to that
destination. The primary destination supports the same auth via
`restic_rest_username`/`restic_rest_password`/`restic_rest_credentials_file`
if `restic_repository` itself is a `rest:` URL.

**Getting the URL right (see Troubleshooting below for the details on each):**

- The scheme (`http`/`https`) must match what's actually listening on that
  port. `rest-server` itself defaults to plain HTTP; if there's a reverse
  proxy terminating TLS in front of it, point restic at the proxy's HTTPS
  port/host, not `rest-server`'s own plain-HTTP port.
- If `rest-server` is running with `--private-repos`, the repository path's
  **first segment must equal the htpasswd username** - e.g. user `restic`
  requires a path like `rest:https://host/restic/<repo-name>`, not just
  `rest:https://host/<repo-name>`.

### Destination Fault Isolation & Timeouts

Every restic call (init/backup/prune/stats) is wrapped with `timeout` so an
unreachable or hung destination (e.g. a REST server that's down) fails after
a bounded time instead of blocking the whole run indefinitely. Default is
`restic_command_timeout_seconds: 1800` (30 min); override per destination:

```yaml
restic_additional_destinations:
  - name: rest-offsite
    command_timeout_seconds: 300
    ...
```

If one destination fails (init, backup, prune, or a hung connection), it's
marked bad and skipped for the rest of that run - other destinations, other
services, and the container stop/restart cycle all still complete normally.
Only at the very end does the script exit non-zero (visible via
`systemctl status restic-backup.service` / `journalctl`) if any destination
failed, so monitoring still catches it without anything else being aborted.

Every log line is timestamped (`[2026-08-26 22:00:00] ...`), so a stuck step
shows up as a visible gap between log lines - see Troubleshooting below.

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

**REST destination: "server gave HTTP response to HTTPS client":**

The repository URL's scheme doesn't match what's actually listening on that
host/port. `rest-server` itself defaults to plain HTTP; if you're using
`rest:https://...`, make sure that hostname/port is actually a TLS-terminating
reverse proxy in front of it, not `rest-server`'s own port. Check what's
really listening with `curl -v https://<host>:<port>/`.

**REST destination: "x509: certificate signed by unknown authority":**

The TLS handshake is reaching a server with a certificate the client doesn't
trust - even if the cert looks fine in a browser or `curl` elsewhere. This
usually means the reverse proxy isn't serving the full chain (leaf +
intermediate); Go's TLS client (used by `restic`) is stricter about this than
curl/browsers, which can silently paper over a missing intermediate. Verify
with, from the backup host itself:

```bash
echo | openssl s_client -connect <host>:443 -servername <host> -showcerts 2>/dev/null \
  | grep -E "^ *[0-9]+ s:|^ *[0-9]+ i:|Verify return code"
```

If only the leaf certificate shows up (no intermediate), fix the proxy's
certificate bundle (e.g. use `fullchain.pem`, not just `cert.pem`). Also rule
out a stale local CA trust store (`sudo update-ca-certificates` /
`sudo update-ca-trust extract`).

**REST destination: `401 Unauthorized` on init/backup:**

Test the exact same credentials directly, bypassing restic:

```bash
sudo bash -c 'source /root/.restic-rest-<name>-creds && \
  curl -v -u "$RESTIC_REST_USERNAME:$RESTIC_REST_PASSWORD" https://<host>/<repo-path>/config'
```

`404 Not Found` here means auth actually succeeded (the repo just doesn't
exist yet - `restic init` will create it). A real `401` means either the
password is wrong, or - very common with `rest-server --private-repos` - the
repository path's first segment doesn't match the htpasswd username (see
"REST Server Destinations" above).

**REST destination appears to hang with no log output:**

Check `systemctl status restic-backup.service` for the actual child PID
running `restic` (not the wrapping bash script's PID), then:

```bash
sudo cat /proc/<restic-pid>/environ | tr '\0' '\n' | grep RESTIC_REPOSITORY
sudo ss -tnp | grep <restic-pid>
```

This identifies which destination it's stuck on and whether it's still trying
to connect (`SYN_SENT`). As of this role's `timeout` wrapping, this should
self-resolve within `restic_command_timeout_seconds`; a hang beyond that means
an even older/undeployed version of the script is still running - redeploy
the role and restart the service.

## Files Created

- `/opt/scripts/restic-backup.sh` - Backup script
- `/opt/scripts/restic-compare.sh` - Snapshot comparison script (accepts an optional destination name)
- `/etc/systemd/system/restic-backup.service` - Systemd service
- `/etc/systemd/system/restic-backup.timer` - Systemd timer
- `/root/.restic-password` - Primary destination's encryption password
- `/root/.restic-password-<name>` - Each additional destination's own encryption password (as configured)
- `/root/.restic-rest-<name>-creds` - REST server HTTP basic auth credentials, per REST-backed destination
- `/var/log/restic-backup.log` - Backup log
- `/mnt/backup/restic-podman/` - Restic repository (primary; additional destinations live wherever their `repository` points)
