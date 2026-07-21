#!/usr/bin/env bash
# SnowCorp Lab — installer
# Installs VirtualBox (default) or VMware stack, Vagrant, Ansible, and required collections
#
# Usage:
#   bash install.sh            # VirtualBox mode
#   bash install.sh --vmware   # VMware mode
#
# Under WSL2, the hypervisor stays on Windows (nesting one inside a VM is
# unreliable once Hyper-V is active), but Vagrant itself runs *inside* WSL —
# per HashiCorp's docs, vagrant.exe invoked from WSL2 "won't function
# correctly." This also matters here specifically: this repo's Vagrantfile
# uses Vagrant's built-in "ansible" provisioner, which shells out to
# ansible-playbook on whatever machine runs `vagrant` — so vagrant has to run
# where Ansible is, i.e. inside WSL2, not as vagrant.exe on Windows.
#
# See: https://developer.hashicorp.com/vagrant/docs/other/wsl

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

is_wsl() {
    grep -qi microsoft /proc/version 2>/dev/null
}

detect_os() {
    if is_wsl; then
        echo "wsl"
    elif [[ "$OSTYPE" == "darwin"* ]]; then
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

# ── WSL2 (Vagrant + Ansible run inside WSL; hypervisor stays on Windows) ────
#
# Per HashiCorp's docs, vagrant.exe invoked from inside WSL "won't function
# correctly" — Vagrant must be the Linux binary. VAGRANT_WSL_ENABLE_WINDOWS_ACCESS
# grants that Linux Vagrant access to Windows-side tools/resources (needed to
# drive the Windows-installed hypervisor), and the hypervisor's own CLI
# (VBoxManage.exe / vmrun.exe) just needs to be on PATH.

# Resolve the actual mount point of C:\ via wslpath rather than assuming the
# default /mnt/c — WSL2 instances with a customized [automount] root in
# /etc/wsl.conf (e.g. root = /) mount Windows drives elsewhere (e.g. /c).
WIN_C_ROOT="$(wslpath -u 'C:\' 2>/dev/null | sed 's:/$::')"
WIN_C_ROOT="${WIN_C_ROOT:-/mnt/c}"

# Ask Windows itself where each hypervisor is installed (registry — set by
# their own installers) rather than assuming the default Program Files path,
# which breaks for anyone who customized the install location. Falls back to
# the default path if the registry lookup fails (e.g. not installed yet).
detect_win_install_dir() {
    local reg_path="$1" value_name="$2" fallback="$3" win_dir
    win_dir="$(powershell.exe -NoProfile -Command \
        "(Get-ItemProperty '$reg_path' -ErrorAction SilentlyContinue).'$value_name'" \
        2>/dev/null | tr -d '\r\n')"
    if [[ -n "$win_dir" ]]; then
        wslpath -u "$win_dir" 2>/dev/null | sed 's:/$::'
    else
        echo "$fallback"
    fi
}

WIN_VBOX_DIR="$(detect_win_install_dir 'HKLM:\SOFTWARE\Oracle\VirtualBox' 'InstallDir' "${WIN_C_ROOT}/Program Files/Oracle/VirtualBox")"
WIN_VMWARE_DIR="$(detect_win_install_dir 'HKLM:\SOFTWARE\WOW6432Node\VMware, Inc.\VMware Workstation' 'InstallPath' "${WIN_C_ROOT}/Program Files (x86)/VMware/VMware Workstation")"

check_wsl_drive() {
    case "$(pwd)/" in
        "${WIN_C_ROOT}"/*|/mnt/*/*) ;;
        *)
            warn "This repo is on the WSL-only filesystem, not a Windows drive."
            warn "For synced folders to work, clone/move the project under a Windows-mounted path (e.g. ${WIN_C_ROOT}/Users/you/snowcorp-lab) — see README for details."
            ;;
    esac
}

check_windows_hypervisor() {
    if [[ "$VMWARE_MODE" == true ]]; then
        if [[ -d "$WIN_VMWARE_DIR" ]]; then
            ok "VMware Workstation found on Windows"
        else
            warn "VMware Workstation not found on Windows. Install it manually:"
            warn "  https://www.vmware.com/products/desktop-hypervisor.html"
        fi
    else
        if [[ -d "$WIN_VBOX_DIR" ]]; then
            ok "VirtualBox found on Windows"
            check_vbox_version
        else
            warn "VirtualBox not found on Windows. Install it manually:"
            warn "  https://www.virtualbox.org/wiki/Downloads"
        fi
    fi
}

# VirtualBox < 7.2 fails to import ANY box with UEFI firmware
# ("Unknown resource type 32768 in hardware item") — this hits essentially
# all modern Windows 11 boxes (Windows 11 requires UEFI), regardless of box
# publisher. Warn up front rather than let it surface as a cryptic
# `VBoxManage import` crash mid-`vagrant up`.
check_vbox_version() {
    local raw major minor
    raw="$("${WIN_VBOX_DIR}/VBoxManage.exe" --version 2>/dev/null | tr -d '\r\n')"
    major="$(echo "$raw" | cut -d. -f1)"
    minor="$(echo "$raw" | cut -d. -f2)"
    if [[ -z "$major" || -z "$minor" ]]; then
        return
    fi
    if (( major < 7 || (major == 7 && minor < 2) )); then
        warn "VirtualBox $raw is older than 7.2 — Windows 11 boxes (UEFI firmware)"
        warn "will fail to import with 'Unknown resource type 32768 in hardware"
        warn "item'. Upgrade to VirtualBox 7.2+ before running 'make up':"
        warn "  https://www.virtualbox.org/wiki/Downloads"
    fi
}

configure_wsl_env() {
    local marker="# snowcorp-lab: WSL2 Vagrant/Windows-hypervisor bridge"
    local block
    block="$(
        echo ""
        echo "$marker"
        echo 'export VAGRANT_WSL_ENABLE_WINDOWS_ACCESS=1'
        if [[ "$VMWARE_MODE" == true ]]; then
            echo "export PATH=\"\$PATH:$WIN_VMWARE_DIR\""
        else
            echo "export PATH=\"\$PATH:$WIN_VBOX_DIR\""
        fi
    )"
    # ~/.bashrc covers interactive shells (the common case: a user's WSL
    # terminal). It's not enough on its own, though — Debian/Kali's default
    # ~/.bashrc starts with `[ -z "$PS1" ] && return`, which skips everything
    # below it (including anything appended here) for *non-interactive*
    # shells. `make` itself doesn't care (it inherits PATH from whatever
    # already-interactive shell launched it), but a non-interactive
    # invocation used as the entry point — e.g. `wsl.exe -- bash -lc "make
    # check"` from a Windows shortcut/Task Scheduler — would source ~/.bashrc
    # and hit that early return before ever reaching these lines. ~/.profile
    # has no such guard and is read by both interactive and non-interactive
    # *login* shells, so writing there too closes that gap.
    for rc in ~/.bashrc ~/.profile; do
        if grep -qF "$marker" "$rc" 2>/dev/null; then
            ok "WSL2 environment already configured in $rc"
            continue
        fi
        warn "Configuring $rc for WSL2 (VAGRANT_WSL_ENABLE_WINDOWS_ACCESS + hypervisor PATH)..."
        echo "$block" >> "$rc"
        ok "$rc updated — open a new shell (or 'source $rc') to pick it up"
    done
    export VAGRANT_WSL_ENABLE_WINDOWS_ACCESS=1
    if [[ "$VMWARE_MODE" == true ]]; then
        export PATH="$PATH:$WIN_VMWARE_DIR"
    else
        export PATH="$PATH:$WIN_VBOX_DIR"
    fi
}

configure_defender_exclusions() {
    # Best-effort only: Windows Defender real-time scanning on VBoxManage.exe,
    # the VM storage dir, the box cache, and WSL2's own vhdx has been observed
    # to cause intermittent hangs in the WSL<->Windows interop calls Vagrant
    # makes during `vagrant up`. Excluding them is a standard, reversible
    # perf/reliability tweak — but requires admin, so skip silently (with a
    # warning) if we don't have it rather than failing the install.
    #
    # Reuses the same registry-detected hypervisor dir as everything else
    # here (not a re-guessed path), and $env:USERPROFILE for the per-user
    # dirs — both correct regardless of username or install location.
    local hv_dir_win
    if [[ "$VMWARE_MODE" == true ]]; then
        hv_dir_win="$(wslpath -w "$WIN_VMWARE_DIR" 2>/dev/null)"
    else
        hv_dir_win="$(wslpath -w "$WIN_VBOX_DIR" 2>/dev/null)"
    fi

    if HV_DIR_WIN="$hv_dir_win" powershell.exe -NoProfile -Command '
        $ErrorActionPreference = "Stop"
        if ($env:HV_DIR_WIN) { Add-MpPreference -ExclusionPath $env:HV_DIR_WIN }
        Add-MpPreference -ExclusionPath "$env:USERPROFILE\VirtualBox VMs"
        Add-MpPreference -ExclusionPath "$env:USERPROFILE\.vagrant.d"
        Add-MpPreference -ExclusionProcess "VBoxManage.exe"
        Add-MpPreference -ExclusionProcess "VBoxHeadless.exe"
        Add-MpPreference -ExclusionProcess "VBoxSVC.exe"
        Add-MpPreference -ExclusionProcess "vmware.exe"
        Add-MpPreference -ExclusionProcess "vmware-vmx.exe"
    ' >/dev/null 2>&1; then
        ok "Windows Defender exclusions added for the hypervisor (requires admin — skipped if unavailable)"
    else
        warn "Could not add Windows Defender exclusions (likely no admin rights) — skipping."
        warn "If 'vagrant up' hangs intermittently on VBoxManage calls, consider adding exclusions"
        warn "manually for VirtualBox, VM storage, and .vagrant.d — see README troubleshooting."
    fi
}

install_wsl() {
    ok "Detected WSL2 — Vagrant and Ansible run inside WSL; the hypervisor stays on Windows"
    check_wsl_drive
    check_windows_hypervisor
    install_vagrant_debian
    install_ansible_debian
    if [[ "$VMWARE_MODE" == true ]]; then
        install_vmware_plugin
    fi
    configure_defender_exclusions
    configure_wsl_env
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
    wsl)    install_wsl    ;;
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
