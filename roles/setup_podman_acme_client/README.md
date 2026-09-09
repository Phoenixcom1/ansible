# setup_podman_acme_client

Installs `acme.sh` on a Podman host and issues DNS-01 certificates through the Hetzner Cloud DNS API. The default staging CA is used for initial testing.

By default, the certificate contains both the base domain and wildcard SAN:

- `jo.fassbender.contact`
- `*.jo.fassbender.contact`

Set `podman_acme_client_domains` to issue a service-specific certificate instead, for example:

```yaml
podman_acme_client_domains:
	- immich.jo.fassbender.contact
```

Certificates are installed under the configured certificate directory. Renewal is handled by the `acme.sh` cron job and reloads Nginx after installation.

Keep `podman_acme_client_dns_token` in Ansible Vault. Change `podman_acme_client_server` to `letsencrypt` only after staging validation succeeds.
