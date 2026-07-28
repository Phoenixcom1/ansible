# UniFi OS Server Container Role

Deploys UniFi OS Server in a rootless Podman setup using Quadlets, based on the UniHosted reference deployment.

## What this role does

- Deploys MongoDB 4.4 as a companion container
- Deploys `ghcr.io/unihosted/unifi-os-server-docker` with required capabilities and mounts
- Creates persistent storage directories under `/opt/podman/unifi-os-server`
- Publishes required UniFi ports for devices and services
- Publishes Web UI on localhost (`127.0.0.1:11443`) and exposes it via nginx
- Removes legacy `unifi` / `unifi-db` services and old nginx config from the previous controller role

## Defaults

Key defaults are in `defaults/main.yml`.

- Domain: `unifi2.kerberos.fassbender.contact`
- Reverse proxy upstream: `https://127.0.0.1:11443`
- System IP env: `static_ip` fallback to `ansible_host`

## Notes

- The role keeps UniFi Network App bypass (`7443`) localhost-only for security.
- First startup can take several minutes.
- Ensure nginx and wildcard certificates are available on the target host.
