# Gitea Container Role

Deploys Gitea as a rootless Podman container managed by a Podman Quadlet.

The role stores Gitea data below `{{ gitea_data_dir }}`, publishes the web
interface on localhost, and configures nginx to proxy it over HTTPS. The SSH
port is published on the host LAN interfaces by default so remote backup
clients can push repositories. Restrict TCP port `2222` to trusted backup
clients in the host or network firewall. On Fedora, the role opens TCP port
`2222` for `gitea_ssh_firewall_sources`, which defaults to the local
`192.168.1.0/24` network. Override that list with only the OPNsense address in
inventory for a narrower rule. SQLite is used by default; the Gitea database
settings can be replaced with inventory variables when an external database
is required.

Run the Fedora playbook for a deployment:

```bash
ansible-playbook -i inventory/01-lab.yml fedora_base.yml -l podman-vm-pve0
```

Manage the service as the Podman user:

```bash
systemctl --user status gitea
systemctl --user restart gitea
journalctl --user -u gitea -f
```

The SSH repository URL for a remote backup client is:

```text
ssh://git@<gitea-host>:2222/<user>/<repository>.git
```
