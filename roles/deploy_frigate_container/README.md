# Frigate NVR Container Role

Ansible role for deploying Frigate NVR (Network Video Recorder) with hardware acceleration support using Podman Quadlets on Ubuntu 24.04.

## Overview

Frigate is an open-source NVR with real-time AI object detection. This role deploys Frigate with:

- Intel Quick Sync hardware acceleration (VAAPI)
- GPU device passthrough for efficient video processing
- go2rtc for RTSP restreaming
- Multiple stream qualities for different clients
- Home Assistant integration support

## Features

- ✅ Rootless Podman deployment via Quadlets
- ✅ Intel Quick Sync hardware acceleration
- ✅ GPU device access with proper GID mapping
- ✅ RTSP restream server (go2rtc)
- ✅ Multiple stream resolutions
- ✅ Nginx reverse proxy with SSL
- ✅ Automatic updates via Podman auto-update
- ✅ Persistent user namespace configuration

## Prerequisites

- Fedora or Ubuntu with a supported Podman installation
- Podman user configured (via `podman-user` role)
- Intel GPU with Quick Sync support
- Camera with RTSP stream
- Nginx installed

## Hardware Requirements

### Intel Quick Sync Support

This role requires an Intel CPU with Quick Sync Video support:

- Intel 6th generation (Skylake) or newer
- Integrated graphics enabled in BIOS

Verify hardware support:

```bash
# Check for Intel GPU
lspci | grep -i vga

# Check VAAPI support
vainfo

# Check render device
ls -la /dev/dri/
```

## Complex Challenge: GPU Device Access in Rootless Podman

### The Problem

Rootless Podman uses user namespaces to map host UIDs/GIDs to container UIDs/GIDs. For GPU access, the container needs membership in the host's `video` (GID 44) and `render` (GID 993) groups. However, this involves **three** layers of GID mapping:

1. **Host GIDs**: The actual system groups (video:44, render:993)
2. **Intermediate namespace GIDs**: Podman's user namespace mappings
3. **Container GIDs**: What the container sees

### The Solution

#### Step 1: Add podman user to host groups

```yaml
- name: Add podman user to video group
  user:
    name: podman
    groups: video
    append: yes

- name: Add podman user to render group
  user:
    name: podman
    groups: render
    append: yes
```

#### Step 2: Configure subordinate GIDs

Add specific host GIDs to `/etc/subgid` so podman can delegate them:

```
podman:296608:65536   # Main subordinate range
podman:44:1            # Delegate video group
podman:993:1           # Delegate render group
```

This tells the system that the `podman` user is allowed to use host GIDs 44 and 993 in user namespaces.

#### Step 3: Create intermediate namespace mapping

After `podman system migrate`, the intermediate namespace looks like:

```
Intermediate GID  →  Host GID
0                 →  1003 (podman user's GID)
1                 →  44   (video)
2                 →  993  (render)
3+                →  296608+ (subordinate range)
```

#### Step 4: Map container GIDs to intermediate GIDs

In the Quadlet file, we use `--gidmap` to map container GIDs to the intermediate namespace:

```ini
PodmanArgs=--shm-size=512mb \
  --gidmap=0:0:1 \
  --gidmap=1:3:43 \
  --gidmap=44:1:1 \
  --gidmap=45:46:948 \
  --gidmap=993:2:1 \
  --gidmap=994:994:64543 \
  --group-add=1 \
  --group-add=2
```

Breaking this down:

- `--gidmap=0:0:1`: Container root (0) → Intermediate 0 (podman user)
- `--gidmap=1:3:43`: Container 1-43 → Intermediate 3-45 (subordinate range)
- `--gidmap=44:1:1`: Container 44 → Intermediate 1 (**this is video!**)
- `--gidmap=45:46:948`: Container 45-992 → Intermediate 46-993
- `--gidmap=993:2:1`: Container 993 → Intermediate 2 (**this is render!**)
- `--gidmap=994:994:64543`: Remaining container GIDs → subordinate range

#### Step 5: Add process to groups

**Critical**: Use container GIDs that map to the intermediate namespace:

```ini
--group-add=44 --group-add=993
```

The `--gidmap` configuration maps container GID 44 → intermediate GID 1 (video) and container GID 993 → intermediate GID 2 (render). By adding the process to container groups 44 and 993, it gains access to the intermediate GIDs 1 and 2, which map to host video and render groups.

### Why This Is Necessary

Without proper mapping:

```bash
# Inside container without mapping
$ ls -ln /dev/dri/
crw-rw---- 1 65534 65534 226, 128 Jan  9 16:01 renderD128  # nobody:nobody

# With proper mapping
$ ls -ln /dev/dri/
crw-rw---- 1 65534 1 226,   0 Jan  9 16:01 card0        # nobody:video
crw-rw---- 1 65534 2 226, 128 Jan  9 16:01 renderD128   # nobody:render

# Process is in correct groups
$ id
uid=0(root) gid=0(root) groups=0(root),1,2
```

The process (groups 1,2) can now access devices (owned by GID 1,2).

## Reboot Persistence Challenge

### The Problem

After a system reboot, Frigate failed to start with:

```
[AVHWDeviceContext @ 0x...] No VA display found for device /dev/dri/renderD128.
Device creation failed: -22.
```

The user namespace wasn't being rebuilt with the current `/etc/subgid` configuration on boot.

### The Solution

Add systemd ordering to ensure proper initialization:

```ini
[Unit]
After=network-online.target default.target
```

The `After=default.target` ensures Frigate waits until the user's session is fully initialized, including the user namespace, before starting.

## Installation

### 1. Create camera credentials file

On the target host, create `/opt/podman/frigate/config/frigate.env`:

```bash
FRIGATE_CAMERA_USER=admin
FRIGATE_CAMERA_PASSWORD=your_password
FRIGATE_CAMERA_IP=192.168.107.11
```

### 2. Run the playbook

```yaml
- hosts: docker-vm
  roles:
    - deploy_frigate_container
```

Or standalone:

```bash
ansible-playbook -i inventory deploy_frigate.yml
```

## Configuration

### Default Variables (`defaults/main.yml`)

```yaml
# Podman user
podman_user: "{{ podman_username }}"

# Paths
frigate_config_dir: "/opt/podman/frigate/config"
frigate_media_dir: "/opt/podman/frigate/media"

# Network
frigate_domain: "frigate.example.com"
frigate_port: 8971 # Web UI (proxied via nginx)
frigate_rtsp_port: 8554 # RTSP restream
frigate_webrtc_tcp_port: 8555 # WebRTC

# Container resources
frigate_shm_size: "512mb"
frigate_tmpfs_size: 1000000000 # 1GB for /tmp/cache
```

### Camera Configuration

Edit the deployed config at `/opt/podman/frigate/config/config.yaml` or customize the template.

The role creates two go2rtc streams:

- `BabyCam`: Full resolution (1920x1080)
- `BabyCam_low`: Lower resolution for mobile (640x480 @ 500kbps)

Access streams at:

- `rtsp://192.168.1.118:8554/BabyCam`
- `rtsp://192.168.1.118:8554/BabyCam_low`

## Service Management

### As podman user

```bash
# Status
systemctl --user status frigate

# Logs
journalctl --user -u frigate -f

# Restart
systemctl --user restart frigate

# Check GPU usage
podman exec frigate vainfo
```

### As root (managing podman user's service)

```bash
# Status
sudo -u podman XDG_RUNTIME_DIR=/run/user/1003 systemctl --user status frigate

# Restart
sudo -u podman XDG_RUNTIME_DIR=/run/user/1003 systemctl --user restart frigate
```

### Container commands

```bash
# Check hardware acceleration
podman exec frigate vainfo --display drm --device /dev/dri/renderD128

# View ffmpeg processes
podman exec frigate ps aux | grep ffmpeg

# Check device access
podman exec frigate ls -la /dev/dri/

# Verify group membership
podman exec frigate id
```

## Verification

### 1. Check Hardware Acceleration

```bash
# Verify VAAPI is working
podman exec frigate vainfo --display drm --device /dev/dri/renderD128

# Check ffmpeg is using hardware acceleration
podman logs frigate 2>&1 | grep -i "vaapi\|hwaccel"
```

Expected in ffmpeg command:

```
-hwaccel vaapi -hwaccel_device /dev/dri/renderD128 -hwaccel_output_format vaapi
```

### 2. Check Device Permissions

```bash
# On host
ls -la /dev/dri/
# Should show: crw-rw---- 1 root render ... renderD128

# Inside container
podman exec frigate ls -ln /dev/dri/
# Should show: crw-rw---- 1 65534 2 ... renderD128

# Process groups
podman exec frigate id
# Should show: groups=0(root),1,2
```

### 3. Test RTSP Stream

```bash
# Test with ffmpeg
ffmpeg -i rtsp://192.168.1.118:8554/BabyCam -frames:v 1 test.jpg

# Test with VLC
vlc rtsp://192.168.1.118:8554/BabyCam
```

### 4. Access Web UI

Open `https://frigate.example.com` in your browser.

## Troubleshooting

### Hardware acceleration not working

**Error**: `No VA display found for device /dev/dri/renderD128`

**Solutions**:

1. Check device exists:

   ```bash
   ls -la /dev/dri/renderD128
   ```

2. Verify group membership:

   ```bash
   getent group video
   getent group render
   # Both should include 'podman'
   ```

3. Check subordinate GIDs:

   ```bash
   cat /etc/subgid | grep podman
   # Should include: podman:44:1 and podman:993:1
   ```

4. Verify intermediate namespace:

   ```bash
   podman unshare cat /proc/self/gid_map
   # Should show:
   #   0  1003  1
   #   1    44  1
   #   2   993  1
   #   3 296608 65536
   ```

5. Check container group membership:

   ```bash
   podman exec frigate id
   # Should show: groups=0(root),1,2
   ```

6. Restart with namespace migration:
   ```bash
   systemctl --user stop frigate
   podman system migrate
   systemctl --user start frigate
   ```

### Camera connection issues

**Error**: `Connection refused` or `404 Stream Not Found`

**Solutions**:

1. Verify camera IP and RTSP path:

   ```bash
   # Test from docker-vm
   ffmpeg -rtsp_transport tcp -i rtsp://user:pass@192.168.107.11/live0 -frames:v 1 test.jpg
   ```

2. Common RTSP paths by manufacturer:
   - Generic: `/live0`, `/stream1`, `/h264`
   - Hikvision: `/Streaming/Channels/101`
   - Dahua: `/cam/realmonitor?channel=1&subtype=0`
   - Reolink: `/h264Preview_01_main`

3. Check credentials in `/opt/podman/frigate/config/frigate.env`

4. Test network connectivity:
   ```bash
   ping 192.168.107.11
   nc -zv 192.168.107.11 554
   ```

### High CPU usage

**Causes**:

- Detection running at full resolution
- No hardware acceleration
- CPU-based object detection

**Solutions**:

1. Disable detection if not needed:

   ```yaml
   detect:
     enabled: false
   ```

2. Use lower resolution for detection:

   ```yaml
   detect:
     width: 640
     height: 480
   ```

3. Consider Google Coral TPU for hardware object detection

### Service won't start after reboot

**Error**: ffmpeg fails immediately on boot

**Solution**: Already implemented with `After=default.target`. If still occurring:

```bash
# Manually migrate namespace
systemctl --user stop frigate
podman system migrate
systemctl --user start frigate

# Check if issue persists after reboot
```

### Mobile WebRTC lag

**Solution**: Use the low-resolution stream:

- In Home Assistant or mobile app, change stream URL to use `BabyCam_low`
- Or configure your camera's substream directly if available

## Integration with Home Assistant

### 1. Configure go2rtc in Home Assistant

Add to Home Assistant's `configuration.yaml`:

```yaml
go2rtc:
  streams:
    babycam:
      - rtsp://192.168.1.118:8554/BabyCam
    babycam_low:
      - rtsp://192.168.1.118:8554/BabyCam_low
```

### 2. Add camera to Lovelace

```yaml
type: custom:webrtc-camera
url: babycam_low # Use low res for mobile
```

### 3. Frigate Integration

Install the Frigate integration in Home Assistant:

- Settings → Devices & Services → Add Integration → Frigate
- URL: `http://192.168.1.118:8971`

## Files Structure

```
roles/deploy_frigate_container/
├── README.md
├── defaults/
│   └── main.yml                    # Default variables
├── files/
│   └── frigate.env.example        # Example credentials file
├── handlers/
│   └── main.yml                    # Nginx reload handler
├── tasks/
│   └── main.yml                    # Main deployment tasks
└── templates/
    ├── config.yml.j2              # Frigate configuration
    ├── frigate.conf.j2            # Nginx reverse proxy config
    └── frigate.container.j2       # Podman Quadlet file
```

## Security Considerations

1. **Credentials**: Store camera credentials in `/opt/podman/frigate/config/frigate.env`, not in the Ansible repository

2. **Network exposure**: Frigate web UI is only exposed on localhost (127.0.0.1:8971) and proxied through nginx with SSL

3. **RTSP ports**: Consider firewall rules if not using nginx proxy for RTSP access

4. **Rootless container**: Runs as unprivileged user with limited access to host resources

## Performance Tips

1. **Use camera's substream** for detection instead of transcoding:

   ```yaml
   inputs:
     - path: rtsp://.../live0
       roles: [record]
     - path: rtsp://.../live1 # Lower resolution
       roles: [detect]
   ```

2. **Adjust detection resolution** based on camera distance and object size

3. **Monitor GPU usage**:

   ```bash
   # If available (may require intel-gpu-tools)
   intel_gpu_top
   ```

4. **Check ffmpeg performance**:
   ```bash
   podman exec frigate cat /dev/shm/logs/BabyCam/latest.log
   ```

## Technical Deep Dive: User Namespace GID Mapping

For those interested in the technical details, here's how the three-layer GID mapping works:

```
┌─────────────────────────────────────────────────────────────┐
│ Host System                                                  │
│ ┌─────────────────────────────────────────────────────────┐ │
│ │ /dev/dri/renderD128                                     │ │
│ │ Owner: root:render (0:993)                              │ │
│ │                                                          │ │
│ │ /etc/group:                                             │ │
│ │   video:x:44:podman                                     │ │
│ │   render:x:993:podman                                   │ │
│ │                                                          │ │
│ │ /etc/subgid:                                            │ │
│ │   podman:296608:65536  ← Main range                     │ │
│ │   podman:44:1          ← Delegate video                 │ │
│ │   podman:993:1         ← Delegate render                │ │
│ └─────────────────────────────────────────────────────────┘ │
│                              ↓                               │
│ ┌─────────────────────────────────────────────────────────┐ │
│ │ Intermediate User Namespace (after podman system migrate)│ │
│ │ /proc/self/gid_map:                                     │ │
│ │   0    1003    1      ← Container 0 → Host podman GID   │ │
│ │   1      44    1      ← Container 1 → Host video        │ │
│ │   2     993    1      ← Container 2 → Host render       │ │
│ │   3  296608 65536     ← Container 3+ → Host subordinate │ │
│ └─────────────────────────────────────────────────────────┘ │
│                              ↓                               │
│ ┌─────────────────────────────────────────────────────────┐ │
│ │ Container Namespace (via --gidmap)                      │ │
│ │                                                          │ │
│ │ /dev/dri/renderD128 appears as:                         │ │
│ │   Owner: nobody:2 (65534:2)                             │ │
│ │                                                          │ │
│ │ Process groups (via --group-add=1 --group-add=2):       │ │
│ │   uid=0(root) gid=0(root) groups=0(root),1,2            │ │
│ │                                                          │ │
│ │ Result: Process in group 2 can access device (GID 2) ✓  │ │
│ └─────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
```

The key insight: When using custom `--gidmap`, we map container GIDs 44 and 993 to intermediate GIDs 1 and 2 respectively. The `--group-add=44 --group-add=993` adds the process to these mapped container GIDs, giving it access to the host's video and render groups through the intermediate namespace.

## Related Roles

- `podman-user`: Creates and configures the podman user
- `nginx_reverse_proxy`: Configures SSL proxy for web UI

## License

MIT

## Author

Created for Ubuntu 24.04 Podman deployment with Intel Quick Sync hardware acceleration support.
