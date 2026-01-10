# Immich Container Role

Deploys Immich photo and video management platform using **Podman Quadlets** with PostgreSQL (with vector extensions), Valkey/Redis, and machine learning capabilities.

## Features

- Immich photo and video management server
- PostgreSQL database with optimized settings
- Redis cache for performance
- Machine learning for face recognition and object detection
- **Hardware acceleration** for video transcoding (Intel Quick Sync/VAAPI)
- **Hardware-accelerated ML** with OpenVINO (Intel GPU)
- Background microservices for processing
- **Podman Quadlet** for modern systemd integration
- **Automatic container updates** via `AutoUpdate=registry`
- Network mount support for external photo libraries (CIFS/SMB or NFS)
- Nginx reverse proxy with SSL
- Coordinated service startup via systemd target

## Architecture

**Containers (Quadlets):**

- `immich-server`: Main web application and API
- `immich-microservices`: Background job processing (thumbnail generation, metadata extraction)
- `immich-machine-learning`: ML services for face recognition and object detection
- `immich-postgres`: PostgreSQL 14 with vectorchord and pgvectors extensions
- `immich-redis`: Valkey 9 cache (Redis fork)

All containers run in an isolated `immich_net` Quadlet-managed bridge network for security.

**Service Dependencies:**

```
immich-server        → immich-postgres (required)
                     → immich-redis (required)

immich-microservices → immich-postgres (required)
                     → immich-redis (required)

immich-machine-learning (optional, can be disabled)
```

**Data Structure:**

```
/opt/podman/immich/
├── upload/          # Uploaded photos and videos
├── postgres/        # PostgreSQL database
├── model-cache/     # ML models cache
├── redis/           # Redis data (ephemeral)
├── library/         # Network mount for external library (optional)
└── immich.env       # Environment file with secrets
```

## Quadlet Configuration

### Service Files

Quadlet files are deployed to `~/.config/containers/systemd/`:

- `immich-postgres.container`
- `immich-redis.container`
- `immich-server.container`
- `immich-microservices.container`
- `immich-machine-learning.container`
- `immich_net.network` (bridge network for container communication)
- `immich-stack.target` (deployed to `~/.config/systemd/user/`)

Systemd automatically generates service units:

- `immich-postgres.service`
- `immich-redis.service`
- `immich-server.service`
- `immich-microservices.service`
- `immich-machine-learning.service`
- `immich-stack.target` (coordinates all services)

### Auto-Update Policy

**Auto-update is ENABLED** for all Immich containers via `AutoUpdate=registry`. Podman checks for new images daily and updates automatically. The `immich-stack.target` ensures services start in the correct order after updates.

## Configuration

### Default Settings (defaults/main.yml)

```yaml
# Container settings
immich_repo_path: "/opt/podman/immich"
immich_upload_dir: "/opt/podman/immich/upload"
immich_db_dir: "/opt/podman/immich/postgres"
immich_model_cache_dir: "/opt/podman/immich/model-cache"

# Network mount (optional)
immich_enable_network_mount: false
immich_network_mount_source: "//datenbunker.local/Photos"
immich_network_mount_type: "cifs"
immich_network_mount_target: "/opt/podman/immich/library"

# Application
immich_domain: "immich.kerberos.fassbender.contact"
immich_port: 2283
immich_internal_port: 2283

# Container versions
immich_version: "release" # Use "release" for latest stable
postgres_version: "14-vectorchord0.4.3-pgvector0.8.1-pgvectors0.2.0" # Official Immich postgres with extensions
redis_version: "9" # Valkey 9 (Redis fork)

# Database
immich_db_name: "immich"
immich_db_user: "postgres"

# Machine Learning
immich_ml_workers: 1
immich_ml_model_ttl: 300

# Upload limits
immich_max_upload_size: "10000" # MB

# Feature flags
immich_disable_machine_learning: false
immich_disable_reverse_geocoding: false

# Podman
podman_user: "podman"
immich_network: immich_net
```

## Environment File Setup

Create `/opt/podman/immich/immich.env` with required secrets:

```bash
# Database (required)
DB_DATABASE_NAME=immich
DB_USERNAME=postgres
DB_PASSWORD=your_secure_database_password

# Optional: Timezone
TZ=Europe/Berlin

# Optional: Logging
LOG_LEVEL=log
```

**Note:** The database configuration uses `DB_USERNAME=postgres` (not `immich`) to match the official Immich postgres image defaults. All three database environment variables are required.

**Security:**

```bash
sudo chown podman:podman /opt/podman/immich/immich.env
sudo chmod 600 /opt/podman/immich/immich.env
```

## Network Mount Setup

### SMB/CIFS Mount for External Library

1. **Create credentials file** on the host:

   ```bash
   sudo nano /root/.immich_smbcreds
   ```

   Content:

   ```
   username=your_smb_user
   password=your_smb_password
   ```

   Secure it:

   ```bash
   sudo chmod 600 /root/.immich_smbcreds
   ```

2. **Configure in inventory/defaults**:

   ```yaml
   immich_enable_network_mount: true
   immich_network_mount_source: "//nas-server.local/Photos"
   immich_network_mount_type: "cifs"
   immich_smbcredentials_file: "/root/.immich_smbcreds"
   ```

**UID/GID Mapping:**
The role automatically calculates the correct host UID/GID for the SMB mount based on the podman user's subordinate UID range (`/etc/subuid`). This ensures that container UID 1000 (immich user) can access the mounted files.

### NFS Mount

```yaml
immich_enable_network_mount: true
immich_network_mount_source: "192.168.1.100:/export/Photos"
immich_network_mount_type: "nfs"
immich_network_mount_options: "defaults,_netdev"
```

### External Library Usage

After mounting, import the external library in Immich:

1. Navigate to **Administration** → **External Libraries**
2. Create a new library pointing to `/usr/src/app/external` (container path)
3. Immich will scan and import photos without moving/copying files

## PostgreSQL Configuration

### Vector Extensions

The role uses the official Immich PostgreSQL image which includes:

- **vectorchord 0.4.3**: High-performance vector search
- **pgvector 0.8.1**: Vector similarity search
- **pgvectors 0.2.0**: Additional vector operations

These extensions enable Immich's smart search, facial recognition, and similarity detection features.

### Performance Optimization

The role configures PostgreSQL with optimized settings for Immich:

```yaml
postgres_shared_buffers: "256MB"
postgres_effective_cache_size: "1GB"
postgres_maintenance_work_mem: "256MB"
postgres_work_mem: "8MB"
postgres_max_wal_size: "4GB"
```

Adjust these based on your server's RAM. General guidelines:

- **shared_buffers**: 25% of RAM (up to 8GB)
- **effective_cache_size**: 50-75% of RAM
- **maintenance_work_mem**: 5-10% of RAM (up to 1GB)

## Machine Learning Configuration

### Disable ML (for low-resource systems)

```yaml
immich_disable_machine_learning: true
```

When disabled, face recognition and object detection features won't be available, but Immich will use significantly less CPU and memory.

### Tune ML Performance

```yaml
immich_ml_workers: 2 # Increase for faster processing
immich_ml_model_ttl: 600 # Keep models loaded longer (seconds)
```

**Note:** Each ML worker uses ~2GB RAM. Monitor memory usage when increasing workers.

## Hardware Acceleration

### Overview

The role automatically configures hardware acceleration for:

- **Video transcoding**: Uses Intel Quick Sync (QSV) or VAAPI for encoding/decoding
- **Machine learning**: Uses OpenVINO for GPU-accelerated face detection, object recognition, and smart search

### Prerequisites

- Intel CPU with integrated GPU (6th gen or newer recommended)
- Host drivers installed: `intel-media-va-driver`, `libva`, `intel-gpu-tools`
- Podman user added to `video` and `render` groups (handled automatically by role)

### How It Works

**Video Transcoding (immich-server, immich-microservices):**

- Containers access `/dev/dri` for GPU hardware
- GID mapping ensures proper permissions in rootless Podman
- Must be **enabled in Immich web UI**: Administration → Video Transcoding Settings → Hardware Acceleration → Select "Quick Sync (QSV)" or "VAAPI"

**Machine Learning (immich-machine-learning):**

- Uses `-openvino` tagged image with Intel GPU support
- Automatically enabled when role deploys containers
- Significantly faster face detection and smart search

### Configuration

Hardware acceleration is **enabled by default** in the Quadlet templates. The role automatically:

1. Adds the podman user to `video` and `render` groups
2. Passes `/dev/dri` device to containers
3. Configures GID mapping for proper GPU access in rootless Podman
4. Uses OpenVINO-tagged ML image for GPU acceleration

**No manual configuration needed** - just deploy and enable in the web UI for transcoding.

### Verification

**Check device access:**

```bash
podman exec -it immich-server ls -l /dev/dri
podman exec -it immich-machine-learning ls -l /dev/dri
```

**Monitor GPU usage:**

```bash
intel_gpu_top
```

**Check logs for hardware acceleration:**

```bash
# Video transcoding
journalctl --user -u immich-microservices | grep -i vaapi

# Machine learning
journalctl --user -u immich-machine-learning | grep -i openvino
```

You should see messages like:

- `Transcoding video ... with VAAPI-accelerated encoding`
- `Available ORT providers` containing `OpenVINOExecutionProvider`

### Troubleshooting Hardware Acceleration

**Video transcoding says "without hardware acceleration":**

- Check that you've enabled it in the Immich web UI (Administration → Video Transcoding Settings)
- Verify `/dev/dri` is accessible in the container
- Check that podman user is in video and render groups: `groups podman`

**GPU not being used:**

```bash
# Check group membership
getent group video
getent group render

# Check device permissions in container
podman exec -it immich-server ls -l /dev/dri

# Monitor GPU usage during transcoding/ML job
intel_gpu_top
```

**For older CPUs or different hardware:**

- Modify the Quadlet templates to use different acceleration (e.g., NVIDIA)
- See [Immich Hardware Transcoding Docs](https://docs.immich.app/features/hardware-transcoding)
- See [Immich ML Hardware Acceleration Docs](https://docs.immich.app/features/ml-hardware-acceleration)

### Disabling Hardware Acceleration

If you need to disable hardware acceleration:

1. **For transcoding**: Set to "Disabled" in Immich web UI
2. **For ML**: Change the machine learning image from `-openvino` to standard (remove `-openvino` suffix from template)
3. **Remove device access**: Comment out `AddDevice=/dev/dri` lines in Quadlet templates

## Service Management

### Check Status

```bash
# Overall stack status
systemctl --user status immich-stack.target

# Individual services
systemctl --user status immich-server
systemctl --user status immich-microservices
systemctl --user status immich-postgres
systemctl --user status immich-redis
systemctl --user status immich-machine-learning
```

### Restart Services

```bash
# Restart entire stack
systemctl --user restart immich-stack.target

# Restart specific service
systemctl --user restart immich-server
```

### View Logs

```bash
# Server logs
journalctl --user -u immich-server -f

# Microservices logs
journalctl --user -u immich-microservices -f

# ML logs
journalctl --user -u immich-machine-learning -f

# Database logs
journalctl --user -u immich-postgres -f
```

## Updates

Auto-updates are enabled via Podman's auto-update feature:

```bash
# Check for updates (runs daily automatically)
systemctl --user start podman-auto-update.service

# View auto-update logs
journalctl --user -u podman-auto-update.service
```

**Manual update:**

```bash
# Update images and restart services
podman auto-update
systemctl --user restart immich-stack.target
```

## Backup Strategy

### What to Back Up

**Critical:**

- `/opt/podman/immich/upload/` - All photos and videos
- `/opt/podman/immich/postgres/` - Database with metadata, albums, users
- `/opt/podman/immich/immich.env` - Secrets and configuration

**Optional:**

- `/opt/podman/immich/model-cache/` - ML models (can be re-downloaded)

**Not needed:**

- `/opt/podman/immich/redis/` - Ephemeral cache

### Backup Command

```bash
# Stop services for consistent backup
systemctl --user stop immich-stack.target

# Backup data
sudo tar -czf immich-backup-$(date +%Y%m%d).tar.gz \
  /opt/podman/immich/upload \
  /opt/podman/immich/postgres \
  /opt/podman/immich/immich.env

# Start services
systemctl --user start immich-stack.target
```

### Restore

```bash
# Stop services
systemctl --user stop immich-stack.target

# Restore data
sudo tar -xzf immich-backup-YYYYMMDD.tar.gz -C /

# Fix permissions
sudo chown -R podman:podman /opt/podman/immich

# Start services
systemctl --user start immich-stack.target
```

## Troubleshooting

### Services Won't Start

Check systemd status and logs:

```bash
systemctl --user status immich-stack.target
journalctl --user -u immich-server -n 50
```

### Database Connection Errors

Verify PostgreSQL is running and credentials are correct:

```bash
systemctl --user status immich-postgres
cat /opt/podman/immich/immich.env | grep DB_
```

Ensure all three database variables are set in the environment file:

- `DB_DATABASE_NAME=immich`
- `DB_USERNAME=postgres`
- `DB_PASSWORD=your_password`

### Upload Failures

Check upload directory permissions and disk space:

```bash
ls -la /opt/podman/immich/upload
df -h /opt/podman
```

### ML Service High CPU/Memory

Reduce ML workers or disable ML:

```yaml
immich_ml_workers: 1
# or
immich_disable_machine_learning: true
```

### Network Mount Not Accessible

Verify mount and permissions:

```bash
mount | grep immich
ls -la /opt/podman/immich/library
```

Check subordinate UID/GID mapping and data directory permissions:

```bash
grep podman /etc/subuid
grep podman /etc/subgid
ls -aln /opt/podman/immich/
```

Data directories should be owned by the mapped host UID (e.g., 297607) corresponding to container UID 999.

## Security Considerations

- **Environment file**: Contains database password - ensure proper permissions (600)
- **Network isolation**: All services run in isolated `immich_net` network
- **Reverse proxy**: Nginx handles SSL termination and rate limiting
- **Rootless Podman**: Containers run without root privileges
- **Read-only mounts**: External library mounted read-only when possible

## Prerequisites

- Ubuntu 24.04
- Podman user configured (via `podman-user` role)
- Nginx installed
- At least 4GB RAM (8GB+ recommended with ML enabled)
- 20GB+ storage for photos/videos
- **Optional for hardware acceleration**: Intel CPU with integrated GPU (6th gen+), host drivers installed

## Example Playbook

```yaml
- hosts: media_servers
  roles:
    - role: deploy_immich_container
      vars:
        immich_domain: "photos.example.com"
        immich_enable_network_mount: true
        immich_network_mount_source: "//nas.local/Photos"
        immich_ml_workers: 2
```

## Related Roles

- `podman-user`: Creates rootless Podman user
- `nginx_reverse_proxy`: Configures SSL reverse proxy
- `restic-backup`: Backup solution for Immich data

## References

- [Immich Documentation](https://immich.app/docs)
- [Immich Hardware Transcoding](https://docs.immich.app/features/hardware-transcoding)
- [Immich ML Hardware Acceleration](https://docs.immich.app/features/ml-hardware-acceleration)
- [Podman Quadlets](https://docs.podman.io/en/latest/markdown/podman-systemd.unit.5.html)
- [PostgreSQL Performance Tuning](https://pgtune.leopard.in.ua/)
