# Ansible Setup

Ansible scripts for setting up Ubuntu and Fedora systems.

## Target setup

> [!IMPORTANT]
> When setting up a new system, this is the only section you need to do.

After successful installation of the Ubuntu or Fedora system, you need to follow these steps to bootstrap the machine for ansible:

- login with the created user
- open this README on the target system
- download the [ansible_bootstrap.sh](./ansible_bootstrap.sh) script
- navigate to the downloaded script in a terminal
- Make the script executable `chmod +x ansible_bootstrap,sh`
- Execute the script with root permissions `sudo ./ansible_bootstrap.sh`
- Or copy and run it from your workstation:

```bash
scp ansible_bootstrap.sh user@host:/tmp/ && ssh -t user@host 'sudo bash /tmp/ansible_bootstrap.sh'
```

- Get your machine staged by an ansible admin

## Install ansible

> [!WARNING]
> The following sections are only for ansible admins and are not required to be executed for getting your system staged.

<details>
<summary>Ubuntu 24.04</summary>

```bash
sudo apt install ansible
```

</details>

<details>
<summary>Fedora</summary>

```bash
sudo dnf install ansible
```

</details>

## Run ansible remotly on another machine

### Preconditions

- Have ansible installed with at least Python 3.10
- After cloning this repo initialize git-lfs
  - `git lfs fetch`
  - `git lfs checkout`
- Have access to external services via .netrc
- Have your private ssh key on hand which mathces the public key in `ansible_bootstrap.sh`
- If you are using macOS and your key is password-protected, add it to your SSH agent before running Ansible:
  - `ssh-add ~/.ssh/id_ed25519_priv`
  - or `ssh-add --apple-use-keychain ~/.ssh/id_ed25519_priv`
- Know the current IP of the machine you want to stage

## Run playbook

Ensure the target machine is listed in [the inventory file](inventory/01-lab.yml) or entere it.

Now execute one of the following commands (depending on how you installed ansible) where `host` is the domain name and `ansible_host=...` is the current ip adress of the target machine.

```
ansible-playbook noble_base.yml -i inventory/01-lab.yml -l host -e "ansible_host=xxx.xxx.xxx.xxx" -e "ansible_private_key_file=/path/to/private/ssh/key"
```

or

```
python3 -m ansible playbook noble_base.yml -i inventory/01-lab.yml -l host -e "ansible_host=xxx.xxx.xxx.xxx" -e "ansible_private_key_file=/path/to/private/ssh/key"
```

## Run ansible locally on your machine

### Prepare user information

To customize the installation for your user, we need to provide certain information to ansible.
Prepare the setup by creating a .user folder inside the ansible repo and copy the template into the folder:

```
mkdir .user
cp user_data.template.yml .user/user_data.yml
```

Fill the template file with the required information:

```yaml
---
name: # Your plain name : Max Mustermann
network:
  static_ip: # Your desired static IP (if you have one)
git_signing_key: #<optional> Your git signing key
pub_key: #<optional> Your public ssh key.
docker_registry_token: #<optional> Your docker registry token, can be retrieved from **Docker Configuration** tab and is NOT an **Application Token**
```

You can copy your Github private key into the **.user** folder and ensure the file is named **github**.
If it is not provided, ansible will create a new key pair for you. The public key is automatically generated.

You can also add the SSH keys required to access 3rd party enteties. Copy them to the **.user** folder with proper naming.

_TBD_

### Execute Playbook

to setup your local machine run the following command:

```
python3 -m ansible playbook -K site.yml - inventory
```

or

```
ansible-playbook site.yml - inventory -K
```

### Shared system setup

There are two different playbooks for shared system setups. The first one
