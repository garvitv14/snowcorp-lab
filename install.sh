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

WIN_VBOX_DIR="/mnt/c/Program Files/Oracle/VirtualBox"
WIN_VMWARE_DIR="/mnt/c/Program Files (x86)/VMware/VMware Workstation"

check_wsl_drive() {
    case "$(pwd)" in
        /mnt/*) ;;
        *)
            warn "This repo is on the WSL-only filesystem, not a Windows drive."
            warn "For synced folders to work, clone/move the project under a Windows-mounted path (e.g. /mnt/c/Users/you/snowcorp-lab) — see README for details."
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
        else
            warn "VirtualBox not found on Windows. Install it manually:"
            warn "  https://www.virtualbox.org/wiki/Downloads"
        fi
    fi
}

configure_wsl_env() {
    local marker="# snowcorp-lab: WSL2 Vagrant/Windows-hypervisor bridge"
    local already_configured=false
    if grep -qF "$marker" ~/.bashrc 2>/dev/null; then
        ok "WSL2 environment already configured in ~/.bashrc"
        already_configured=true
    else
        warn "Configuring ~/.bashrc for WSL2 (VAGRANT_WSL_ENABLE_WINDOWS_ACCESS + hypervisor PATH)..."
        {
            echo ""
            echo "$marker"
            echo 'export VAGRANT_WSL_ENABLE_WINDOWS_ACCESS=1'
            if [[ "$VMWARE_MODE" == true ]]; then
                echo "export PATH=\"\$PATH:$WIN_VMWARE_DIR\""
            else
                echo "export PATH=\"\$PATH:$WIN_VBOX_DIR\""
            fi
        } >> ~/.bashrc
    fi

    # Always export into THIS process too, regardless of whether ~/.bashrc
    # already had the marker - .bashrc is only read by new interactive
    # shells, never by a script invocation like `bash install.sh`, so
    # relying solely on the "already configured" branch above meant every
    # run after the very first one left this script's own PATH without the
    # hypervisor directory, making `command -v VBoxManage.exe` fail here on
    # every subsequent run (confirmed by direct testing, 2026-07-26) - a
    # silent, reliably-reproducing regression that only the first-ever run
    # avoided.
    export VAGRANT_WSL_ENABLE_WINDOWS_ACCESS=1
    if [[ "$VMWARE_MODE" == true ]]; then
        export PATH="$PATH:$WIN_VMWARE_DIR"
    else
        export PATH="$PATH:$WIN_VBOX_DIR"
    fi
    if [[ "$already_configured" == false ]]; then
        ok "~/.bashrc updated — open a new shell (or 'source ~/.bashrc') to pick it up"
    fi
}

# ── VirtualBox host-only networks (lab.local / corp.local) ─────────────────
#
# This lab's Vagrantfile requests two private networks (192.168.136.0/24 for
# lab.local, 10.10.10.0/24 for corp.local) with no hardcoded adapter name, so
# Vagrant's VirtualBox provider auto-creates a host-only adapter for each on
# first `vagrant up`. Confirmed by direct testing: that auto-created adapter
# gets the GUEST side's IP set correctly, but its HOST side is left on
# whatever address VirtualBox/Windows assigns by default (an APIPA
# 169.254.x.x address) — not the requested subnet. The host (and this WSL2
# environment) then has no route to the guest network at all, so WinRM and
# Ansible can't reach any of the VMs even though they boot fine. Pre-creating
# and IP'ing the adapters here means `vagrant up` finds an existing adapter
# already on the right subnet and reuses it instead.
#
# On Windows/WSL specifically, `VBoxManage hostonlyif ipconfig` itself is
# unreliable: confirmed by direct testing that it returns exit 0 and reports
# success while silently leaving the adapter's actual Windows-side IP on an
# APIPA address — the write never takes. Using PowerShell's New-NetIPAddress
# instead (as an ADDITIONAL address, leaving VirtualBox's own auto-assigned
# one in place) reliably works, but only if the target IP isn't already
# statically claimed by some other adapter on the host (e.g. a VMware vnet
# reusing the same subnet) — Windows correctly refuses that as a duplicate,
# which surfaces as the same "already exists" error. So: check for a
# conflicting owner first and warn instead of silently failing, then verify
# the assignment actually landed instead of trusting the exit code.
setup_hostonly_networks() {
    [[ "$VMWARE_MODE" == true ]] && return  # VMware uses vmnet, not VirtualBox host-only adapters

    local vboxmanage
    if is_wsl; then
        vboxmanage="VBoxManage.exe"
    else
        vboxmanage="VBoxManage"
    fi
    # Explicit "return 0", not a bare "return" - a bare return here defaults
    # to the exit status of the failed `command -v` (1), which under this
    # file's `set -e` silently kills the entire install the moment this
    # guard clause is hit as a bare statement (confirmed by direct testing,
    # 2026-07-26) - exactly the failure mode this whole file has been
    # fighting tonight. "Not installed yet" is a graceful no-op, not a
    # failure, so it must return 0.
    command -v "$vboxmanage" &>/dev/null || return 0

    # WSL's Linux→Windows interop does NOT pass ordinary shell env vars into
    # a launched Windows process (only names listed in WSLENV cross that
    # boundary) — confirmed by direct testing: $env:SCLAB_* read back empty
    # inside PowerShell even though the bash side set them correctly. Values
    # are embedded as escaped literals in the -Command string instead.
    ps_quote() { printf '%s' "$1" | sed "s/'/''/g"; }

    set_host_ip_windows() {
        local adapter_name ip
        adapter_name=$(ps_quote "$1")
        ip=$(ps_quote "$2")
        powershell.exe -NoProfile -NonInteractive -Command "
            \$adapter = Get-NetAdapter -InterfaceDescription '$adapter_name' -ErrorAction SilentlyContinue
            if (-not \$adapter) { Write-Output 'NOADAPTER'; exit }
            \$existing = Get-NetIPAddress -InterfaceIndex \$adapter.ifIndex -IPAddress '$ip' -AddressFamily IPv4 -ErrorAction SilentlyContinue
            if (\$existing) { Write-Output 'OK'; exit }
            \$conflict = Get-NetIPAddress -IPAddress '$ip' -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object { \$_.InterfaceIndex -ne \$adapter.ifIndex }
            if (\$conflict) { Write-Output ('CONFLICT:' + \$conflict[0].InterfaceAlias); exit }
            try { New-NetIPAddress -InterfaceIndex \$adapter.ifIndex -IPAddress '$ip' -PrefixLength 24 -ErrorAction Stop | Out-Null } catch { Write-Output ('SETFAILED:' + \$_.Exception.Message); exit }
            Start-Sleep -Seconds 2
            \$check = Get-NetIPAddress -InterfaceIndex \$adapter.ifIndex -IPAddress '$ip' -AddressFamily IPv4 -ErrorAction SilentlyContinue
            if (\$check) { Write-Output 'OK' } else { Write-Output 'NOTVERIFIED' }
        " 2>/dev/null | tr -d '\r'
    }

    # `VBoxManage list hostonlyifs` only ever reports ONE address per adapter
    # (whichever VirtualBox itself considers "primary"), so it can miss an IP
    # we added as a secondary address via PowerShell above — confirmed by
    # direct testing to under-report inconsistently. On Windows/WSL, check
    # the real interface state instead of trusting that listing. Note:
    # Get-NetIPAddress's bulk (non-by-index) results leave InterfaceDescription
    # blank on this host (confirmed by direct testing) — cross-reference via
    # InterfaceIndex against Get-NetAdapter instead of filtering by description
    # directly on the address objects.
    find_adapter_on_subnet_windows() {
        local subnet
        subnet=$(ps_quote "$1")
        powershell.exe -NoProfile -NonInteractive -Command "
            \$vboxIdx = (Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { \$_.InterfaceDescription -like 'VirtualBox Host-Only*' }).ifIndex
            \$match = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object { (\$vboxIdx -contains \$_.InterfaceIndex) -and \$_.IPAddress.StartsWith('$subnet.') } | Select-Object -First 1
            if (\$match) { (Get-NetAdapter -InterfaceIndex \$match.InterfaceIndex).InterfaceDescription }
        " 2>/dev/null | tr -d '\r'
    }

    # WSL2's "mirrored" networking mode (used here previously) is a known,
    # currently-unresolved source of instability with VirtualBox host-only
    # adapters (matches open upstream reports - e.g. microsoft/WSL#13454,
    # #40752) - confirmed firsthand (2026-07-26): it can drop every
    # host-only interface mid-run with no reliable fix, not even a full
    # reboot. Switched to WSL2's default NAT networking mode instead (see
    # ~/.wslconfig - `networkingMode=mirrored` removed) plus explicit
    # routing: standard host-based IP forwarding between WSL2's own NAT
    # network and the VirtualBox host-only networks, which is a
    # fundamentally more stable mechanism than dynamic interface mirroring
    # - confirmed working end-to-end by direct testing the same night this
    # was switched.
    #
    # This needs to run every time WSL2 restarts (the WSL-side gateway IP
    # and any routes added are not persistent across `wsl --shutdown` or a
    # reboot), which is why it's part of this pre-flight check, run before
    # every `make up`.
    ensure_wsl_nat_route() {
        local adapter_name="$1" host_ip="$2"
        local subnet
        subnet=$(echo "$host_ip" | cut -d. -f1-3)

        # Never hardcode the WSL gateway IP - it's assigned by Windows/WSL
        # per machine and per WSL version (seen firsthand as 172.29.208.1
        # on this machine; it can differ on others), so discover it fresh
        # every time from WSL's own default route.
        local wsl_gateway
        wsl_gateway=$(ip route show default 2>/dev/null | awk '/^default/ {print $3; exit}')
        if [[ -z "$wsl_gateway" ]]; then
            err "Could not determine WSL2's own default gateway (no 'default' route found).
    This means WSL2's basic NAT networking isn't up at all, which is more fundamental than
    anything this repo can fix - check 'wsl --status' and that ~/.wslconfig doesn't still have
    networkingMode=mirrored (this repo now expects default/NAT mode, not mirrored)."
        fi

        # Enable IP forwarding on the Windows-side WSL vSwitch (the
        # adapter that owns $wsl_gateway) and on this specific VirtualBox
        # host-only adapter - both directions of the same route need
        # forwarding enabled.
        #
        # Set-NetIPInterface -Forwarding Enabled needs a genuinely elevated
        # token - confirmed by direct testing (2026-07-26) that it fails
        # with "Access is denied" even from an Administrators-group session
        # whose token has UAC filtering applied, which is the norm for any
        # interactively-launched process (including WSL's own powershell.exe
        # interop launches, and even this project's own elevated-looking
        # tooling after a plain reboot). Worse: that failure happens even
        # with -ErrorAction SilentlyContinue on the cmdlet itself -
        # SilentlyContinue stops the *script* from halting on the error, but
        # powershell.exe's own process exit code still comes back 1 whenever
        # any error was written to the error stream during a -Command
        # invocation, regressed or not. Combined with this file's `set -e`
        # and the old ">/dev/null 2>&1" redirect, that 1 silently killed the
        # entire install with no visible error at all - exactly what was
        # happening here before this was found.
        #
        # Fix: check current state without elevation first (free, no
        # privilege needed - forwarding is a persistent machine-wide setting
        # that survives reboots and WSL restarts, so this is a no-op on every
        # run after the first). Only if it's actually off, request elevation
        # via Start-Process -Verb RunAs - a single, real Windows UAC consent
        # prompt the interactive user approves once, same spirit as the
        # `sudo` prompt already used below for the WSL-side route. Never let
        # this call's own exit code reach `set -e` - always capture output
        # and branch on it explicitly instead of running it as a bare
        # redirected statement.
        local fwd_status
        fwd_status=$(timeout 60 powershell.exe -NoProfile -NonInteractive -Command "
            \$ErrorActionPreference = 'SilentlyContinue'
            \$gwIdx = (Get-NetIPAddress -AddressFamily IPv4 -IPAddress '$(ps_quote "$wsl_gateway")').InterfaceIndex
            \$hoIdx = (Get-NetAdapter -InterfaceDescription '$(ps_quote "$adapter_name")').ifIndex
            if (-not \$gwIdx -or -not \$hoIdx) { Write-Output 'FORWARDING_SKIP:missing-adapter'; exit }
            \$gwFwd = (Get-NetIPInterface -InterfaceIndex \$gwIdx -AddressFamily IPv4).Forwarding
            \$hoFwd = (Get-NetIPInterface -InterfaceIndex \$hoIdx -AddressFamily IPv4).Forwarding
            if (\$gwFwd -eq 'Enabled' -and \$hoFwd -eq 'Enabled') { Write-Output 'FORWARDING_OK'; exit }
            \$cmd = \"Set-NetIPInterface -InterfaceIndex \$gwIdx,\$hoIdx -Forwarding Enabled\"
            try {
                Start-Process powershell.exe -Verb RunAs -WindowStyle Hidden -Wait -ArgumentList '-NoProfile','-NonInteractive','-Command',\$cmd -ErrorAction Stop
            } catch {
                Write-Output \"FORWARDING_ELEVATION_FAILED:\$(\$_.Exception.Message)\"
                exit
            }
            Start-Sleep -Milliseconds 500
            \$gwFwd2 = (Get-NetIPInterface -InterfaceIndex \$gwIdx -AddressFamily IPv4).Forwarding
            \$hoFwd2 = (Get-NetIPInterface -InterfaceIndex \$hoIdx -AddressFamily IPv4).Forwarding
            if (\$gwFwd2 -eq 'Enabled' -and \$hoFwd2 -eq 'Enabled') { Write-Output 'FORWARDING_OK' } else { Write-Output 'FORWARDING_STILL_DISABLED' }
        " 2>/dev/null | tr -d '\r')

        case "$fwd_status" in
            FORWARDING_OK|FORWARDING_SKIP:*)
                ;;
            *)
                warn "Could not confirm IP forwarding is enabled between WSL and '$adapter_name' (${fwd_status:-no response/timed out})."
                warn "This is a one-time Windows setting that needs an elevated (Admin) prompt approved - if you"
                warn "didn't see/approve a UAC prompt just now, run this ONCE in an elevated PowerShell window:"
                warn "  \$gw = (Get-NetIPAddress -AddressFamily IPv4 -IPAddress '$wsl_gateway').InterfaceIndex"
                warn "  \$ho = (Get-NetAdapter -InterfaceDescription '$adapter_name').ifIndex"
                warn "  Set-NetIPInterface -InterfaceIndex \$gw,\$ho -Forwarding Enabled"
                warn "Continuing - the final reachability check will fail loudly if this actually breaks connectivity."
                ;;
        esac

        if ip route show 2>/dev/null | grep -q "^${subnet}\.0/24 "; then
            ok "WSL already has a route to ${subnet}.0/24 via $wsl_gateway"
            return
        fi
        # Adding a route needs root - sudo here is the normal, expected way
        # for a real interactive user (one password prompt per WSL
        # session, same as any other setup step needing elevation) - this
        # is not a workaround for a workaround, just standard Linux
        # privilege escalation. (setcap-based passwordless routing was
        # tried and confirmed NOT to work reliably in this WSL2 setup -
        # not worth chasing further.)
        #
        # Wrapped in `timeout` - confirmed by direct testing (2026-07-26)
        # that `sudo` itself can hang indefinitely (stuck before even
        # exec'ing into `ip`, no child process) right after WSL2's idle
        # route-wipe, almost certainly a PAM/NSS lookup stalling on
        # momentarily-broken DNS/networking during that same window. A
        # hang here previously blocked the whole install with no feedback;
        # now it times out and falls through to the manual-fallback message
        # below instead.
        if timeout 20 sudo ip route add "${subnet}.0/24" via "$wsl_gateway" 2>/dev/null; then
            ok "WSL route added: ${subnet}.0/24 via $wsl_gateway (adapter '$adapter_name')"
        else
            err "Could not add WSL route for ${subnet}.0/24 via $wsl_gateway.
    Manually run inside WSL:
      sudo ip route add ${subnet}.0/24 via $wsl_gateway"
        fi
    }

    ensure_hostonly_adapter() {
        local subnet="$1" host_ip="$2"
        local existing
        if is_wsl; then
            existing=$(find_adapter_on_subnet_windows "$subnet")
        else
            existing=$("$vboxmanage" list hostonlyifs 2>/dev/null | awk -v subnet="$subnet" '
                /^Name:/ { name=$0; sub(/^Name:[ \t]*/, "", name) }
                /^IPAddress:/ { ip=$0; sub(/^IPAddress:[ \t]*/, "", ip); if (index(ip, subnet ".") == 1) { print name; exit } }
            ')
        fi
        if [[ -n "$existing" ]]; then
            ok "Host-only adapter for ${subnet}.0/24 already configured: $existing"
            # Explicit "return 0" - on native (non-WSL) Linux, `is_wsl`
            # short-circuits the `&&` before ensure_wsl_nat_route ever runs,
            # so a bare `return` here would pick up is_wsl's own exit code
            # (1, since it's false there) and silently kill the script under
            # `set -e` on non-WSL hosts - same class of bug as the
            # VBoxManage.exe guard clause above.
            is_wsl && ensure_wsl_nat_route "$existing" "$host_ip"
            return 0
        fi
        warn "Creating host-only adapter for ${subnet}.0/24..."
        local create_output created
        create_output=$("$vboxmanage" hostonlyif create 2>&1)
        created=$(echo "$create_output" | grep -oE "'[^']+'" | tr -d "'" | head -1)
        if [[ -z "$created" ]]; then
            warn "Could not parse the name of the newly created host-only adapter from:"
            warn "$create_output"
            warn "You may need to run 'VBoxManage hostonlyif ipconfig <name> --ip ${host_ip} --netmask 255.255.255.0' manually."
            return
        fi

        if is_wsl; then
            local result
            result=$(set_host_ip_windows "$created" "$host_ip")
            case "$result" in
                OK)
                    ok "Host-only adapter '$created' configured with IP $host_ip"
                    ensure_wsl_nat_route "$created" "$host_ip"
                    ;;
                CONFLICT:*)
                    warn "IP $host_ip is already assigned to another network adapter on this host (${result#CONFLICT:})."
                    warn "That adapter needs to give up $host_ip (or the lab's network config needs a different subnet)"
                    warn "before '$created' can use it - leaving it unconfigured for now."
                    ;;
                *)
                    warn "Could not confirm '$created' got IP $host_ip (result: ${result:-no output})."
                    warn "You may need to set it manually: run this in an elevated PowerShell:"
                    warn "  New-NetIPAddress -InterfaceDescription '$created' -IPAddress $host_ip -PrefixLength 24"
                    ;;
            esac
        else
            "$vboxmanage" hostonlyif ipconfig "$created" --ip "$host_ip" --netmask 255.255.255.0
            ok "Host-only adapter '$created' configured with IP $host_ip"
        fi
    }

    ensure_hostonly_adapter "192.168.136" "192.168.136.1"
    ensure_hostonly_adapter "10.10.10" "10.10.10.1"
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
    configure_wsl_env
    setup_hostonly_networks
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
    setup_hostonly_networks
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
    setup_hostonly_networks
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
