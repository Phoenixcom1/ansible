# TrueNAS System Configuration Role

Manages selected global TrueNAS settings through the JSON-RPC API. It
currently configures the global DNS resolver list used by TrueNAS services,
including Cloud Sync and rclone.

Enable it with:

```yaml
truenas_system_config_enabled: true
truenas_system_config_dns_nameservers:
  - "192.168.1.249"
  - "1.1.1.1"
  - "8.8.8.8"
```

The role manages only `nameserver1` through `nameserver3`; it does not change
interfaces, addresses, routes, hostname, or domain settings.
