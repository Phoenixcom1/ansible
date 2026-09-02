# TODO

## Repository data security

- [ ] Define and enforce runtime access controls for the Gitea data and config directories.
- [ ] Review container, Podman user, systemd, and host permissions to ensure repository data is not readable by unintended local users.
- [ ] Restrict Gitea network access to the HTTPS reverse proxy and trusted Git backup clients.
- [ ] Review SSH key ownership, rotation, revocation, and the permissions of the dedicated backup account.
- [ ] Decide whether repository data requires encryption at rest on the host, such as encrypted storage or filesystem-level encryption.
- [ ] Protect Gitea secrets, database files, repository contents, and backup archives from unauthorized access.
- [ ] Document the threat model and the recovery implications of encryption keys.

## Backup strategy

- [ ] Decide what must be backed up: repositories, Gitea database, configuration, attachments, avatars, and secrets.
- [ ] Choose the backup destination and retention policy, including an off-host or offline copy.
- [ ] Implement scheduled backups with monitoring and failure notification.
- [ ] Encrypt backup data in transit and at rest, and store encryption keys separately from the backups.
- [ ] Define whether the firewall Git repository is the primary backup, an additional copy, or only a configuration history.
- [ ] Test repository and full Gitea restoration regularly, including recovery of the dedicated backup account and SSH access.
- [ ] Document recovery time and recovery point objectives.
