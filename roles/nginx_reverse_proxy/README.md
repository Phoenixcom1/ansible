# Nginx Reverse Proxy Role

Deploys nginx as a reverse proxy with optional global SSL configuration for HTTPS services.

## Features

- Installs `nginx` using the generic package module
- Creates SSL certificate directory `/etc/ssl/wildcard`
- Deploys global SSL defaults only when certificate files are available
- Keeps stale SSL config out of nginx when certificates are missing
- Enables nginx service with systemd
- Enables SELinux `httpd_can_network_connect` for RedHat-family systems
- Installs and configures `firewalld` on RedHat-family systems
- Opens `http` and `https` services in `firewalld`

## Role behavior

This role is intended to run before certificate provisioning. It will:

1. Ensure nginx and required directories exist
2. Create `/etc/ssl/wildcard`
3. Check for configured SSL certificate files
4. Remove stale `/etc/nginx/conf.d/00-default-ssl.conf` if certs are missing
5. Deploy the SSL config only when both cert files are present
6. Start nginx

That means the role can be executed first, and certificates can be deployed later.

## Required global variables

This role relies on global SSL variables rather than role defaults. Set these in `group_vars/all.yml` or another shared inventory file:

```yaml
ssl_cert: "/etc/ssl/wildcard/kerberos.fassbender.contact/fullchain.pem"
ssl_key: "/etc/ssl/wildcard/kerberos.fassbender.contact/key.pem"
```

If these variables are not defined, the role will fail when it attempts to reference `{{ ssl_cert }}` and `{{ ssl_key }}`.

## SSL configuration

The SSL config template is `roles/nginx_reverse_proxy/templates/00-default-ssl.conf.j2`.
It uses `ssl_cert` and `ssl_key` variables to set:

```nginx
ssl_certificate     {{ ssl_cert }};
ssl_certificate_key {{ ssl_key }};
```

If the certificate files are not present, the role removes the generated config to prevent nginx from failing on start.

## Fedora / RedHat compatibility

For RedHat-family hosts, this role also:

- sets `httpd_can_network_connect` to `true`
- installs `firewalld`
- enables and starts `firewalld`
- opens the `http` and `https` services
- reloads `firewalld`

## Usage

Include the role in your playbook, for example:

```yaml
- hosts: all
  roles:
    - nginx_reverse_proxy
```

If you want to override certificate paths, set:

```yaml
ssl_cert: "/etc/ssl/wildcard/yourdomain/fullchain.pem"
ssl_key: "/etc/ssl/wildcard/yourdomain/key.pem"
```

## Notes

- The role assumes the `ansible` user already exists if it is used elsewhere to manage the SSL directory ownership.
- The role intentionally skips SSL config deployment until the certificate files are available, allowing nginx to be installed and started before cert provisioning.
