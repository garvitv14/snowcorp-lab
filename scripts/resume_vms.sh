#!/usr/bin/env bash
# Resumes a lab that was fully powered off, starting VMs directly via
# VBoxManage instead of `vagrant up`.
#
# Why this exists: `vagrant up` waits for its own WinRM readiness check,
# which for the VirtualBox provider connects through the NAT-forwarded port
# on 127.0.0.1. Under WSL2 with `networkingMode=mirrored` (needed so WSL can
# see the lab's host-only adapters at all), that specific loopback path can
# become unreachable from inside WSL even though the guest is fully booted
# and reachable on its real host-only IP the whole time - `vagrant up` then
# hangs at "Waiting for machine to boot" for no real reason (confirmed by
# checking the guest directly: WinRM running, console at the lock screen,
# CPU active - only the NAT-loopback path from WSL was broken).
#
# This script sidesteps that path entirely: it starts each VM with
# VBoxManage (bypassing Vagrant's own boot-wait), then verifies real
# readiness over the host-only network - the same path Ansible already uses
# successfully. Vagrant recognizes machines VBoxManage started as "running"
# and `vagrant provision` does not repeat the broken readiness check for an
# already-running machine, so this composes cleanly with the normal
# `make provision` step afterwards.
#
# Use this when `vagrant up` hangs after a poweroff. For first-time/fresh
# VM creation, keep using `make up` / `vagrant up` as normal.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

is_wsl() { grep -qi microsoft /proc/version 2>/dev/null; }

if is_wsl; then
    VBOXMANAGE="VBoxManage.exe"
else
    VBOXMANAGE="VBoxManage"
fi

ok()   { echo -e "\033[0;32m[+]\033[0m $*"; }
warn() { echo -e "\033[1;33m[!]\033[0m $*"; }
err()  { echo -e "\033[0;31m[x]\033[0m $*"; exit 1; }

# name -> VM name, and (for Windows hosts) the host-only IP Ansible already
# reaches them on; ubu01 is checked over SSH instead of WinRM.
VMS=(
    "dc01:SnowCorp-DC01:winrm:192.168.136.10"
    "ws01:SnowCorp-WS01:winrm:192.168.136.11"
    "dc02:SnowCorp-DC02:winrm:10.10.10.20"
    "ws02:SnowCorp-WS02:winrm:10.10.10.21"
    "ubu01:SnowCorp-UBU01:ssh:10.10.10.31"
)

if is_wsl; then
    ok "Re-syncing WSL host-only interfaces (mirrored-mode interface names/IPs are not stable across WSL restarts)..."
    if [[ -x "install.sh" || -f "install.sh" ]]; then
        bash install.sh >/tmp/resume_vms_install.log 2>&1 || warn "install.sh reported an issue - see /tmp/resume_vms_install.log"
    fi
fi

ok "Starting any VM that isn't already running..."
running=$("$VBOXMANAGE" list runningvms 2>/dev/null || true)
for entry in "${VMS[@]}"; do
    IFS=':' read -r name vmname proto ip <<< "$entry"
    if echo "$running" | grep -q "\"$vmname\""; then
        ok "$vmname already running"
    else
        ok "Starting $vmname..."
        "$VBOXMANAGE" startvm "$vmname" --type headless
    fi
done

ok "Waiting for real readiness on each host (this can take a few minutes for Windows guests)..."
TIMEOUT_SECS=600
for entry in "${VMS[@]}"; do
    IFS=':' read -r name vmname proto ip <<< "$entry"
    port=5985
    [[ "$proto" == "ssh" ]] && port=22

    elapsed=0
    until timeout 3 bash -c "cat < /dev/null > /dev/tcp/$ip/$port" 2>/dev/null; do
        if (( elapsed >= TIMEOUT_SECS )); then
            warn "$name ($ip:$port) still not reachable after ${TIMEOUT_SECS}s - check it manually"
            break
        fi
        sleep 5
        elapsed=$((elapsed + 5))
    done
    if (( elapsed < TIMEOUT_SECS )); then
        ok "$name ($ip:$port) is reachable"
    fi
done

echo ""
ok "Done. Run 'make provision' (or 'vagrant provision ubu01') to run the Ansible playbook."
