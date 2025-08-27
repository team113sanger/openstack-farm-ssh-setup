# openstack-farm-ssh-setup
Convenience scripts for Team113 users to run on their laptop to configure SSH for the Farm, OpenStack, GitHub and GitLab

## new_openstack_host_setup.sh

Automated VM onboarding helper that sets up SSH access, registers SSH keys with GitHub/GitLab, and optionally configures dotfiles and development environments.

### What it does

1. Adds SSH config alias for the new VM
2. Creates SSH keypair on the VM if missing
3. Registers the VM's public key with GitHub and GitLab APIs
4. Optionally sets up dotfiles with dotbot (if GitHub registration succeeds)
5. Optionally installs R (via rig) and Python (via pyenv) versions from JSON config

### Quick Start

Download and run from GitHub releases:

```bash
# Set some variables for convenience
NEW_IP="172.27.21.59"
NEW_HOST_ALIAS="iv3-dev-4"

# Download latest stable release
curl -LO https://github.com/team113sanger/openstack-farm-ssh-setup/releases/latest/download/new_openstack_host_setup.sh

# Run with interactive prompts
bash new_openstack_host_setup.sh $NEW_IP $NEW_HOST_ALIAS
```
