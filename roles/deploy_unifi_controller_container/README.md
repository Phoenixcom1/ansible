# UniFi Controller Container Role

Deploys UniFi Network Controller in a Podman container with nginx reverse proxy.

## Features

- UniFi Controller in rootless Podman container
- Automatic nginx reverse proxy with SSL
- Built-in automatic backups
- Persistent configuration storage

## Configuration

### Default Settings (defaults/main.yml)

```yaml
unifi_domain: "unifi.kerberos.fassbender.contact"
unifi_port: 8443
unifi_config_dir: "/opt/podman/unifi/data"
```

### Required Ports

- **8443**: Web UI (proxied via nginx)
- **8080**: Device communication (inform)
- **3478**: STUN server (device discovery)
- **6789**: Speed test
- **8880**: HTTP portal redirect
- **8843**: HTTPS portal redirect
- **10001**: AP discovery (UDP)

## Deployment

```bash
ansible-playbook -i inventory/01-lab.yml noble_base.yml -l docker-vm
```

## Backup and Restore

### Automatic Backups

UniFi Controller creates automatic backups internally:

- **Location**: `/opt/podman/unifi/data/backup/autobackup/`
- **Frequency**: Configurable in UniFi Settings → System → Backup
- **Retention**: Configurable (default: keep recent backups)

The entire `/opt/podman/unifi` directory is backed up by Restic (if configured).

### Manual Backup

**Via UniFi Web UI:**

1. Log into UniFi Controller at https://unifi.kerberos.fassbender.contact
2. Go to **Settings** → **System** → **Backup**
3. Click **Download Backup**
4. Save the `.unf` file securely

**Via Command Line:**

```bash
# Copy latest autobackup
sudo cp /opt/podman/unifi/data/backup/autobackup/autobackup_*.unf ~/unifi-backup-$(date +%Y%m%d).unf
```

### Restore from Backup

#### Method 1: Via Web UI (Recommended)

1. **Deploy fresh UniFi Controller** (if needed):

   ```bash
   ansible-playbook -i inventory/01-lab.yml noble_base.yml -l docker-vm --tags deploy_unifi_controller_container
   ```

2. **Access UniFi Controller** at https://unifi.kerberos.fassbender.contact

3. **During initial setup**:

   - Select **"Restore from Backup"**
   - Upload your `.unf` backup file
   - Wait for restoration to complete (controller will restart)

4. **If already initialized**:
   - Go to **Settings** → **System** → **Backup**
   - Click **"Choose File"** under "Restore Backup"
   - Select your `.unf` file
   - Click **"Restore"**
   - Controller will restart automatically

#### Method 2: Via File System

1. **Stop UniFi container**:

   ```bash
   sudo -u podman podman stop unifi
   ```

2. **Clear existing data** (CAUTION: This deletes current config):

   ```bash
   sudo rm -rf /opt/podman/unifi/data/*
   ```

3. **Place backup file** in autobackup directory:

   ```bash
   sudo mkdir -p /opt/podman/unifi/data/backup/autobackup
   sudo cp your-backup.unf /opt/podman/unifi/data/backup/autobackup/
   sudo chown -R podman:podman /opt/podman/unifi/data
   ```

4. **Start UniFi container**:

   ```bash
   sudo -u podman podman start unifi
   ```

5. **Controller will auto-detect and restore** from the backup file

#### Method 3: Full Directory Restore (Restic)

If using Restic backups:

```bash
# Stop container
sudo -u podman podman stop unifi

# Restore from Restic
sudo restic -r /mnt/backup/restic-podman restore latest \
  --target / \
  --include /opt/podman/unifi

# Fix permissions
sudo chown -R podman:podman /opt/podman/unifi

# Start container
sudo -u podman podman start unifi
```

### Re-adopting Devices After Restore

After restoring a backup, UniFi devices may need to be re-adopted to the controller:

**Method 1: Via Device SSH (Most Reliable)**

1. **Get SSH credentials**:

   - UniFi Controller → **Settings** → Search for **"SSH"**
   - Note the username and password

2. **SSH into each device**:

   ```bash
   ssh <username>@<device-ip>
   ```

3. **Run set-inform command**:

   ```bash
   set-inform http://<controller_ip>:8080/inform
   ```

   Example:

   ```bash
   set-inform http://192.168.1.118:8080/inform
   ```

4. **Verify adoption**:
   - Device should appear in UniFi Controller
   - Adopt device if shown as "Pending Adoption"

**Method 2: Via UniFi Controller (If Devices Visible)**

1. Go to **Devices** in UniFi Controller
2. Click on any "Disconnected" or "Pending" device
3. Click **"Adopt"** or **"Re-adopt"**

**Common Issues:**

- **Devices not appearing**: Ensure layer 2 connectivity between controller and devices
- **Adoption fails**: Check firewall rules, ensure port 8080 is accessible
- **Different IP**: Use DNS name if available: `http://unifi.kerberos.fassbender.contact:8080/inform`

## Maintenance

### View Container Logs

```bash
sudo -u podman podman logs unifi -f
```

### Restart Container

```bash
sudo -u podman podman restart unifi
```

### Access Container Shell

```bash
sudo -u podman podman exec -it unifi bash
```

### Check Container Status

```bash
sudo -u podman podman ps -a | grep unifi
```

## Troubleshooting

### Controller Not Accessible

1. **Check container status**:

   ```bash
   sudo -u podman podman ps -a | grep unifi
   ```

2. **Check nginx config**:

   ```bash
   sudo nginx -t
   sudo systemctl status nginx
   ```

3. **Check logs**:
   ```bash
   sudo -u podman podman logs unifi --tail 100
   ```

### Devices Not Connecting

1. **Verify port 8080 is open**:

   ```bash
   sudo ss -tulpn | grep 8080
   ```

2. **Check firewall**:

   ```bash
   sudo ufw status
   ```

3. **Test inform URL** from device:
   ```bash
   curl http://<controller_ip>:8080/inform
   ```

### Database Corruption

If controller fails to start after restore:

```bash
# Check logs
sudo -u podman podman logs unifi

# If database error, may need to restore from earlier backup
# or reset and reconfigure manually
```

## Files and Directories

- **Container config**: `/opt/podman/unifi/`
- **Compose file**: `/opt/podman/unifi/compose_unifi.yml`
- **Data directory**: `/opt/podman/unifi/data/`
- **Auto backups**: `/opt/podman/unifi/data/backup/autobackup/`
- **Nginx config**: `/etc/nginx/conf.d/unifi.conf`
- **Systemd service**: Managed by Podman user systemd

## Security Notes

- Controller uses self-signed certificate internally (nginx terminates SSL)
- Web UI only accessible via nginx proxy (localhost binding)
- Device ports exposed to network for management
- Change default SSH credentials in UniFi settings after setup

## Additional Resources

- [UniFi Controller Documentation](https://help.ui.com/hc/en-us/categories/200320654-UniFi-Controller)
- [Device SSH Access](https://help.ui.com/hc/en-us/articles/204909374-UniFi-Device-SSH-Connection)
- [Backup and Restore Guide](https://help.ui.com/hc/en-us/articles/226218448-UniFi-How-to-Back-Up-and-Restore-a-UniFi-Network-Controller)
