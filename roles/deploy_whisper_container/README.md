# Wyoming-Whisper Container Role

Deploys Wyoming-Whisper speech-to-text service in a rootless Podman container managed by **Podman Quadlets** with automatic updates.

## Overview

Wyoming-Whisper is a Wyoming protocol server for OpenAI's Whisper speech-to-text system using faster-whisper. It's commonly used with Home Assistant for voice assistant functionality.

- **Project**: [rhasspy/wyoming-faster-whisper](https://github.com/rhasspy/wyoming-faster-whisper)
- **Container Image**: `rhasspy/wyoming-whisper`
- **Wyoming Protocol**: [Wyoming Protocol Specification](https://github.com/rhasspy/wyoming)

## Features

- Wyoming-Whisper in rootless Podman container
- **Quadlet systemd integration** (modern Podman approach)
- **Automatic container updates** via `AutoUpdate=registry`
- Direct TCP access for Wyoming protocol
- Persistent data storage for models
- Configurable Whisper models and languages
- Compatible with Home Assistant and other Wyoming clients

## Deployment Approach

This role uses **Podman Quadlets** - the modern, recommended way to manage containers with systemd:

1. Quadlet `.container` file is deployed to `~/.config/containers/systemd/`
2. On systemd reload, the Quadlet is automatically converted to a service unit
3. Service manages the container lifecycle
4. Podman's auto-update feature checks for new images daily

## Configuration

### Default Settings (defaults/main.yml)

```yaml
# Whisper application settings
whisper_domain: "whisper.kerberos.fassbender.contact"
whisper_port: 10300

# Data directory for Whisper models and cache
whisper_data_dir: "{{ podman_service_dir }}/whisper/data"

# Whisper model configuration
# Available models: tiny, tiny-int8, base, base-int8, small, small-int8,
#                   medium, medium-int8, large, large-v3
whisper_model: "tiny-int8"

# Language code (e.g., en, de, fr, es, etc.)
whisper_language: "en"

# Podman user and network
podman_user: "{{ podman_username }}"
podman_network: "podman_bridge"
```

### Available Whisper Models

Models are listed from fastest/least accurate to slowest/most accurate:

| Model         | Size     | Notes                                           |
| ------------- | -------- | ----------------------------------------------- |
| `tiny`        | ~39 MB   | Fastest, least accurate                         |
| `tiny-int8`   | ~39 MB   | Quantized version of tiny (recommended default) |
| `base`        | ~74 MB   | Good balance of speed and accuracy              |
| `base-int8`   | ~74 MB   | Quantized version of base                       |
| `small`       | ~244 MB  | Better accuracy                                 |
| `small-int8`  | ~244 MB  | Quantized version of small                      |
| `medium`      | ~769 MB  | High accuracy                                   |
| `medium-int8` | ~769 MB  | Quantized version of medium                     |
| `large`       | ~1550 MB | Best accuracy, slower                           |
| `large-v3`    | ~1550 MB | Latest large model                              |

**Note**: Models are automatically downloaded on first run and cached in the data directory.

### Language Codes

Common language codes (ISO 639-1):

- `en` - English
- `de` - German
- `fr` - French
- `es` - Spanish
- `it` - Italian
- `nl` - Dutch
- `pl` - Polish
- `pt` - Portuguese
- `ru` - Russian
- `zh` - Chinese

For a full list, see [Whisper language support](https://github.com/openai/whisper#available-models-and-languages).

## Deployment

Add the role to your playbook:

```yaml
- hosts: docker_hosts
  roles:
    - deploy_whisper_container
```

Deploy:

```bash
ansible-playbook -i inventory/01-lab.yml noble_base.yml -l docker-vm
```

## Service Management

### Quadlet Location

`~/.config/containers/systemd/whisper.container`

### As Podman User

```bash
# Check service status
systemctl --user status whisper

# Stop service
systemctl --user stop whisper

# Start service
systemctl --user start whisper

# Restart service
systemctl --user restart whisper

# View logs
journalctl --user -u whisper -f

# View recent logs
journalctl --user -u whisper -n 100
```

### Check Auto-Updates

```bash
# Check for updates manually
podman auto-update --dry-run

# Run auto-update
podman auto-update
```

## Troubleshooting

### Container Won't Start

Check logs for errors:

```bash
journalctl --user -u whisper -n 100
```

### Permission Issues

Ensure data directory has correct ownership:

```bash
ls -la {{ whisper_data_dir }}
```

Should be owned by the podman user.

### Model Download Issues

First run will download the model. Check logs:

```bash
journalctl --user -u whisper -f
```

Model downloads can take several minutes depending on model size and connection speed.

### Test Wyoming Service

Test the Wyoming protocol server:

```bash
# From another machine or container
telnet <server-ip> 10300
```

Or test with a Wyoming client like Home Assistant.

## Integration with Home Assistant

1. In Home Assistant, go to Settings → Devices & Services
2. Add Wyoming Protocol integration
3. Configure with:
   - **Host**: Use IP address (e.g., `192.168.1.118`) - DNS hostnames may not resolve from HA container
   - **Port**: `10300`
   - **Protocol**: Wyoming

**Note**: If Home Assistant is running in a container and can't resolve your domain name, use the server's IP address directly.

## Files Created by This Role

```
/home/{{ podman_user }}/.config/containers/systemd/whisper.container
{{ whisper_data_dir }}/                           # Model cache and downloaded models
```

## Network Access

The service listens on:

- **Port 10300** - Wyoming protocol (TCP)
- **Default**: Binds to all interfaces for network access
- **For localhost only**: Change `PublishPort` to `127.0.0.1:10300:10300/tcp`

### Testing the Connection

From any machine on your network:

```bash
# Test TCP connection
telnet <docker-vm-ip> 10300
# or
nc -zv <docker-vm-ip> 10300

# Should see: Connected to <docker-vm-ip>
```

From docker-vm locally:

```bash
telnet 127.0.0.1 10300
```

### Firewall Configuration

If the connection is refused from external machines, check the firewall:

```bash
# Check if port is open
sudo ufw status | grep 10300

# Allow port 10300 if needed
sudo ufw allow 10300/tcp
```

**Note**: Wyoming protocol uses raw TCP, not HTTP. Direct TCP access on port 10300 is required - nginx HTTP reverse proxy is not applicable for this service.

## Dependencies

- Podman installed and configured
- Podman user with lingering enabled

## Related Roles

- `podman` - Installs and configures Podman
- `podman-user` - Sets up rootless Podman user

## References

- [Wyoming Faster-Whisper GitHub](https://github.com/rhasspy/wyoming-faster-whisper)
- [Wyoming Protocol](https://github.com/rhasspy/wyoming)
- [Podman Quadlets Documentation](https://docs.podman.io/en/latest/markdown/podman-systemd.unit.5.html)
- [OpenAI Whisper](https://github.com/openai/whisper)
- [Faster Whisper](https://github.com/guillaumekln/faster-whisper)

## License

MIT

## Author

Created as part of the Ansible infrastructure automation project.
