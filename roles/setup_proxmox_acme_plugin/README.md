# setup_proxmox_acme_plugin

Registers a Proxmox ACME account and configures a DNS or standalone ACME plugin on a Proxmox VE host using the native `pvenode` CLI.

The role does not install Proxmox VE. Run it against a dedicated Proxmox inventory group, for example:

```yaml
- hosts: proxmox
  become: true
  roles:
    - role: setup_proxmox_acme_plugin
      vars:
        proxmox_acme_account_email: "admin@example.com"
        proxmox_acme_domains:
          - pve.example.com
        proxmox_acme_plugin_id: hetzner
        proxmox_acme_plugin_type: dns
        proxmox_acme_plugin_api: provider_api_name
        proxmox_acme_plugin_data:
          TOKEN: "{{ proxmox_acme_api_token }}"
```

`proxmox_acme_plugin_data` should come from Ansible Vault or another secret source. The role writes it to a root-only temporary file for the `pvenode` command and removes that file afterward.

The account defaults to the Let's Encrypt production directory and is registered as `default` when it does not already exist. Set `proxmox_acme_account_email` to a real contact address before running the role.

Each entry in `proxmox_acme_domains` is assigned to an `acmedomainN` slot and
included in the certificate. Proxmox supports up to five node ACME domains.
The role then runs `pvenode acme cert order` to request or renew the certificate.

Proxmox VE native node ACME configuration accepts concrete DNS names only. It
does not accept `*.example.com` in `acmedomain0`, and the `alias` field is only
for DNS challenge validation. Use a separate DNS-01 ACME client for wildcard
certificates, then install that certificate through the workflow that consumes
it.

Existing plugin configuration is preserved by default. Set `proxmox_acme_plugin_reconfigure: true` when rotating credentials or changing plugin settings.
