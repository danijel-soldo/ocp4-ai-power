#!/usr/bin/env bash
# =============================================================================
# prepare-bastion.sh
# Prepares the bastion host for Single Node OpenShift (SNO) installation
# on PowerVM using the ocp4-ai-power project.
#
# Supports: RHEL 8/9, CentOS 8/9
# Must be run as root (or with sudo privileges).
# =============================================================================

set -euo pipefail

# ── Colours ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

info()    { echo -e "${CYAN}[INFO]${RESET}  $*"; }
success() { echo -e "${GREEN}[OK]${RESET}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
error()   { echo -e "${RED}[ERROR]${RESET} $*" >&2; exit 1; }

# ── Root check ────────────────────────────────────────────────────────────────
if [[ $EUID -ne 0 ]]; then
  error "This script must be run as root. Try: sudo $0"
fi

echo -e "${BOLD}"
echo "============================================================"
echo "  ocp4-ai-power – Bastion Preparation Script (SNO)"
echo "============================================================"
echo -e "${RESET}"

# ── Detect OS ─────────────────────────────────────────────────────────────────
info "Detecting operating system..."

DISTRO=$(lsb_release -ds 2>/dev/null \
  || cat /etc/*release 2>/dev/null | head -n1 \
  || uname -om \
  || echo "Unknown")

OS_VERSION=$(lsb_release -rs 2>/dev/null \
  || grep "VERSION_ID" /etc/*release 2>/dev/null \
     | awk -F= '{print $2}' | tr -d '"' \
  || echo "0")

info "Detected: ${DISTRO} (version ${OS_VERSION})"

# ── SELinux check ─────────────────────────────────────────────────────────────
info "Checking SELinux mode..."
SELINUX_MODE=$(getenforce 2>/dev/null || echo "Unknown")
if [[ "$SELINUX_MODE" == "Enforcing" ]]; then
  warn "SELinux is currently Enforcing. Setting to Permissive for this session..."
  setenforce 0
  # Make it persistent
  sed -i 's/^SELINUX=enforcing/SELINUX=permissive/' /etc/selinux/config
  success "SELinux set to Permissive (persistent). A reboot is recommended."
elif [[ "$SELINUX_MODE" == "Permissive" ]]; then
  success "SELinux is already Permissive."
else
  warn "Could not determine SELinux mode (${SELINUX_MODE}). Ensure it is set to permissive."
fi

# ── Install Ansible ───────────────────────────────────────────────────────────
info "Installing Ansible..."

if [[ "$DISTRO" != *CentOS* ]]; then
  # Red Hat / RHEL
  RHEL_VERSION=$(cat /etc/redhat-release 2>/dev/null | sed 's/[^0-9.]*//g' | cut -d. -f1,2 || echo "0")
  if awk "BEGIN {exit !($RHEL_VERSION > 8.5)}"; then
    info "RHEL > 8.5 detected – enabling codeready-builder repo..."
    subscription-manager repos --enable codeready-builder-for-rhel-9-ppc64le-rpms
    yum install -y ansible-core
  else
    info "RHEL <= 8.5 detected – enabling ansible-2.9 repo..."
    subscription-manager repos --enable ansible-2.9-for-rhel-8-ppc64le-rpms
    yum install -y ansible
  fi
else
  # CentOS
  if [[ "$OS_VERSION" != "8"* ]]; then
    info "CentOS 9 detected – installing EPEL..."
    yum install -y https://dl.fedoraproject.org/pub/epel/epel-release-latest-9.noarch.rpm
    yum install -y ansible-core
  else
    info "CentOS 8 detected – enabling powertools and EPEL..."
    yum install -y epel-release epel-next-release
    yum config-manager --set-enabled powertools
    yum install -y ansible
  fi
fi

success "Ansible installed."

# ── Install Ansible Collections ───────────────────────────────────────────────
info "Installing required Ansible collections..."

ansible-galaxy collection install community.crypto --upgrade
ansible-galaxy collection install community.general --upgrade
ansible-galaxy collection install ansible.posix --upgrade
ansible-galaxy collection install kubernetes.core --upgrade

success "Ansible collections installed."

# ── Install System Packages ───────────────────────────────────────────────────
info "Installing required system packages..."

yum install -y \
  wget \
  jq \
  git \
  net-tools \
  vim \
  tar \
  unzip \
  python3 \
  python3-pip \
  python3-jmespath \
  coreos-installer \
  grub2-tools-extra \
  bind-utils

success "System packages installed."

# ── Setup PXE TFTP Directory ──────────────────────────────────────────────────
info "Setting up PXE TFTP directory for PowerVM (grub2-mknetdir)..."

grub2-mknetdir --net-directory=/var/lib/tftpboot

success "TFTP directory created at /var/lib/tftpboot"

# ── Install and Configure httpd ───────────────────────────────────────────────
info "Installing and configuring httpd (port 8000)..."

yum install -y httpd

# Change listen port from 80 to 8000
if grep -q "^Listen 80$" /etc/httpd/conf/httpd.conf; then
  sed -i 's/^Listen 80$/Listen 8000/' /etc/httpd/conf/httpd.conf
  info "httpd configured to listen on port 8000."
else
  warn "Could not find 'Listen 80' in httpd.conf – please verify the port manually."
fi

# Create required web directories
mkdir -p /var/www/html/install
mkdir -p /var/www/html/ignition
restorecon -vR /var/www/html 2>/dev/null || true

systemctl enable --now httpd
success "httpd installed and started."

# ── Install and Configure dnsmasq ─────────────────────────────────────────────
info "Installing dnsmasq..."

yum install -y dnsmasq

success "dnsmasq installed. Configure /etc/dnsmasq.conf before starting the service."

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}${GREEN}============================================================"
echo "  Bastion preparation complete!"
echo -e "============================================================${RESET}"
echo ""
echo -e "  ${BOLD}Next steps:${RESET}"
echo "  1. Configure /etc/dnsmasq.conf (DNS / DHCP / PXE)"
echo "  2. Create /var/lib/tftpboot/boot/grub2/grub.cfg (PXE boot menu)"
echo "  3. Download RHCOS images to /var/lib/tftpboot/rhcos and /var/www/html/install"
echo "  4. Create ~/sno-work/install-config.yaml and generate the ignition file"
echo "  5. Network-boot the SNO LPAR via lpar_netboot or SMS"
echo ""
echo -e "  See the full guide: ${CYAN}quick-start.html${RESET}"
echo ""

# Made with Bob
