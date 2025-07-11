#!/usr/bin/env bash

set -e

FISHER=${FISHER:-"true"}
USERNAME=${USERNAME:-"automatic"}

source /etc/os-release

cleanup() {
  case "${ID}" in
    debian|ubuntu)
      rm -rf /var/lib/apt/lists/*
    ;;
  esac
}

# Clean up
cleanup

if [ "$(id -u)" -ne 0 ]; then
  echo -e 'Script must be run as root. Use sudo, su, or add "USER root" to your Dockerfile before running this script.'
  exit 1
fi

# Ensure that login shells get the correct path if the user updated the PATH using ENV.
rm -f /etc/profile.d/00-restore-env.sh
echo "export PATH=${PATH//$(sh -lc 'echo $PATH')/\$PATH}" > /etc/profile.d/00-restore-env.sh
chmod +x /etc/profile.d/00-restore-env.sh

# Determine the appropriate non-root user
if [ "${USERNAME}" = "auto" ] || [ "${USERNAME}" = "automatic" ]; then
  USERNAME=""
  POSSIBLE_USERS=("vscode" "node" "codespace" "$(awk -v val=1000 -F ":" '$3==val{print $1}' /etc/passwd)")
  for CURRENT_USER in "${POSSIBLE_USERS[@]}"; do
    if id -u ${CURRENT_USER} > /dev/null 2>&1; then
      USERNAME=${CURRENT_USER}
      break
    fi
  done
  if [ "${USERNAME}" = "" ]; then
    USERNAME=root
  fi
elif [ "${USERNAME}" = "none" ] || ! id -u ${USERNAME} > /dev/null 2>&1; then
  USERNAME=root
fi

apt_get_update() {
  case "${ID}" in
    debian|ubuntu)
      if [ "$(find /var/lib/apt/lists/* | wc -l)" = "0" ]; then
        echo "Running apt-get update..."
        apt-get update -y
      fi
    ;;
    fedora|rhel)
      dnf update -y
    ;;
  esac
}

# Checks if packages are installed and installs them if not
check_packages() {
  case "${ID}" in
    debian|ubuntu)
      if ! dpkg -s "$@" >/dev/null 2>&1; then
        apt_get_update
        apt-get -y install --no-install-recommends "$@"
      fi
    ;;
    alpine)
      if ! apk -e info "$@" >/dev/null 2>&1; then
        apk add --no-cache "$@"
      fi
    ;;
    fedora|rhel)
      dnf install -y --setopt=install_weak_deps=False "$@"
    ;;
  esac
}

export DEBIAN_FRONTEND=noninteractive

# Install dependencies if missing
check_packages curl ca-certificates
if ! type git > /dev/null 2>&1; then
  check_packages git
fi

# Install fish shell
echo "Installing fish shell..."


case "${ID}" in
  debian|ubuntu)
    if [ "${ID}" = "ubuntu" ]; then
      echo "deb https://ppa.launchpadcontent.net/fish-shell/release-4/ubuntu ${UBUNTU_CODENAME} main" > /etc/apt/sources.list.d/shells:fish:release:4.list
      curl -fsSL "https://keyserver.ubuntu.com/pks/lookup?op=get&search=0x88421e703edc7af54967ded473c9fcc9e2bb48da" | tee -a /etc/apt/trusted.gpg.d/shells_fish_release_4.asc > /dev/null
    elif [ "${ID}" = "debian" ]; then
      echo "deb http://download.opensuse.org/repositories/shells:/fish:/release:/4/Debian_${VERSION_ID}/ /" | tee /etc/apt/sources.list.d/shells:fish:release:4.list
      curl -fsSL "https://download.opensuse.org/repositories/shells:fish:release:4/Debian_${VERSION_ID}/Release.key" | tee /etc/apt/trusted.gpg.d/shells_fish_release_4.asc > /dev/null
    fi
    curl -o xe-fish-prompt.deb https://files.xeiaso.net/dl/xe-fish-prompt_1.23.0~2-g063d5c0-dev_all.deb
    apt-get update -y
    apt-get -y install --no-install-recommends fish ./xe-fish-prompt.deb

  ;;
  alpine)
    apk add --no-cache fish
  ;;
  fedora|rhel)
    dnf install -y --setopt=install_weak_deps=False fish https://files.xeiaso.net/dl/xe-fish-prompt-1.23.0~2_g063d5c0_dev-1.noarch.rpm
  ;;
esac

fish -v

# Install Fisher
if [ "${FISHER}" = "true" ]; then
  echo "Installing Fisher..."
  fish -c 'curl -sL https://raw.githubusercontent.com/jorgebucaran/fisher/main/functions/fisher.fish | source && fisher install jorgebucaran/fisher'
  if [ "${USERNAME}" != "root" ]; then
    su $USERNAME -c 'fish -c "curl -sL https://raw.githubusercontent.com/jorgebucaran/fisher/main/functions/fisher.fish | source && fisher install jorgebucaran/fisher"'
  fi
  fish -c "fisher -v"
fi

# Clean up
cleanup

echo "Done!"
