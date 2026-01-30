# Open WebUI Container Role

Deploys Open WebUI in a rootless Podman container managed by **Podman Quadlets** with automatic updates.

## Overview

Open WebUI is a feature-rich, self-hosted web interface for interacting with Large Language Models (LLMs). It provides a ChatGPT-like experience for local LLM deployments, particularly Ollama.

- **Project**: [open-webui/open-webui](https://github.com/open-webui/open-webui)
- **Container Image**: `ghcr.io/open-webui/open-webui:main`
- **Documentation**: [Open WebUI Docs](https://docs.openwebui.com/)

## Features

- Open WebUI in rootless Podman container
- **Quadlet systemd integration** (modern Podman approach)
- **Automatic container updates** via `AutoUpdate=registry`
- Automatic nginx reverse proxy with SSL
- Persistent data storage using named volumes
- Host network access for connecting to Ollama on the host
- Web-based chat interface for LLMs
- Compatible with Ollama, OpenAI API, and other LLM backends

## Deployment Approach

This role uses **Podman Quadlets** - the modern, recommended way to manage containers with systemd:

1. Quadlet `.container` file is deployed to `~/.config/containers/systemd/`
2. On systemd reload, the Quadlet is automatically converted to a service unit
3. Service manages the container lifecycle
4. Podman's auto-update feature checks for new images daily

## Configuration

### Default Settings (defaults/main.yml)

```yaml
# Open WebUI application settings
openwebui_domain: "chat.kerberos.fassbender.contact"
openwebui_host_port: 3001
openwebui_container_port: 8080

# Named volume for persistent data
openwebui_volume_name: "open-webui"

# Enable access to host services (like Ollama running on the host)
openwebui_enable_host_access: true

# Podman user and network
podman_user: "{{ podman_username }}"
podman_network: "podman_bridge"
```

### Key Configuration Options

- **openwebui_host_port**: Port on the host to access Open WebUI (default: 3000 but changed to 3001)
- **openwebui_enable_host_access**: Allows container to reach services on the host via `host.containers.internal` (needed for Ollama)
- **openwebui_volume_name**: Named volume for persistent storage of chats, settings, and models

## Deployment

Add the role to your playbook:

```yaml
- hosts: docker_hosts
  roles:
    - deploy_openwebui_container
```

Deploy:

```bash
ansible-playbook -i inventory/01-lab.yml noble_base.yml -l docker-vm
```

## Service Management

### Quadlet Location

`~/.config/containers/systemd/open-webui.container`

### As Podman User

```bash
# Check service status
systemctl --user status open-webui

# Stop service
systemctl --user stop open-webui

# Start service
systemctl --user start open-webui

# Restart service
systemctl --user restart open-webui

# View logs
journalctl --user -u open-webui -f

# View recent logs
journalctl --user -u open-webui -n 100

# Check container logs directly
podman logs -f open-webui
```

### Check Auto-Updates

```bash
# Check for updates manually
podman auto-update --dry-run

# Run auto-update
podman auto-update
```

## Accessing Open WebUI

### Direct Access

Access via browser:

```
http://<server-ip>:3001
```

### Via Nginx (HTTPS)

If nginx is configured:

```
https://chat.kerberos.fassbender.contact
```

### First Login

On first access, you'll need to create an admin account:

1. Navigate to the Open WebUI URL
2. Click "Sign up"
3. Create your admin account (first user becomes admin)
4. Configure your LLM backend (Ollama, OpenAI API, etc.)

## Connecting to Ollama

### Ollama Running on the Same Host

If Ollama is running on the docker-vm host, Open WebUI can access it via the special hostname:

**In Open WebUI Settings:**

- Go to **Settings → Connections**
- Set Ollama API URL to: `http://host.containers.internal:11434`

This works because `openwebui_enable_host_access: true` adds the `host.containers.internal` hostname mapping.

### Ollama Running on Different Host

If Ollama is on another machine:

- Set Ollama API URL to: `http://<ollama-host-ip>:11434`

## Troubleshooting

### Container Won't Start

Check logs for errors:

```bash
journalctl --user -u open-webui -n 100
# or
podman logs open-webui
```

### Can't Connect to Ollama on Host

1. **Verify Ollama is running**:

   ```bash
   curl http://localhost:11434/api/version
   ```

2. **Check Ollama is listening on all interfaces** (not just localhost):

   ```bash
   # Ollama should be started with OLLAMA_HOST=0.0.0.0
   # Or check systemd service override
   ```

3. **Test from container**:
   ```bash
   podman exec -it open-webui curl http://host.containers.internal:11434/api/version
   ```

### Permission Issues with Volume

Check volume ownership:

```bash
podman volume inspect open-webui
```

### Web UI Not Loading

1. Check service is running: `systemctl --user status open-webui`
2. Verify port is accessible: `curl http://localhost:3001`
3. Check firewall: `sudo ufw status | grep 3001`

## Data Management

### Backup Data

The Open WebUI data is stored in a named Podman volume. To backup:

```bash
# Export volume to tar
podman volume export open-webui > open-webui-backup.tar

# Or copy volume contents
mkdir -p /tmp/backup
podman run --rm -v open-webui:/data -v /tmp/backup:/backup alpine tar czf /backup/open-webui.tar.gz -C /data .
```

### Restore Data

```bash
# Import from tar
cat open-webui-backup.tar | podman volume import open-webui -

# Or extract to new volume
podman run --rm -v open-webui:/data -v /tmp/backup:/backup alpine tar xzf /backup/open-webui.tar.gz -C /data
```

### Reset/Delete Data

```bash
# Stop service
systemctl --user stop open-webui

# Delete volume
podman volume rm open-webui

# Start service (will create new empty volume)
systemctl --user start open-webui
```

## Files Created by This Role

```
/home/{{ podman_user }}/.config/containers/systemd/open-webui.container
/etc/nginx/conf.d/openwebui.conf             # Optional nginx config
Podman Volume: {{ openwebui_volume_name }}   # Named volume for data
```

## Network Access

The service listens on:

- **Port 3001** - HTTP web interface
- **Default**: Binds to `127.0.0.1` (localhost only)
- **For external access**: Change `PublishPort` to `3001:8080/tcp` or use nginx reverse proxy

### Firewall Configuration

If accessing directly (not via nginx):

```bash
# Allow port 3001
sudo ufw allow 3001/tcp
```

## Security Considerations

### Authentication

- Open WebUI has built-in user authentication
- First user becomes administrator
- Additional users can be created by admin

### HTTPS/SSL

- Use nginx reverse proxy for SSL/TLS encryption
- The role automatically configures nginx if it's available
- Recommended for production deployments

### API Keys

- Store OpenAI API keys securely in Open WebUI settings
- Keys are stored in the persistent volume

## Dependencies

- Podman installed and configured
- Podman user with lingering enabled
- (Optional) nginx for reverse proxy with SSL
- (Optional) Ollama for local LLM inference

## Related Roles

- `podman` - Installs and configures Podman
- `podman-user` - Sets up rootless Podman user
- `nginx_reverse_proxy` - Configures nginx with SSL

## References

- [Open WebUI GitHub](https://github.com/open-webui/open-webui)
- [Open WebUI Documentation](https://docs.openwebui.com/)
- [Ollama](https://ollama.ai/)
- [Podman Quadlets Documentation](https://docs.podman.io/en/latest/markdown/podman-systemd.unit.5.html)
- [Podman Volumes](https://docs.podman.io/en/latest/markdown/podman-volume.1.html)

## License

MIT

## Author

Created as part of the Ansible infrastructure automation project.
