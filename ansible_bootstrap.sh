#!/bin/bash
# This script bootstraps an Ansible control node on a fresh Linux system (Ubuntu/Fedora compatible) based on an 'ansible' user, having sudo and ssh access.

SSH_PUBLIC_KEYS=(
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBpiHVEMPB9KT0nzBBV8aMHeIcq0siEwdwZxstnfiNLd enno-fassbender@web.de"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOmUS65IKukjmAtEFAXhRnVD/JceznOHQCTPpUZJWkFE root@Kerberos.localdomain"
)

PKG_CMD=""
PKG_UPDATE_CMD=""
PKG_INSTALL_CMD=""
ANSIBLE_HOME="/home/ansible"
ANSIBLE_SSH_DIR="$ANSIBLE_HOME/.ssh"
AUTHORIZED_KEYS_FILE="$ANSIBLE_SSH_DIR/authorized_keys"
SUDOERS_CONFIG_LINE="ansible ALL=(ALL) NOPASSWD:ALL"
SUDOERS_FILE="/etc/sudoers.d/90-ansible-nopasswd"
SUDO_GROUP="sudo"

# Check if running as root
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root"
  exit 1
fi

# Detect package manager and set distro-specific variables
if command -v dnf >/dev/null 2>&1; then
  PKG_CMD="dnf"
  PKG_UPDATE_CMD="dnf makecache"
  PKG_INSTALL_CMD="dnf install -y"
  SUDO_GROUP="wheel"
elif command -v yum >/dev/null 2>&1; then
  PKG_CMD="yum"
  PKG_UPDATE_CMD="yum makecache"
  PKG_INSTALL_CMD="yum install -y"
  SUDO_GROUP="wheel"
elif command -v apt-get >/dev/null 2>&1; then
  PKG_CMD="apt-get"
  PKG_UPDATE_CMD="apt-get update -y"
  PKG_INSTALL_CMD="apt-get install -y"
  SUDO_GROUP="sudo"
else
  echo "Unsupported package manager. Supported: dnf, yum, apt-get."
  exit 1
fi

OS_RELEASE_FILE="/etc/os-release"
SSH_SERVICE="ssh"
if [ -f "$OS_RELEASE_FILE" ]; then
  . "$OS_RELEASE_FILE"
  echo "Detected distribution: ${NAME:-unknown}"
  if [ "${ID:-}" = "fedora" ] || [ "${ID:-}" = "rhel" ] || [ "${ID:-}" = "centos" ] || [ "${ID:-}" = "rocky" ] || [ "${ID:-}" = "almalinux" ]; then
    SSH_SERVICE="sshd"
  fi
fi

echo "Starting Ansible control node bootstrap..."

# --- Step 1: Install open-ssh-server if not installed ---
echo ""
echo "---Installing OpenSSH Server if not present---"

echo "Updating package lists..."
$PKG_UPDATE_CMD
if [ $? -ne 0 ]; then
  echo "Failed to update package lists. Exiting."
  # Do not exit here, try installing openssh-server anyway
  #exit 1
fi

#install openssh-server
echo "Installing openssh-server..."
$PKG_INSTALL_CMD openssh-server
if [ $? -ne 0 ]; then
  echo "Failed to install openssh-server. Exiting."
  exit 1
fi
echo "OpenSSH Server installation completed."

# --- Step 2: Persistently enable sshd.service ---
echo ""
echo "--- Enabling $SSH_SERVICE.service to start on boot---"
systemctl enable --now "$SSH_SERVICE"
if [ $? -ne 0 ]; then
  echo "Failed to enable/start $SSH_SERVICE.service. Exiting."
  exit 1
fi
echo "sshd.service is enabled and started."

# --- Step 3: Create 'ansible' user if not exists ---
echo ""
echo "---Creating 'ansible' user if not exists---"

# Check if user 'ansible' exists
if id "ansible" &>/dev/null; then
    echo "User 'ansible' already exists. Skipping user creation."
else
    echo "Creating user 'ansible'..."
    # -m flag creates home directory if it does not exist
    # -s flag sets the shell to bash
    useradd -m -s /bin/bash ansible
    if [ $? -ne 0 ]; then
      echo "Failed to create user 'ansible'. Exiting."
      exit 1
    fi
    echo "User 'ansible' created successfully with bash shell."
fi

# Ensure ansible user has bash shell (in case user already existed)
echo "Ensuring ansible user has bash shell..."
usermod -s /bin/bash ansible
if [ $? -ne 0 ]; then
  echo "Warning: Failed to set bash shell for ansible user."
fi

# --- Step 4: Add 'ansible' user to sudo group ---
echo ""
echo "---Adding 'ansible' user to sudo group---"
usermod -aG $SUDO_GROUP ansible
if [ $? -ne 0 ]; then
  echo "Failed to add 'ansible' user to sudo group. Exiting."
  exit 1
fi
echo "'ansible' user added to group $SUDO_GROUP."
echo "The user 'ansible' will have sudo privileges after login."

# --- Step 5: Create an .ssh directory for 'ansible' user ---
echo ""
echo "---Creating .ssh directory for 'ansible' user---"

# Ensure home directory exists
if [ ! -d "$ANSIBLE_HOME" ]; then
    echo "Home directory $ANSIBLE_HOME does not exist."
    exit 1
fi

# Create .ssh directory if it does not exist
if [ -d "$ANSIBLE_SSH_DIR" ]; then
    echo ".ssh directory already exists. Skipping creation."
else
    echo "Creating directory $ANSIBLE_SSH_DIR..."
    mkdir "$ANSIBLE_SSH_DIR"
    if [ $? -ne 0 ]; then
      echo "Failed to create .ssh directory. Exiting."
      exit 1
    fi
    echo "$ANSIBLE_SSH_DIR directory created."
fi

# Set ownership and permissions
echo "Setting permissions for $ANSIBLE_SSH_DIR to 700"
chmod 700 "$ANSIBLE_SSH_DIR"
if [ $? -ne 0 ]; then
  echo "Failed to set permissions for .ssh directory. Exiting."
  exit 1
fi
echo "Permissions set to 700."

# Set ownership to ansible user
echo "Setting ownership of $ANSIBLE_SSH_DIR to 'ansible' user"
chown ansible:ansible "$ANSIBLE_SSH_DIR"
if [ $? -ne 0 ]; then
  echo "Failed to set ownership for .ssh directory. Exiting."
  exit 1
fi
echo "Ownership set to 'ansible' user."
echo ".ssh directory setup completed."

# --- Step 6: Add multiple SSH public keys to authorized_keys ---
echo ""
echo "---Adding SSH public keys to authorized_keys---"

# Clear existing authorized_keys file or create if not exists
echo "Creating/clearing $AUTHORIZED_KEYS_FILE..."
echo "" > "$AUTHORIZED_KEYS_FILE"
if [ $? -ne 0 ]; then
  echo "Failed to create/clear authorized_keys file. Exiting."
  exit 1
fi
echo "Cleared or created $AUTHORIZED_KEYS_FILE."

echo "Adding ${#SSH_PUBLIC_KEYS[@]} SSH public keys to $AUTHORIZED_KEYS_FILE..."
for KEY in "${SSH_PUBLIC_KEYS[@]}"; do
    #Append each key to authorized_keys
    echo "$KEY" | tee -a "$AUTHORIZED_KEYS_FILE" > /dev/null
    if [ $? -ne 0 ]; then
      echo "Warning: Failed to add $KEY to $AUTHORIZED_KEYS_FILE."
      #Don't exit, continue with other keys
    fi
done
echo "SSH public keys added to $AUTHORIZED_KEYS_FILE."

#Set minimum permissions for authorized_keys (600)
chmod 600 "$AUTHORIZED_KEYS_FILE"
if [ $? -ne 0 ]; then
  echo "Failed to set permissions for authorized_keys file. Exiting."
  exit 1
fi
echo "Permissions set to 600 for $AUTHORIZED_KEYS_FILE."

# Set ownership for authorized_keys (should already be ansible:ansible from tee but just to be sure)
echo "Setting ownership of $AUTHORIZED_KEYS_FILE to 'ansible' user"
chown ansible:ansible "$AUTHORIZED_KEYS_FILE"
if [ $? -ne 0 ]; then
  echo "Failed to set ownership for authorized_keys file. Exiting."
  exit 1
fi
echo "Ownership set to 'ansible' user."
echo "SSH key setup completed."

# --- Step 7: Configure passwordless sudo for 'ansible' user ---
echo ""
echo "---Configuring passwordless sudo for 'ansible' user---"

#Check if sudoers file already exists
if [ -f "$SUDOERS_FILE" ]; then
    echo "Sudoers file $SUDOERS_FILE already exists. Skipping creation."
fi

echo "Creating sudoers file $SUDOERS_FILE with NOPASSWD configuration..."

#use echo to write the line to the sudoers file
echo "$SUDOERS_CONFIG_LINE" > "$SUDOERS_FILE"
if [ $? -ne 0 ]; then
  echo "Failed to create sudoers file. Exiting."
  exit 1
fi
echo "Sudoers file created."

#Set ownership and permissions
echo "Setting ownership of $SUDOERS_FILE to root:root"
chown root:root "$SUDOERS_FILE"
if [ $? -ne 0 ]; then
  echo "Failed to set ownership for sudoers file. Exiting."
  exit 1
fi
echo "Ownership set to root:root."

#Set permissions to 440
echo "Setting permissions of $SUDOERS_FILE to 440"
chmod 440 "$SUDOERS_FILE"
if [ $? -ne 0 ]; then
  echo "Failed to set permissions for sudoers file. Exiting."
  exit 1
fi
echo "Permissions set to 440."
echo "NOPASSWD sudo configuration completed."

exit 0