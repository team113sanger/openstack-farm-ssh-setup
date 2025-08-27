# openstack-farm-ssh-setup
Convenience scripts for Team113 users to run on their laptop to configure SSH for the Farm, OpenStack, GitHub and GitLab

## new_openstack_host_setup.sh

Automated VM onboarding helper that sets up SSH access, registers SSH keys with GitHub/GitLab, and optionally configures dotfiles and development environments.

### Quick Start (Recommended)

Download and run from GitHub releases:

```bash
# Download latest stable release
curl -LO https://github.com/team113sanger/openstack-farm-ssh-setup/releases/latest/download/new_openstack_host_setup.sh
chmod +x new_openstack_host_setup.sh

# Run with interactive prompts
./new_openstack_host_setup.sh 172.27.21.59 iv3-dev-4

# Or with dotfiles pre-specified (skips interactive prompt)
./new_openstack_host_setup.sh 172.27.21.59 iv3-dev-4 --dotfiles git@github.com:user/dotfiles.git
```

### Download Other Versions

```bash
# Bleeding edge (canary from main branch)
curl -O https://github.com/team113sanger/openstack-farm-ssh-setup/releases/download/canary/new_openstack_host_setup.sh

# Specific version
curl -O https://github.com/team113sanger/openstack-farm-ssh-setup/releases/download/0.5.0/new_openstack_host_setup.sh
```

### Non-Interactive Usage (Advanced)

For automation where you want to skip all interactive prompts:

```bash
# Set environment variables to skip prompts
export GITHUB_PAT="your_github_token"
export GITLAB_PAT="your_gitlab_token" 
export REMOTE_SSH_USER="ubuntu"

# Run non-interactively
curl -L https://github.com/team113sanger/openstack-farm-ssh-setup/releases/latest/download/new_openstack_host_setup.sh | bash -s -- 172.27.21.59 iv3-dev-4 --dotfiles git@github.com:user/dotfiles.git
```

### Command Line Options

```bash
# Show help
./new_openstack_host_setup.sh --help

# Basic usage
./new_openstack_host_setup.sh <NEW-IP> <NEW-HOST-ALIAS>

# With dotfiles (SSH URI format required)
./new_openstack_host_setup.sh <NEW-IP> <NEW-HOST-ALIAS> --dotfiles git@github.com:user/dotfiles.git
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

