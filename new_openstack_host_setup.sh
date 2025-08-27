#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# OpenStack instance onboarding helper: add SSH config alias, mint remote id_rsa if missing,
# register the public key with GitHub and GitLab via their APIs.
# Optionally set up dotfiles with dotbot if GitHub registration succeeds.
# Optionally install R (via rig) and Python (via pyenv) versions from JSON config.
#
# Usage: ./new_openstack_host_setup.sh [--dotfiles <github-uri>] <NEW-IP> <NEW-HOST-ALIAS>
# Example: ./new_openstack_host_setup.sh 172.27.21.59 iv3-dev-4
# Example: ./new_openstack_host_setup.sh --dotfiles https://github.com/user/dotfiles 172.27.21.59 iv3-dev-4
# =============================================================================

# ---- Constants ----------------------------------------------------------------
VERSION="0.1.2"
GITHUB_API="https://api.github.com"
GITHUB_TOKEN_URL="https://github.com/settings/tokens"
GITLAB_HOST="gitlab.internal.sanger.ac.uk"
GITLAB_API="https://${GITLAB_HOST}/api/v4"
GITLAB_TOKEN_URL="https://${GITLAB_HOST}/-/user_settings/personal_access_tokens"
DEFAULT_REMOTE_SSH_USER="ubuntu"
REMOTE_SSH_USER=""

SSH_DIR="${HOME}/.ssh"
SSH_CONFIG="${SSH_DIR}/config"
BACKUP_TS="$(date +%Y%m%d-%H%M%S)"

# GitHub registration status flag
GITHUB_KEY_REGISTERED=0
# Dotfiles repository URL (optional)
DOTFILES_URL=""
# R/Python installation flags
INSTALL_R_PYTHON=0
VERSIONS_JSON_URL=""

# ---- Formatting & logging ------------------------------------------------------
format_black=$(tput setaf 0)
format_red=$(tput setaf 1)
format_green=$(tput setaf 2)
format_yellow=$(tput setaf 3)
format_blue=$(tput setaf 4)
format_magenta=$(tput setaf 5)
format_cyan=$(tput setaf 6)
format_white=$(tput setaf 7)
format_off=$(tput sgr0)

print_info()      { echo -e "${format_green}INFO: $*${format_off}" >&2; }
print_post_script(){ echo -e "${format_blue}NEXT STEPS: $*${format_off}" >&2; }
print_warning()   { echo -e "${format_yellow}WARNING: $*${format_off}" >&2; }
print_error()     { echo -e "${format_red}ERROR: $*${format_off}" >&2; }

print_usage() {
  echo "Usage: $0 [--dotfiles <github-uri>] <NEW-IP> <NEW-HOST-ALIAS>"
  echo ""
  echo "Adds an SSH config alias, ensures the OpenStack instance at <NEW-IP> has an id_rsa keypair,"
  echo "and registers its public key with GitHub/GitLab via API."
  echo "Optionally sets up dotfiles with dotbot if GitHub registration succeeds."
  echo "Optionally installs R (via rig) and Python (via pyenv) versions from JSON config."
  echo ""
  echo "Options:"
  echo "  -h, --help            Show this help message and exit"
  echo "  --dotfiles <uri>      SSH URL of dotfiles repository (git@host:user/repo.git)"
  echo "  --remote-user <user>  SSH username for the OpenStack instance (default: ${DEFAULT_REMOTE_SSH_USER})"
  echo "  --version             Show script version and exit"
  echo ""
  echo "Arguments:"
  echo "  <NEW-IP>          IPv4 address of the new OpenStack instance (e.g., 172.27.21.59)"
  echo "  <NEW-HOST-ALIAS>  SSH alias for the OpenStack instance (e.g., iv3-dev-4)"
  echo "                    Underscores will be converted to hyphens"
  echo ""
  echo "Examples:"
  echo "  $0 172.27.21.59 iv3-dev-4"
  echo "  $0 --dotfiles git@github.com:user/dotfiles.git 172.27.21.59 iv3-dev-4"
  echo "  $0 172.27.21.59 iv3_dev_4  # Converts to iv3-dev-4"
  echo ""
}

# ---- Helpers ------------------------------------------------------------------
validate_ip_address() {
  local ip="$1"
  
  # Check basic format: four dot-separated numbers
  if [[ ! "$ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
    return 1
  fi
  
  # Check each octet is between 0-255
  local IFS='.'
  local octets=($ip)
  for octet in "${octets[@]}"; do
    if (( octet > 255 )); then
      return 1
    fi
  done
  
  return 0
}

normalize_hostname() {
  local hostname="$1"
  
  # Convert underscores to hyphens
  hostname="${hostname//_/-}"
  
  # Validate hostname: alphanumeric, hyphens, and dots only
  if [[ ! "$hostname" =~ ^[a-zA-Z0-9.-]+$ ]]; then
    print_error "Invalid hostname '$hostname'. Only alphanumeric characters, hyphens, and dots are allowed."
    return 1
  fi
  
  # Check it's not empty
  if [[ -z "$hostname" ]]; then
    print_error "Hostname cannot be empty."
    return 1
  fi
  
  echo "$hostname"
}

validate_dotfiles_uri() {
  local uri="$1"
  
  # Check for SSH format: git@github.com:user/repo.git or git@gitlab.host:user/repo.git
  if [[ "$uri" =~ ^git@[a-zA-Z0-9.-]+:[a-zA-Z0-9._-]+/[a-zA-Z0-9._-]+\.git$ ]]; then
    return 0
  fi
  
  # Also accept without .git suffix
  if [[ "$uri" =~ ^git@[a-zA-Z0-9.-]+:[a-zA-Z0-9._-]+/[a-zA-Z0-9._-]+$ ]]; then
    return 0
  fi
  
  return 1
}

# ---- Arg parsing ---------------------------------------------------------------
parse_args() {
  # Handle options first
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --version)
        echo "$0 version ${VERSION}"
        exit 0
        ;;
      -h|--help)
        print_usage
        exit 0
        ;;
      --dotfiles)
        if [[ -n "$2" ]] && [[ ! "$2" =~ ^-- ]]; then
          if ! validate_dotfiles_uri "$2"; then
            print_error "Invalid dotfiles URL format: '$2'"
            print_error "Expected SSH format: git@github.com:user/repo.git or git@gitlab.host:user/repo.git"
            print_error "Examples:"
            print_error "  git@github.com:user/dotfiles.git"
            print_error "  git@gitlab.internal.sanger.ac.uk:user/dotfiles.git"
            exit 1
          fi
          DOTFILES_URL="$2"
          shift 2
        else
          print_error "Option --dotfiles requires a GitHub/GitLab SSH URL argument."
          print_usage
          exit 1
        fi
        ;;
      --remote-user)
        if [[ -n "$2" ]] && [[ ! "$2" =~ ^-- ]]; then
          REMOTE_SSH_USER="$2"
          shift 2
        else
          print_error "Option --remote-user requires a username argument."
          print_usage
          exit 1
        fi
        ;;
      -*)
        print_error "Unknown option: $1"
        print_usage
        exit 1
        ;;
      *)
        break
        ;;
    esac
  done
  
  # Check for required positional arguments
  if [[ $# -lt 2 ]]; then
    print_error "Missing required arguments: <NEW-IP> and <NEW-HOST-ALIAS>"
    print_usage
    exit 1
  fi
  
  # Validate and assign IP address
  NEW_IP="$1"
  if ! validate_ip_address "$NEW_IP"; then
    print_error "Invalid IP address format: '$NEW_IP'"
    print_error "Expected format: xxx.xxx.xxx.xxx (e.g., 172.27.21.59)"
    exit 1
  fi
  
  # Normalize and validate hostname
  local raw_alias="$2"
  if ! NEW_ALIAS="$(normalize_hostname "$raw_alias")"; then
    print_error "Failed to normalize hostname: '$raw_alias'"
    exit 1
  fi
  
  # Show normalization if it occurred
  if [[ "$raw_alias" != "$NEW_ALIAS" ]]; then
    print_info "Normalized hostname: '$raw_alias' → '$NEW_ALIAS'"
  fi

  if [[ -z "${REMOTE_SSH_USER:-}" ]]; then
    REMOTE_SSH_USER="${DEFAULT_REMOTE_SSH_USER}"
  fi

  print_info "Target: ${REMOTE_SSH_USER}@${NEW_IP} (alias: ${NEW_ALIAS})"
}

# ---- Pre-flight checks ---------------------------------------------------------
assert_tools() {
  local missing=0
  for t in ssh ssh-keyscan curl jq; do
    if ! command -v "$t" >/dev/null 2>&1; then
      print_error "Required tool not found: $t"
      missing=1
    fi
  done
  (( missing == 0 )) || exit 1
}

ensure_ssh_dir() {
  mkdir -p "${SSH_DIR}"
  chmod 700 "${SSH_DIR}"
}

backup_ssh_config() {
  if [[ -f "${SSH_CONFIG}" ]]; then
    cp "${SSH_CONFIG}" "${SSH_CONFIG}.bak.${BACKUP_TS}"
    print_info "Backed up SSH config to ${SSH_CONFIG}.bak.${BACKUP_TS}"
  else
    touch "${SSH_CONFIG}"
    chmod 600 "${SSH_CONFIG}"
    print_info "Created new SSH config at ${SSH_CONFIG}"
  fi
}

# Remove any existing block for the alias, then append the new one
upsert_ssh_config_block() {
  local tmp
  tmp="$(mktemp)"
  awk -v alias="${NEW_ALIAS}" '
    BEGIN{skip=0}
    /^Host[[:space:]]+/ {
      found=0
      for (i=2; i<=NF; i++) if ($i==alias) {found=1; break}
      if (found) { skip=1; next }
      if (skip==1) { skip=0 }
    }
    skip!=1 { print }
  ' "${SSH_CONFIG}" > "${tmp}"

  {
    echo ""
    echo "Host ${NEW_ALIAS}"
    echo "  HostName ${NEW_IP}"
    echo "  User ${REMOTE_SSH_USER}"
    echo "  IdentitiesOnly yes"
    echo "  IdentityFile ~/.ssh/id_rsa"
    echo "  AddKeysToAgent yes"
    echo "  StrictHostKeyChecking accept-new"
  } >> "${tmp}"

  mv "${tmp}" "${SSH_CONFIG}"
  chmod 600 "${SSH_CONFIG}"
  print_info "Upserted SSH config block for '${NEW_ALIAS}'."
}

preseed_known_hosts() {
  # Avoid first-connect prompt for the IP
  if ! grep -Fq "${NEW_IP}" "${SSH_DIR}/known_hosts" 2>/dev/null; then
    ssh-keyscan -H -t ed25519 "${NEW_IP}" >> "${SSH_DIR}/known_hosts" 2>/dev/null || true
    # Fallback to RSA if needed
    ssh-keyscan -H -t rsa     "${NEW_IP}" >> "${SSH_DIR}/known_hosts" 2>/dev/null || true
    print_info "Pre-seeded known_hosts for ${NEW_IP}"
  fi
}

# ---- Remote operations (run on the OpenStack instance) ----------------------------------------
remote_ensure_keypair() {
  print_info "Ensuring remote id_rsa keypair exists on ${NEW_ALIAS}..."
  ssh -o BatchMode=yes -o ConnectTimeout=10 "${REMOTE_SSH_USER}@${NEW_IP}" bash -s <<'EOF'
set -euo pipefail
mkdir -p "${HOME}/.ssh"
chmod 700 "${HOME}/.ssh"
if [[ ! -f "${HOME}/.ssh/id_rsa" || ! -f "${HOME}/.ssh/id_rsa.pub" ]]; then
  ssh-keygen -t rsa -b 4096 -N '' -f "${HOME}/.ssh/id_rsa" >/dev/null
  chmod 600 "${HOME}/.ssh/id_rsa"
  chmod 644 "${HOME}/.ssh/id_rsa.pub"
fi
EOF
}

remote_read_pubkey() {
  REMOTE_PUBKEY="$(ssh -o BatchMode=yes -o ConnectTimeout=10 "${REMOTE_SSH_USER}@${NEW_IP}" "cat ~/.ssh/id_rsa.pub")"
  if [[ -z "${REMOTE_PUBKEY}" ]]; then
    print_error "Failed to read remote public key."
    exit 1
  fi
  print_info "Fetched remote public key."
}

# ---- Token helpers -------------------------------------------------------------
ensure_github_token() {
  if [[ -n "${GITHUB_PAT:-}" ]]; then
    print_info "GITHUB_PAT already set (using existing token)."
    return 0
  fi

  print_warning "GITHUB_PAT not set."
  print_post_script "Create a ${format_yellow}Personal access token (classic)${format_blue} with:"
  print_post_script "  • ${format_yellow}Type:${format_off} classic"
  print_post_script "  • ${format_yellow}Scope:${format_off} admin:public_key"
  print_post_script "  • ${format_yellow}Expiration:${format_off} 7 days"
  print_post_script "  • ${format_yellow}Note/name:${format_off} 'OpenStack instance key upload (temporary)'"
  print_post_script "Open: ${format_yellow}${GITHUB_TOKEN_URL}${format_blue}"
  if command -v xdg-open >/dev/null 2>&1; then xdg-open "${GITHUB_TOKEN_URL}" >/dev/null 2>&1 || true
  elif command -v open >/dev/null 2>&1; then open "${GITHUB_TOKEN_URL}" >/dev/null 2>&1 || true
  elif command -v start >/dev/null 2>&1; then start "" "${GITHUB_TOKEN_URL}" >/dev/null 2>&1 || true
  fi

  echo >&2
  read -r -p "Paste new GitHub token (classic, admin:public_key, 7-day): " GITHUB_PAT
  echo >&2
  [[ -n "${GITHUB_PAT}" ]] || { print_info "Skipping GitHub key registration (no token provided)."; return 0; }

  local status
  status=$(curl -sS --connect-timeout 5 --max-time 20 \
    -o /dev/null -w "%{http_code}" \
    -H "Authorization: Bearer ${GITHUB_PAT}" \
    -H "Accept: application/vnd.github+json" \
    -X GET "${GITHUB_API}/user" || true)
  if [[ "${status}" == "401" || "${status}" == "403" ]]; then
    print_warning "GitHub token didn’t authenticate (HTTP ${status}). Ensure it's a ${format_yellow}classic${format_off} token with ${format_yellow}write:public_key${format_off}."
  fi
}

ensure_gitlab_token() {
  if [[ -n "${GITLAB_PAT:-}" ]]; then
    print_info "GITLAB_PAT already set (using existing token)."
    return 0
  fi

  print_warning "GITLAB_PAT not set."
  print_post_script "Create a token on ${format_yellow}${GITLAB_HOST}${format_blue} with:"
  print_post_script "  • ${format_yellow}Scope:${format_off} api"
  print_post_script "  • ${format_yellow}Expiration:${format_off} 7 days"
  print_post_script "  • ${format_yellow}Name:${format_off} 'OpenStack instance key upload (temporary)'"
  print_post_script "Open: ${format_yellow}${GITLAB_TOKEN_URL}${format_blue}"
  if command -v xdg-open >/dev/null 2>&1; then xdg-open "${GITLAB_TOKEN_URL}" >/dev/null 2>&1 || true
  elif command -v open >/dev/null 2>&1; then open "${GITLAB_TOKEN_URL}" >/dev/null 2>&1 || true
  elif command -v start >/dev/null 2>&1; then start "" "${GITLAB_TOKEN_URL}" >/dev/null 2>&1 || true
  fi

  echo >&2
  read -r -p "Paste new GitLab token (api scope, 7-day): " GITLAB_PAT
  echo >&2
  [[ -n "${GITLAB_PAT}" ]] || { print_info "Skipping GitLab key registration (no token provided)."; return 0; }
}

# ---- API registrations (done locally) -----------------------------------------
register_key_github() {
  if [[ -z "${GITHUB_PAT:-}" ]]; then
    print_info "Skipping GitHub key registration (no token)."
    return 0
  fi
  print_info "Registering key with GitHub..."

  local payload status
  payload=$(jq -cn \
               --arg title "${NEW_ALIAS}-$(date +%F)" \
               --arg key   "${REMOTE_PUBKEY}" \
               '{title:$title,key:$key}' \
            2>/dev/null \
            || printf '{"title":"%s","key":"%s"}' "${NEW_ALIAS}-$(date +%F)" "${REMOTE_PUBKEY}")

  status=$(curl -sS --connect-timeout 5 --max-time 20 \
    -o /dev/null -w "%{http_code}" \
    -H "Authorization: Bearer ${GITHUB_PAT}" \
    -H "Accept: application/vnd.github+json" \
    -H "Content-Type: application/json" \
    -X POST "${GITHUB_API}/user/keys" \
    -d "${payload}" || true)

  case "${status}" in
    201) 
      print_info "GitHub: key added."
      GITHUB_KEY_REGISTERED=1
      ;;
    422) 
      print_info "GitHub: key already present (ok)."
      GITHUB_KEY_REGISTERED=1
      ;;
    401|403) print_warning "GitHub: unauthorized/forbidden (HTTP ${status}). Check classic token + write:public_key." ;;
    *)   print_warning "GitHub: unexpected HTTP ${status}." ;;
  esac
}

register_key_gitlab() {
  if [[ -z "${GITLAB_PAT:-}" ]]; then
    print_info "Skipping GitLab key registration (no token)."
    return 0
  fi
  print_info "Registering key with GitLab (${GITLAB_HOST})..."

  local title status
  title="${NEW_ALIAS}-$(date +%F)"
  status=$(curl -sS --connect-timeout 5 --max-time 20 \
    -o /dev/null -w "%{http_code}" \
    --header "PRIVATE-TOKEN: ${GITLAB_PAT}" \
    --data-urlencode "title=${title}" \
    --data-urlencode "key=${REMOTE_PUBKEY}" \
    "${GITLAB_API}/user/keys" || true)

  case "${status}" in
    201) print_info "GitLab: key added." ;;
    400) print_info "GitLab: key already present (ok) or invalid input." ;;
    401) print_warning "GitLab: unauthorized (check token)." ;;
    *)   print_warning "GitLab: unexpected HTTP ${status}." ;;
  esac
}

# ---- Smoke tests (run on the OpenStack instance) ----------------------------------------------
remote_git_ssh_sanity() {
  print_info "Waiting for GitHub to finish processing the new key..."
  sleep 2 # Brief pause to allow GitHub to process the new key
  print_info "Running remote SSH smoke tests for GitHub (this may return nonzero but is informative)..."
  ssh -o BatchMode=yes "${REMOTE_SSH_USER}@${NEW_IP}" 'ssh -T -o StrictHostKeyChecking=accept-new git@github.com || true' || true
  print_info "Waiting for GitLab to finish processing the new key..."
  sleep 2 # Takes a few seconds for the GitLab server to propogate the new key
  print_info "Running remote SSH smoke tests for GitLab (this may return nonzero but is informative)..."
  ssh -o BatchMode=yes "${REMOTE_SSH_USER}@${NEW_IP}" "ssh -T -o StrictHostKeyChecking=accept-new git@${GITLAB_HOST} || true" || true
}

# ---- Dotfiles setup (if GitHub key was registered) ---------------------------
prompt_for_dotfiles() {
  if [[ "${GITHUB_KEY_REGISTERED}" -ne 1 ]]; then
    print_info "Skipping dotfiles setup (GitHub key registration did not succeed)."
    return 0
  else
    print_info "Attempting dotfiles setup (GitHub key registration succeeded)."
  fi
  
  # If DOTFILES_URL was already provided via --dotfiles, no need to prompt
  if [[ -n "${DOTFILES_URL}" ]]; then
    return 0
  fi
  
  read -r -p "Would you like to set up your dotfiles on ${NEW_ALIAS}? [y/N]: " response
  case "${response}" in
    [yY][eE][sS]|[yY])
      while true; do
        read -r -p "Enter your dotfiles repository SSH URL (git@host:user/repo.git): " DOTFILES_URL
        if [[ -z "${DOTFILES_URL}" ]]; then
          print_info "No URL provided, skipping dotfiles setup."
          break
        elif validate_dotfiles_uri "${DOTFILES_URL}"; then
          break
        else
          print_error "Invalid SSH URL format. Examples:"
          print_error "  git@github.com:user/dotfiles.git"
          print_error "  git@gitlab.internal.sanger.ac.uk:user/dotfiles.git"
          echo "Press Enter to skip or try again:" >&2
        fi
      done
      ;;
    *)
      print_info "Skipping dotfiles setup."
      ;;
  esac
}

# ---- R and Python setup prompting --------------------------------------------
prompt_for_r_python() {
  read -r -p "Would you like to install R and Python versions on ${NEW_ALIAS}? [y/N]: " response
  case "${response}" in
    [yY][eE][sS]|[yY])
      INSTALL_R_PYTHON=1
      echo >&2
      local index_url="https://t113admin-openstack.cog.sanger.ac.uk/ansible/installs/index.html"
      print_info "Opening browser to configuration files index..."
      print_info "${format_yellow}${index_url}${format_off}"
      print_info "Browse to find your old OpenStack instance configuration and copy the 'All Programs' JSON URL"
      
      # Try to open browser
      if command -v xdg-open >/dev/null 2>&1; then xdg-open "${index_url}" >/dev/null 2>&1 || true
      elif command -v open >/dev/null 2>&1; then open "${index_url}" >/dev/null 2>&1 || true
      elif command -v start >/dev/null 2>&1; then start "" "${index_url}" >/dev/null 2>&1 || true
      fi
      
      read -r -p "Paste the 'All Programs' JSON URL for your OpenStack instance (or press Enter to skip): " VERSIONS_JSON_URL
      if [[ -z "${VERSIONS_JSON_URL}" ]]; then
        print_info "No JSON URL provided, skipping R/Python installation."
        INSTALL_R_PYTHON=0
      fi
      ;;
    *)
      print_info "Skipping R and Python installation."
      INSTALL_R_PYTHON=0
      ;;
  esac
}

remote_install_dotfiles() {
  if [[ "${GITHUB_KEY_REGISTERED}" -ne 1 ]]; then
    return 0
  fi
  
  if [[ -z "${DOTFILES_URL}" ]]; then
    return 0
  fi
  
  print_info "Installing dotfiles from ${DOTFILES_URL} on ${NEW_ALIAS}..."
  
  # Run the dotfiles installation on the remote OpenStack instance
  ssh -o BatchMode=yes "${REMOTE_SSH_USER}@${NEW_IP}" bash -s <<EOF
set -euo pipefail

# Clone the dotfiles repository
if [[ -d "\${HOME}/dotfiles" ]]; then
  echo "Directory ~/dotfiles already exists, skipping clone."
else
  echo "Cloning dotfiles repository..."
  if ! git clone --recursive "${DOTFILES_URL}" "\${HOME}/dotfiles"; then
    echo "ERROR: Failed to clone dotfiles repository." >&2
    exit 1
  fi
fi

# Run dotbot
if [[ -f "\${HOME}/dotfiles/install.conf.yaml" ]]; then
  echo "Running dotbot..."
  cd "\${HOME}/dotfiles"
  if [[ -x "./dotbot/bin/dotbot" ]]; then
    ./dotbot/bin/dotbot -c install.conf.yaml || {
      echo "WARNING: dotbot execution failed, but continuing." >&2
    }
  else
    echo "WARNING: dotbot executable not found at ./dotbot/bin/dotbot" >&2
  fi
else
  echo "WARNING: install.conf.yaml not found in dotfiles repository" >&2
fi

echo "Dotfiles setup completed."
EOF
  
  if [[ $? -eq 0 ]]; then
    print_info "Dotfiles installed successfully on ${NEW_ALIAS}."
  else
    print_warning "Dotfiles installation encountered issues. Check the output above."
  fi
}

# ---- R and Python installation (from JSON config) ---------------------------
remote_install_r_versions() {
  if [[ "${INSTALL_R_PYTHON}" -ne 1 ]] || [[ -z "${VERSIONS_JSON_URL}" ]]; then
    return 0
  fi
  
  print_info "Installing R versions from ${VERSIONS_JSON_URL}..."
  
  # Fetch and parse R versions from JSON
  local r_versions
  r_versions=$(curl -sSf --connect-timeout 10 --max-time 30 "${VERSIONS_JSON_URL}" 2>/dev/null | \
    jq -r '.software.r_versions[]?' 2>/dev/null || true)
  
  if [[ -z "${r_versions}" ]]; then
    print_warning "No R versions found in JSON or failed to fetch JSON."
    return 0
  fi
  
  # Install R versions on remote OpenStack instance
  ssh -o BatchMode=yes "${REMOTE_SSH_USER}@${NEW_IP}" bash -s <<EOF
set -euo pipefail

# Check if rig is available
if ! command -v rig >/dev/null 2>&1; then
  echo "WARNING: rig command not found on remote system. Skipping R installation." >&2
  exit 0
fi

echo "Installing R versions with rig..."

# Get currently installed versions
INSTALLED_R_VERSIONS=\$(rig list --plain 2>/dev/null || true)

$(echo "${r_versions}" | while read -r version; do
  [[ -n "${version}" ]] || continue
  echo "if echo \"\${INSTALLED_R_VERSIONS}\" | grep -Fxq \"${version}\"; then"
  echo "  echo \"R ${version} already installed, skipping...\""
  echo "else"
  echo "  echo \"Installing R ${version}...\""
  echo "  rig add \"${version}\" || { echo \"WARNING: Failed to install R ${version}\" >&2; }"
  echo "fi"
done)

echo "R installation completed."
EOF
  
  if [[ $? -eq 0 ]]; then
    print_info "R versions installation completed."
  else
    print_warning "R installation encountered issues."
  fi
}

remote_install_python_versions() {
  if [[ "${INSTALL_R_PYTHON}" -ne 1 ]] || [[ -z "${VERSIONS_JSON_URL}" ]]; then
    return 0
  fi
  
  print_info "Installing Python versions from ${VERSIONS_JSON_URL}..."
  
  # Fetch and parse Python versions from JSON
  local python_versions
  python_versions=$(curl -sSf --connect-timeout 10 --max-time 30 "${VERSIONS_JSON_URL}" 2>/dev/null | \
    jq -r '.software.python_versions[]?' 2>/dev/null || true)
  
  if [[ -z "${python_versions}" ]]; then
    print_warning "No Python versions found in JSON or failed to fetch JSON."
    return 0
  fi
  
  # Install Python versions on remote OpenStack instance
  ssh -o BatchMode=yes "${REMOTE_SSH_USER}@${NEW_IP}" bash -s <<EOF
set -euo pipefail

# Check if pyenv is available
if ! command -v pyenv >/dev/null 2>&1; then
  echo "WARNING: pyenv command not found on remote system. Skipping Python installation." >&2
  exit 0
fi

echo "Installing Python versions with pyenv..."

# Get currently installed versions
INSTALLED_PYTHON_VERSIONS=\$(pyenv versions --bare 2>/dev/null || true)

$(echo "${python_versions}" | while read -r version; do
  [[ -n "${version}" ]] || continue
  echo "if echo \"\${INSTALLED_PYTHON_VERSIONS}\" | grep -Fxq \"${version}\"; then"
  echo "  echo \"Python ${version} already installed, skipping...\""
  echo "else"
  echo "  echo \"Installing Python ${version}...\""
  echo "  pyenv install -s \"${version}\" || { echo \"WARNING: Failed to install Python ${version}\" >&2; }"
  echo "fi"
done)

echo "Python installation completed."
EOF
  
  if [[ $? -eq 0 ]]; then
    print_info "Python versions installation completed."
  else
    print_warning "Python installation encountered issues."
  fi
}

# ---- Main ---------------------------------------------------------------------
main() {
  parse_args "$@"
  assert_tools
  ensure_ssh_dir
  backup_ssh_config
  upsert_ssh_config_block
  preseed_known_hosts

  remote_ensure_keypair
  remote_read_pubkey

  ensure_github_token
  register_key_github

  ensure_gitlab_token
  register_key_gitlab

  remote_git_ssh_sanity
  
  prompt_for_dotfiles
  remote_install_dotfiles
  
  prompt_for_r_python
  remote_install_r_versions
  remote_install_python_versions

  print_post_script "You can now SSH with: ${format_yellow}ssh ${NEW_ALIAS}${format_blue}"
  print_info "Done."
}

main "$@"
