# Wyoming-Piper Container Role

Deploys Wyoming-Piper text-to-speech service in a rootless Podman container managed by **Podman Quadlets** with automatic updates.

## Overview

Wyoming-Piper is a Wyoming protocol server for Piper text-to-speech system. It's commonly used with Home Assistant for voice assistant functionality, converting text to natural-sounding speech.

- **Project**: [rhasspy/wyoming-piper](https://github.com/rhasspy/wyoming-piper)
- **Container Image**: `rhasspy/wyoming-piper`
- **Wyoming Protocol**: [Wyoming Protocol Specification](https://github.com/rhasspy/wyoming)
- **Piper TTS**: [rhasspy/piper](https://github.com/rhasspy/piper)

## Features

- Wyoming-Piper in rootless Podman container
- **Quadlet systemd integration** (modern Podman approach)
- **Automatic container updates** via `AutoUpdate=registry`
- Direct TCP access for Wyoming protocol
- Persistent data storage for voice models
- Configurable voices for different languages and speakers
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
# Piper application settings
piper_port: 10200

# Data directory for Piper voices and cache
piper_data_dir: "{{ podman_service_dir }}/piper/data"

# Piper voice configuration
# Format: language_COUNTRY-speaker-quality
piper_voice: "en_US-lessac-medium"

# Podman user and network
podman_user: "{{ podman_username }}"
podman_network: "podman_bridge"
```

### Available Voices

Piper supports numerous voices across many languages. Voice format: `language_COUNTRY-speaker-quality`

#### Quality Levels

- `low` - Fastest, lower quality (good for testing)
- `medium` - Balanced speed and quality (recommended)
- `high` - Best quality, slower

#### Popular English Voices

| Voice                                  | Description                              | Quality |
| -------------------------------------- | ---------------------------------------- | ------- |
| `en_US-lessac-medium`                  | American English, neutral (default)      | Medium  |
| `en_US-lessac-low`                     | American English, neutral, faster        | Low     |
| `en_US-lessac-high`                    | American English, neutral, best quality  | High    |
| `en_US-amy-medium`                     | American English, female                 | Medium  |
| `en_US-ryan-medium`                    | American English, male                   | Medium  |
| `en_GB-northern_english_male-medium`   | British English, male, northern accent   | Medium  |
| `en_GB-southern_english_female-medium` | British English, female, southern accent | Medium  |

#### Other Languages

- **German**: `de_DE-thorsten-medium`, `de_DE-thorsten-low`, `de_DE-thorsten-high`
- **Spanish**: `es_ES-carlfm-medium`, `es_MX-ald-medium`
- **French**: `fr_FR-siwis-medium`, `fr_FR-upmc-medium`
- **Italian**: `it_IT-riccardo-medium`
- **Dutch**: `nl_NL-rdh-medium`
- **Polish**: `pl_PL-darkman-medium`
- **Portuguese**: `pt_BR-faber-medium`
- **Russian**: `ru_RU-dmitri-medium`
- **Chinese**: `zh_CN-huayan-medium`

For a complete list of available voices, see the [Piper Samples](https://rhasspy.github.io/piper-samples/) page where you can listen to all voices.

**Note**: Voices are automatically downloaded on first use and cached in the data directory. The first TTS request for a new voice will take longer while it downloads.

## Deployment

Add the role to your playbook:

```yaml
- hosts: docker_hosts
  roles:
    - deploy_piper_container
```

Deploy:

```bash
ansible-playbook -i inventory/01-lab.yml noble_base.yml -l docker-vm
```

## Service Management

### Quadlet Location

`~/.config/containers/systemd/piper.container`

### As Podman User

```bash
# Check service status
systemctl --user status piper

# Stop service
systemctl --user stop piper

# Start service
systemctl --user start piper

# Restart service
systemctl --user restart piper

# View logs
journalctl --user -u piper -f

# View recent logs
journalctl --user -u piper -n 100

# Check container logs directly
podman logs -f piper
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
journalctl --user -u piper -n 100
# or
podman logs piper
```

### Permission Issues

Ensure data directory has correct ownership:

```bash
ls -la {{ piper_data_dir }}
```

Should be owned by the podman user.

### Voice Download Issues

First use of a voice will download it. Check logs:

```bash
journalctl --user -u piper -f
```

Voice downloads can take a few minutes depending on the voice size and connection speed.

### Test Piper Service

Test TCP connection:

```bash
# From another machine
nc -zv <server-ip> 10200

# From docker-vm locally
nc -zv 127.0.0.1 10200
```

The connection should remain open (Wyoming protocol waits for commands).

## Integration with Home Assistant

1. In Home Assistant, go to **Settings → Devices & Services**
2. Click **Add Integration**
3. Search for **Wyoming Protocol**
4. Configure with:
   - **Host**: Use IP address (e.g., `192.168.1.118`) - DNS hostnames may not resolve from HA container
   - **Port**: `10200`
   - **Protocol**: Wyoming

**Note**: If Home Assistant is running in a container and can't resolve your domain name, use the server's IP address directly.

### Using with Wyoming Whisper

For a complete voice assistant setup in Home Assistant:

- **Piper** (this role) - Text-to-Speech (TTS)
- **Whisper** (`deploy_whisper_container` role) - Speech-to-Text (STT)
- **Wyoming Satellite** or **Wyoming openWakeWord** - Wake word detection

## Files Created by This Role

```
/home/{{ podman_user }}/.config/containers/systemd/piper.container
{{ piper_data_dir }}/                             # Voice models cache
```

## Network Access

The service listens on:

- **Port 10200** - Wyoming protocol (TCP)
- **Default**: Binds to all interfaces for network access
- **For localhost only**: Change `PublishPort` to `127.0.0.1:10200:10200/tcp`

### Testing the Connection

From any machine on your network:

```bash
# Test TCP connection
telnet <docker-vm-ip> 10200
# or
nc -zv <docker-vm-ip> 10200

# Should see: Connected to <docker-vm-ip>
```

From docker-vm locally:

```bash
telnet 127.0.0.1 10200
```

### Firewall Configuration

If the connection is refused from external machines, check the firewall:

```bash
# Check if port is open
sudo ufw status | grep 10200

# Allow port 10200 if needed
sudo ufw allow 10200/tcp
```

**Note**: Wyoming protocol uses raw TCP, not HTTP. Direct TCP access on port 10200 is required - nginx HTTP reverse proxy is not applicable for this service.

## Dependencies

- Podman installed and configured
- Podman user with lingering enabled

## Related Roles

- `podman` - Installs and configures Podman
- `podman-user` - Sets up rootless Podman user
- `deploy_whisper_container` - Wyoming Whisper STT service (speech-to-text)

## References

- [Wyoming Piper GitHub](https://github.com/rhasspy/wyoming-piper)
- [Piper TTS](https://github.com/rhasspy/piper)
- [Piper Voice Samples](https://rhasspy.github.io/piper-samples/)
- [Wyoming Protocol](https://github.com/rhasspy/wyoming)
- [Podman Quadlets Documentation](https://docs.podman.io/en/latest/markdown/podman-systemd.unit.5.html)
- [Home Assistant Wyoming Integration](https://www.home-assistant.io/integrations/wyoming/)

## License

MIT

## Author

Created as part of the Ansible infrastructure automation project.
