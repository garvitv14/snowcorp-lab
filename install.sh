#!/usr/bin/env bash
# SnowCorp Lab — installer
# Installs VirtualBox (default) or VMware stack, Vagrant, Ansible, and required collections
#
# Usage:
#   bash install.sh            # VirtualBox mode
#   bash install.sh --vmware   # VMware mode

set -e

VMWARE_MODE=false
[[ "${1:-}" == "--vmware" ]] && VMWARE_MODE=true

VAGRANT_VMW_UTIL_VERSION="1.0.23"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

ok()   { echo -e "${GREEN}[+]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
err()  { echo -e "${RED}[-]${NC} $1"; exit 1; }

detect_os() {
    if [[ "$OSTYPE" == "darwin"* ]]; then
        echo "macos"
    elif grep -qi "ubuntu\|debian\|kali" /etc/os-release 2>/dev/null; then
        echo "debian"
    else
        echo "unsupported"
    fi
}

vmware_utility_installed() {
    test -f /opt/vagrant-vmware-desktop/certificates/vagrant-utility.client.crt 2>/dev/null || \
    systemctl is-active --quiet vagrant-vmware-utility 2>/dev/null
}

install_virtualbox_debian() {
    if ! command -v VBoxManage &>/dev/null; then
        warn "Installing VirtualBox..."
        apt-get update -qq
        apt-get install -y virtualbox virtualbox-ext-pack 2>/dev/null || \
            apt-get install -y virtualbox 2>/dev/null || \
            err "VirtualBox install failed. Try manually: https://www.virtualbox.org/wiki/Linux_Downloads"
        ok "VirtualBox installed"
    else
        ok "VirtualBox already installed ($(VBoxManage --version))"
    fi
}

install_virtualbox_macos() {
    if ! command -v VBoxManage &>/dev/null; then
        warn "Installing VirtualBox..."
        brew install --cask virtualbox
        ok "VirtualBox installed"
    else
        ok "VirtualBox already installed ($(VBoxManage --version))"
    fi
}

install_vagrant_debian() {
    if ! command -v vagrant &>/dev/null; then
        warn "Installing Vagrant..."
        VAGRANT_VERSION="2.4.9"
        curl -fsSL "https://releases.hashicorp.com/vagrant/${VAGRANT_VERSION}/vagrant_${VAGRANT_VERSION}-1_amd64.deb" \
            -o /tmp/vagrant.deb
        dpkg -i /tmp/vagrant.deb
        rm /tmp/vagrant.deb
        ok "Vagrant installed"
    else
        ok "Vagrant already installed ($(vagrant --version))"
    fi
}

install_vagrant_macos() {
    if ! command -v vagrant &>/dev/null; then
        warn "Installing Vagrant..."
        brew install --cask vagrant
        ok "Vagrant installed"
    else
        ok "Vagrant already installed ($(vagrant --version))"
    fi
}

install_ansible_debian() {
    if ! command -v ansible &>/dev/null; then
        warn "Installing Ansible..."
        apt-get install -y python3-pip -qq
        pip3 install ansible --break-system-packages 2>/dev/null || pip3 install ansible
        ok "Ansible installed"
    else
        ok "Ansible already installed ($(ansible --version | head -1))"
    fi
}

install_ansible_macos() {
    if ! command -v ansible &>/dev/null; then
        warn "Installing Ansible..."
        brew install ansible
        ok "Ansible installed"
    else
        ok "Ansible already installed ($(ansible --version | head -1))"
    fi
}

install_vmware_utility_debian() {
    if vmware_utility_installed; then
        ok "Vagrant VMware Utility already installed"
        return
    fi
    warn "Installing Vagrant VMware Utility..."
    curl -fsSL \
        "https://releases.hashicorp.com/vagrant-vmware-utility/${VAGRANT_VMW_UTIL_VERSION}/vagrant-vmware-utility_${VAGRANT_VMW_UTIL_VERSION}-1_amd64.deb" \
        -o /tmp/vagrant-vmware-utility.deb
    dpkg -i /tmp/vagrant-vmware-utility.deb
    rm /tmp/vagrant-vmware-utility.deb
    systemctl enable vagrant-vmware-utility
    systemctl start vagrant-vmware-utility
    ok "Vagrant VMware Utility installed and started"
}

install_vmware_utility_macos() {
    if vmware_utility_installed; then
        ok "Vagrant VMware Utility already installed"
        return
    fi
    warn "Installing Vagrant VMware Utility..."
    brew install --cask vagrant-vmware-utility
    ok "Vagrant VMware Utility installed"
}

install_vmware_plugin() {
    if vagrant plugin list 2>/dev/null | grep -q "vagrant-vmware-desktop"; then
        ok "vagrant-vmware-desktop plugin already installed"
    else
        warn "Installing vagrant-vmware-desktop plugin..."
        vagrant plugin install vagrant-vmware-desktop
        ok "vagrant-vmware-desktop plugin installed"
    fi
}

install_debian() {
    ok "Detected Debian/Ubuntu/Kali"
    if [[ "$VMWARE_MODE" == false ]]; then
        install_virtualbox_debian
    fi
    install_vagrant_debian
    install_ansible_debian
    if [[ "$VMWARE_MODE" == true ]]; then
        install_vmware_plugin
        install_vmware_utility_debian
    fi
}

install_macos() {
    ok "Detected macOS"
    if ! command -v brew &>/dev/null; then
        err "Homebrew not found. Install it first: https://brew.sh"
    fi
    if [[ "$VMWARE_MODE" == false ]]; then
        install_virtualbox_macos
    fi
    install_vagrant_macos
    install_ansible_macos
    if [[ "$VMWARE_MODE" == true ]]; then
        install_vmware_plugin
        install_vmware_utility_macos
    fi
}

# ── Main ────────────────────────────────────────────────────────────────────

echo ""
echo "  SnowCorp Lab — Setup"
if [[ "$VMWARE_MODE" == true ]]; then
    echo "  Mode: VMware"
    echo ""
    warn "VMware Workstation (Linux/Windows) or VMware Fusion (macOS) must already be installed."
    warn "Download: https://www.vmware.com/products/desktop-hypervisor.html"
else
    echo "  Mode: VirtualBox"
fi
echo ""

OS=$(detect_os)

case $OS in
    debian) install_debian ;;
    macos)  install_macos  ;;
    *)      err "Unsupported OS. Install Vagrant, Ansible, and your hypervisor manually." ;;
esac

# Ansible collections
warn "Installing Ansible collections..."
ansible-galaxy collection install -r ansible/requirements.yml
ok "Ansible collections installed"

echo ""
if [[ "$VMWARE_MODE" == true ]]; then
    ok "All requirements installed. Run: make check-vmware  then  make up-vmware"
else
    ok "All requirements installed. Run: make check  then  make up"
fi
echo ""
