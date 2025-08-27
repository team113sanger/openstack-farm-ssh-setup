# Changelog
All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.2] - 2025-08-27
### Fixed
- GitHub Actions workflow now correctly creates releases with the right assets

## [0.1.1] - 2025-08-27
### Changed
- Added brief sleeps before running GitHub and GitLab SSH tests to allow time for key propagation
- Improve UX of running the script
- Simplify README

## [0.1.0] - 2025-08-27
### Added
- Initial release of `new_openstack_host_setup.sh` script for automated VM onboarding
    - Automatically sets up SSH access to new VMs with convenient aliases
    - Registers VM SSH keys with GitHub and GitLab for seamless git operations
    - Optional dotfiles setup with dotbot integration
    - Optional R and Python version installation via rig and pyenv
- GitHub Actions workflow for easy installation via curl