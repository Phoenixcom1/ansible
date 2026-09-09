# TODO

- Migrate all roles and inventory variables from `customer_domain` to the canonical `customer_url` variable, then remove the compatibility alias from `group_vars/all.yml`.
- Keep the wildcard certificate as a fallback while migrating services one at a time to dedicated ACME certificates. Update each service's certificate paths, Nginx template, renewal/reload handling, and deployment order; remove the wildcard certificate only after all services are migrated and verified.
- Add service specific cert to individual seervices
