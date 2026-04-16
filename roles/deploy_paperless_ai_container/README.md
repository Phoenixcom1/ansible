# Paperless-AI Container Role

Deploys Paperless-AI document intelligence assistant using **Podman Quadlets** for AI-powered document analysis and chat interface.

## Features

- AI-powered document intelligence and chat
- RAG (Retrieval Augmented Generation) service integration
- Automatic registry updates via Podman
- **Podman Quadlet** for modern systemd integration
- Isolated network for security
- Full security hardening (capability dropping, no-new-privileges)
- Nginx reverse proxy with SSL
- Persistent data storage

## Architecture

**Container:**

- `paperless-ai`: Main AI assistant application

**Data Structure:**

```
/opt/podman/paperless-ai/
└── data/            # Application data and configuration
```

## Quadlet Configuration

### Service Files

Quadlet file deployed to `~/.config/containers/systemd/`:

- `paperless-ai.container`

Systemd automatically generates service unit:

- `paperless-ai.service`

### Auto-Update Policy

**Auto-update is ENABLED** via Podman's registry auto-update feature. The container checks for new images and updates automatically.

## Configuration

### Default Settings (defaults/main.yml)

```yaml
paperless_ai_domain: "paperless-ai.kerberos.fassbender.contact"
paperless_ai_port: 5555
paperless_ai_internal_port: 3000
paperless_ai_data_dir: "/opt/podman/paperless-ai/data"
paperless_ai_network: paperless_ai_net
paperless_ai_image: "docker.io/clusterzx/paperless-ai"
paperless_ai_version: "latest"
```

### Environment Variables

The following environment variables are configured:

- `PUID`: Podman user UID (auto-detected)
- `PGID`: Podman user GID (auto-detected)
- `PAPERLESS_AI_PORT`: Internal application port (3000)
- `RAG_SERVICE_URL`: RAG service endpoint (http://localhost:8000)
- `RAG_SERVICE_ENABLED`: Enable RAG features (true)

### Security Settings

```yaml
paperless_ai_drop_capabilities: true # Drop all Linux capabilities
paperless_ai_no_new_privileges: true # Prevent privilege escalation
```

## Network Configuration

The service runs in an isolated network (`paperless_ai_net`) and only exposes port 5555 on localhost. External access is provided via nginx reverse proxy.

**Port Mapping:**

- External (nginx): 443 → 5555 (localhost)
- Internal: 5555 → 3000 (container)

## Usage

### Service Management

```bash
# Check service status
systemctl --user status paperless-ai.service

# View logs
journalctl --user -u paperless-ai.service -f

# Restart service
systemctl --user restart paperless-ai.service

# Stop service
systemctl --user stop paperless-ai.service

# Start service
systemctl --user start paperless-ai.service
```

### Manual Updates

While auto-update is enabled, you can manually update the container:

```bash
# Pull latest image
podman pull docker.io/clusterzx/paperless-ai:latest

# Restart service to use new image
systemctl --user restart paperless-ai.service
```

## Integration with Paperless-ngx

Paperless-AI is designed to work with Paperless-ngx. Ensure you have:

1. Paperless-ngx deployed and accessible
2. API token configured in Paperless-ngx
3. Network connectivity between services (if needed)

## Backup

### What to Back Up

✅ **Included:**

- `/opt/podman/paperless-ai/data/` - Application data and configuration

### Backup Method

```bash
# Simple tar backup
tar -czf paperless-ai-backup-$(date +%Y%m%d).tar.gz \
  -C /opt/podman/paperless-ai data/

# Or use the restic-backup role (recommended)
```

## Troubleshooting

### Container Won't Start

Check logs:

```bash
journalctl --user -u paperless-ai.service -n 100
```

Check container status:

```bash
podman ps -a | grep paperless-ai
```

### Network Issues

Verify network exists:

```bash
podman network ls | grep paperless_ai_net
```

Test port binding:

```bash
curl http://localhost:5555
```

### Permission Issues

Verify data directory ownership:

```bash
ls -ld /opt/podman/paperless-ai/data/
```

Should be owned by podman user.

## Advanced Configuration

### Custom RAG Service

To use a different RAG service endpoint:

```yaml
paperless_ai_rag_service_url: "http://your-rag-service:8000"
paperless_ai_rag_service_enabled: true
```

### Disable Auto-Update

Edit the Quadlet template to remove or comment out:

```ini
AutoUpdate=registry
```

## Requirements

- Podman 4.4+
- Systemd 250+
- Nginx with SSL certificates
- Podman user with lingering enabled

## Dependencies

This role depends on:

- `podman-user` - Sets up podman user
- `nginx_reverse_proxy` - Configures reverse proxy

## References

- [Paperless-AI GitHub](https://github.com/clusterzx/paperless-ai)
- [Podman Quadlet Documentation](https://docs.podman.io/en/latest/markdown/podman-systemd.unit.5.html)
- [Paperless-ngx Documentation](https://docs.paperless-ngx.com/)
