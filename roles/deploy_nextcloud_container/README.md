# Nextcloud AIO Container Role

Deploys Nextcloud All-in-One (AIO) with Podman Quadlet in the same style as your other roles.

This role now follows the official AIO architecture:

- A single mastercontainer (`nextcloud-aio-mastercontainer`) orchestrates sibling containers.
- PostgreSQL is provided internally by AIO (official default).
- Office is included in AIO and can be enabled in AIO UI (no separate external Office container here).
- Talk high-performance backend on a dedicated server remains supported via variables and guidance.

## Important Compatibility Note

Official AIO documentation is Docker-first and says Podman is not officially supported. This role uses Podman Docker-API compatibility by mounting the rootless Podman socket to `/var/run/docker.sock` inside the mastercontainer.

If your environment has issues with this compatibility mode, the official fallback is AIO manual-install or Docker rootless.

## Features

- AIO mastercontainer via Quadlet
- PostgreSQL database via official AIO internal stack
- Included Office support via AIO (optional through AIO interface)
- Nginx reverse proxy config for your cloud domain
- Configurable host datadir via `NEXTCLOUD_DATADIR`
- Talk HPB external backend variables retained

## Architecture

- Quadlet service: `nextcloud-aio-mastercontainer`
- AIO interface: `https://127.0.0.1:8081` (self-signed, use IP access for setup)
- Nextcloud endpoint behind nginx: `https://{{ nextcloud_domain }}`
- Internal DB: PostgreSQL managed by AIO

## Configuration

Main variables are in `defaults/main.yml`.

```yaml
nextcloud_domain: "cloud.kerberos.fassbender.contact"

# AIO master image
nextcloud_aio_image: "ghcr.io/nextcloud-releases/all-in-one:latest"

# AIO interface (self-signed)
nextcloud_aio_interface_bind_ip: "127.0.0.1"
nextcloud_aio_interface_port: 8081

# AIO Apache endpoint for external nginx reverse proxy
nextcloud_aio_apache_bind_ip: "127.0.0.1"
nextcloud_aio_apache_port: 11000

# Podman compatibility for AIO Docker API client
nextcloud_aio_docker_api_version: "1.41"
nextcloud_aio_network_mode: "bridge"
nextcloud_aio_security_label_disable: true

# Optional explicit DNS for domain validation inside the mastercontainer
nextcloud_aio_dns_servers: []
nextcloud_aio_dns_search: null

# Datadir (must be set before first install and should not be changed later)
nextcloud_aio_datadir: "/opt/podman/nextcloud/data"

# Talk HPB on dedicated server
nextcloud_enable_talk_hpb: false
nextcloud_talk_hpb_url: "https://talk-backend.example.com"
nextcloud_talk_hpb_secret: "CHANGE_ME_SHARED_SECRET"
```

## Prerequisites

1. Rootless Podman socket enabled for the podman user:

```bash
systemctl --user enable --now podman.socket
```

2. Nginx role available/running on host (as with your other services).

3. DNS for `{{ nextcloud_domain }}` points to your reverse-proxy host.

## Deployment

```bash
ansible-playbook noble_base.yml -i inventory/01-lab.yml -l docker-vm --tags deploy_nextcloud_container
```

After deployment:

1. Open AIO interface locally/by IP via port 8081 and complete initial setup.
2. Ensure AIO uses your domain and reverse-proxy mode.
3. Start containers from AIO UI.
4. Access Nextcloud at your domain through nginx.

### First-Time Setup On A Headless VM

If the VM has no browser, use an SSH local tunnel from your workstation to access the AIO setup UI.

1. Start the tunnel from your local machine and keep it running:

```bash
ssh -N -L 8081:127.0.0.1:8081 -i ~/.ssh/id_ed25519_priv podman@<vm-ip>
```

2. Open the AIO setup page locally in your browser:

```text
https://127.0.0.1:8081/setup
```

3. Complete the AIO setup and start the child containers.

4. Once setup is complete, test the AIO apache endpoint on the VM:

```bash
curl -kI https://127.0.0.1:11000
```

5. Access Nextcloud via your domain through nginx.

Notes:

- Seeing `502 Bad Gateway` on your domain before step 3 is expected. Nginx proxies to port 11000, which is only available after the AIO child stack is started.
- Use `-fN` instead of `-N` if you want the tunnel in the background.

## Reverse Proxy

This role deploys nginx config at:

- `/etc/nginx/conf.d/{{ nextcloud_domain }}.conf`

It proxies to the AIO Apache endpoint on:

- `https://{{ nextcloud_aio_apache_bind_ip }}:{{ nextcloud_aio_apache_port }}`

## Talk HPB on Dedicated Server

Keep using your external dedicated Talk backend plan:

```yaml
nextcloud_enable_talk_hpb: true
nextcloud_talk_hpb_url: "https://talk-backend.example.com"
nextcloud_talk_hpb_secret: "CHANGE_ME_SHARED_SECRET"
```

Then configure Talk in Nextcloud admin settings with that signaling URL and secret.

## Service Management

```bash
# Status
systemctl --user status nextcloud-aio-mastercontainer

# Restart
systemctl --user restart nextcloud-aio-mastercontainer

# Logs
journalctl --user -u nextcloud-aio-mastercontainer -f
```

## Notes

- AIO includes PostgreSQL and Redis internally.
- AIO includes Office support internally; no separate Office container is needed in this role.
- Keep `NEXTCLOUD_DATADIR` stable after first setup, as recommended by official docs.
- If AIO reports an unsupported Docker API version with Podman, set `nextcloud_aio_docker_api_version` to a version supported by your Podman socket.
- For rootless Podman + AIO networking stability, keep `nextcloud_aio_network_mode: "bridge"`.
- If AIO domain validation fails because internal DNS is not reachable from the container, set `nextcloud_aio_dns_servers` (for example `['192.168.1.1']`).
