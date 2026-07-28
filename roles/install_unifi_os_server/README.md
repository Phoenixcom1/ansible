# install_unifi_os_server

Installs UniFi OS Server natively on Debian and Fedora/RedHat-family Linux hosts, following the
official UniFi self-hosting Linux flow:

1. Install prerequisites (`podman`, `slirp4netns`, and `curl`/`wget`)
2. Download UniFi OS Server installer from a direct UI release URL
3. Make installer executable and run it
4. Manage `uosserver` systemd service

Reference:
https://help.ui.com/hc/en-us/articles/34210126298775-Self-Hosting-UniFi

Notes:

- Debian-family hosts use apt.
- Fedora/RedHat-family hosts use rpm checks plus dnf CLI installation for compatibility with dnf5 environments.

## Variables

- `unifi_os_server_installer_url` (required): direct Linux installer URL
- `unifi_os_server_downloader`: `curl` (default) or `wget`
- `unifi_os_server_download_dir`: target download dir, default `/opt/installers`
- `unifi_os_server_min_free_space_mb`: minimum free space in download filesystem, default `2048`
- `unifi_os_server_min_installer_size_mb`: threshold to treat existing installer as incomplete, default `700`
- `unifi_os_server_space_requirements`: installer path checks, default `/home >= 15GB`, `/tmp >= 2GB`, `/var/tmp >= 2GB`
- `unifi_os_server_reinstall`: run installer even if already installed, default `false`
- `unifi_os_server_force_download`: always re-download installer, default `false`
- `unifi_os_server_cleanup_installer`: remove installer after run, default `false`
- `unifi_os_server_installer_args`: optional args passed to installer, default empty
- `unifi_os_server_installer_auto_confirm`: auto-answer installer confirmation prompt with `y`, default `true`
- `unifi_os_server_installer_timeout_seconds`: hard timeout for installer run, default `1800`
- `unifi_os_server_show_installer_output`: print installer stdout/stderr in Ansible feedback, default `true`
- `unifi_os_server_installer_output_tail_lines`: number of stdout/stderr lines to print, default `200`
- `unifi_os_server_manage_service`: manage `uosserver` via systemd, default `true`
- `unifi_os_server_enable_on_boot`: enable at boot, default `true`
- `unifi_os_server_state`: desired service state, default `started`
- `unifi_os_server_stop_legacy_network_server`: stop/disable legacy `unifi` before install, default `true`
- `unifi_os_server_legacy_service_name`: legacy service name, default `unifi`

## Example

```yaml
- hosts: unifi_hosts
  become: true
  roles:
    - role: install_unifi_os_server
      vars:
        unifi_os_server_installer_url: "https://fw-download.ubnt.com/data/unifi-os-server/<your-linux-installer>"
```
