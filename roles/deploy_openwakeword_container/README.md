# Wyoming-openWakeWord Container Role

Deploys Wyoming-openWakeWord wake word detection service in a rootless Podman container managed by **Podman Quadlets** with automatic updates.

## Overview

Wyoming-openWakeWord is a Wyoming protocol server for openWakeWord wake word detection system. It listens for wake words in audio streams and is commonly used with Home Assistant for voice assistant functionality, triggering the voice pipeline when a wake word is detected.

- **Project**: [rhasspy/wyoming-openwakeword](https://github.com/rhasspy/wyoming-openwakeword)
- **Container Image**: `rhasspy/wyoming-openwakeword`
- **Wyoming Protocol**: [Wyoming Protocol Specification](https://github.com/rhasspy/wyoming)
- **openWakeWord**: [dscripka/openWakeWord](https://github.com/dscripka/openWakeWord)

## Features

- Wyoming-openWakeWord in rootless Podman container
- **Quadlet systemd integration** (modern Podman approach)
- **Automatic container updates** via `AutoUpdate=registry`
- Direct TCP access for Wyoming protocol
- Pre-loaded wake word models included
- Support for custom wake word models
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
# openWakeWord application settings
openwakeword_port: 10400

# Data directory for custom wake word models
openwakeword_custom_models_dir: "{{ podman_service_dir }}/openwakeword/custom"

# Pre-loaded wake words (no configuration needed, models are built into the container)
# Available: "alexa", "hey_jarvis", "hey_mycroft", "hey_rhasspy", "ok_nabu"

# Podman user and network
podman_user: "{{ podman_username }}"
podman_network: "podman_bridge"
```

### Pre-loaded Wake Word Models

The container includes these wake word models by default (no additional configuration needed):

| Wake Word     | Description                             |
| ------------- | --------------------------------------- |
| `alexa`       | Amazon's wake word                      |
| `hey_jarvis`  | "Hey Jarvis"                            |
| `hey_mycroft` | "Hey Mycroft" (Mycroft AI)              |
| `hey_rhasspy` | "Hey Rhasspy" (Rhasspy voice assistant) |
| `ok_nabu`     | "OK Nabu" (Home Assistant's Nabu Casa)  |

All models are loaded automatically when the service starts. Home Assistant will allow you to choose which wake word to use.

### Custom Wake Word Models

To add custom wake word models:

1. Place your `.tflite` or `.onnx` model files in the custom models directory:

   ```bash
   # Copy model to server
   scp my_custom_wakeword.tflite docker-vm:{{ openwakeword_custom_models_dir }}/
   ```

2. Restart the service:

   ```bash
   systemctl --user restart openwakeword
   ```

3. The custom models will be available alongside the pre-loaded ones

**Creating Custom Models**: See the [openWakeWord documentation](https://github.com/dscripka/openWakeWord#creating-custom-models) for training custom wake words.

## Deployment

Add the role to your playbook:

```yaml
- hosts: docker_hosts
  roles:
    - deploy_openwakeword_container
```

Deploy:

```bash
ansible-playbook -i inventory/01-lab.yml noble_base.yml -l docker-vm
```

### Complete Voice Assistant Setup

Deploy all three Wyoming services together:

```yaml
- hosts: docker_hosts
  roles:
    - deploy_whisper_container # STT on port 10300
    - deploy_piper_container # TTS on port 10200
    - deploy_openwakeword_container # Wake word on port 10400
```

## Service Management

### Quadlet Location

`~/.config/containers/systemd/openwakeword.container`

### As Podman User

```bash
# Check service status
systemctl --user status openwakeword

# Stop service
systemctl --user stop openwakeword

# Start service
systemctl --user start openwakeword

# Restart service
systemctl --user restart openwakeword

# View logs
journalctl --user -u openwakeword -f

# View recent logs
journalctl --user -u openwakeword -n 100

# Check container logs directly
podman logs -f openwakeword
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
journalctl --user -u openwakeword -n 100
# or
podman logs openwakeword
```

### Permission Issues

Ensure custom models directory has correct ownership:

```bash
ls -la {{ openwakeword_custom_models_dir }}
```

Should be owned by the podman user.

### Wake Word Not Detected

1. **Check logs** for detection events:

   ```bash
   journalctl --user -u openwakeword -f
   ```

2. **Verify models loaded**: Check container logs at startup to see which models were loaded

3. **Audio quality**: Ensure clean audio input (low background noise, clear speech)

4. **Threshold adjustment**: In Home Assistant, you can adjust sensitivity in the wake word settings

### Test openWakeWord Service

Test TCP connection:

```bash
# From another machine
nc -zv <server-ip> 10400

# From docker-vm locally
nc -zv 127.0.0.1 10400
```

The connection should remain open (Wyoming protocol waits for audio streams).

## Integration with Home Assistant

### Add Wyoming Wake Word Detection

1. In Home Assistant, go to **Settings → Devices & Services**
2. Click **Add Integration**
3. Search for **Wyoming Protocol**
4. Configure with:
   - **Host**: Use IP address (e.g., `192.168.1.118`) - DNS hostnames may not resolve from HA container
   - **Port**: `10400`
   - **Protocol**: Wyoming

**Note**: If Home Assistant is running in a container and can't resolve your domain name, use the server's IP address directly.

### Complete Voice Pipeline Setup

For a full voice assistant in Home Assistant, you need:

1. **Wake Word Detection** (this role - openWakeWord) - Port 10400
2. **Speech-to-Text** (`deploy_whisper_container`) - Port 10300
3. **Text-to-Speech** (`deploy_piper_container`) - Port 10200

Configure all three in Home Assistant's Wyoming integration, then create a voice assistant pipeline:

1. Go to **Settings → Voice Assistants**
2. Click **Add Assistant**
3. Configure:
   - **Wake word**: Select your Wyoming wake word service (openWakeWord)
   - **Speech-to-text**: Select Whisper
   - **Text-to-speech**: Select Piper
   - **Conversation agent**: Choose your preferred assistant (Home Assistant, etc.)

## Files Created by This Role

```
/home/{{ podman_user }}/.config/containers/systemd/openwakeword.container
{{ openwakeword_custom_models_dir }}/        # Custom wake word models
```

## Network Access

The service listens on:

- **Port 10400** - Wyoming protocol (TCP)
- **Default**: Binds to all interfaces for network access
- **For localhost only**: Change `PublishPort` to `127.0.0.1:10400:10400/tcp`

### Testing the Connection

From any machine on your network:

```bash
# Test TCP connection
telnet <docker-vm-ip> 10400
# or
nc -zv <docker-vm-ip> 10400

# Should see: Connected to <docker-vm-ip>
```

From docker-vm locally:

```bash
telnet 127.0.0.1 10400
```

### Firewall Configuration

If the connection is refused from external machines, check the firewall:

```bash
# Check if port is open
sudo ufw status | grep 10400

# Allow port 10400 if needed
sudo ufw allow 10400/tcp
```

**Note**: Wyoming protocol uses raw TCP, not HTTP. Direct TCP access on port 10400 is required - nginx HTTP reverse proxy is not applicable for this service.

## Performance Considerations

### CPU Usage

Wake word detection runs continuously and processes audio streams in real-time:

- **Lightweight**: openWakeWord is optimized for edge devices
- **CPU usage**: Generally low (1-5% on modern systems)
- **Multiple models**: Loading all 5 pre-loaded models has minimal overhead

### Memory Usage

- Base container: ~200-300 MB
- Each wake word model: ~10-30 MB
- Expected total: ~500 MB with all default models

### Network Bandwidth

- Audio streaming: ~128 kbps (16-bit, 16kHz audio)
- Minimal impact on network

## Dependencies

- Podman installed and configured
- Podman user with lingering enabled

## Related Roles

- `podman` - Installs and configures Podman
- `podman-user` - Sets up rootless Podman user
- `deploy_whisper_container` - Wyoming Whisper STT service (speech-to-text)
- `deploy_piper_container` - Wyoming Piper TTS service (text-to-speech)

## References

- [Wyoming openWakeWord GitHub](https://github.com/rhasspy/wyoming-openwakeword)
- [openWakeWord](https://github.com/dscripka/openWakeWord)
- [Wyoming Protocol](https://github.com/rhasspy/wyoming)
- [Podman Quadlets Documentation](https://docs.podman.io/en/latest/markdown/podman-systemd.unit.5.html)
- [Home Assistant Wyoming Integration](https://www.home-assistant.io/integrations/wyoming/)
- [Home Assistant Voice Assistants](https://www.home-assistant.io/voice_control/)

## License

MIT

## Author

Created as part of the Ansible infrastructure automation project.
