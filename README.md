# openstack-farm-ssh-setup
Convenience scripts for Team113 users to run on their laptop to configure SSH for the Farm, OpenStack, GitHub and GitLab

## new_openstack_host_setup.sh

Automated VM onboarding helper that sets up SSH access, registers SSH keys with GitHub/GitLab, and optionally configures dotfiles and development environments.

### Usage

```bash
./new_openstack_host_setup.sh <NEW-IP> <NEW-HOST-ALIAS> [--dotfiles <github-uri>] 
```

### Examples

```bash
# Basic setup
./new_openstack_host_setup.sh 172.27.21.59 iv3-dev-4

# With dotfiles
./new_openstack_host_setup.sh 172.27.21.59 iv3-dev-4 --dotfiles https://github.com/user/dotfiles
```

### What it does

1. Adds SSH config alias for the new VM
2. Creates SSH keypair on the VM if missing
3. Registers the VM's public key with GitHub and GitLab APIs
4. Optionally sets up dotfiles with dotbot (if GitHub registration succeeds)
5. Optionally installs R (via rig) and Python (via pyenv) versions from JSON config

### Requirements

- `ssh`, `ssh-keyscan`, `curl`, `jq`
- GitHub Personal Access Token (classic, `write:public_key` scope)
- GitLab Personal Access Token (`api` scope)

