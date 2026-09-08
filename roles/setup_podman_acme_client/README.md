# setup_podman_acme_client

Installs `acme.sh` on a Podman host and issues a DNS-01 certificate through the Hetzner Cloud DNS API. The default staging CA is used for initial testing.

The certificate contains both the base domain and wildcard SAN:

- `jo.fassbender.contact`
- `*.jo.fassbender.contact`

Certificates are installed under `/etc/ssl/wildcard/<domain>/`, matching the existing `ssl_cert` and `ssl_key` conventions used by the Nginx and service roles. Renewal is handled by the `acme.sh` cron job and reloads Nginx after installation.

Keep `podman_acme_client_dns_token` in Ansible Vault. Change `podman_acme_client_server` to `letsencrypt` only after staging validation succeeds.
