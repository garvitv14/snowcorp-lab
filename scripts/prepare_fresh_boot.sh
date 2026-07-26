#!/usr/bin/env bash
# Runs ALONGSIDE a fresh `vagrant up` (launched by `make up` - see Makefile)
# to break a real deadlock in this box's first-boot sequence, for every
# Windows guest:
#
# Vagrant's own WinRM boot-readiness check is pointed at each Windows guest's
# static host-only IP (see Vagrantfile's `winrm.host` settings) instead of
# the default NAT-forwarded 127.0.0.1 port. That static IP is normally
# applied by a *provisioner* (EnsurePrivateNetworkIPs.ps1), which Vagrant
# only runs *after* its own boot-readiness check succeeds - so on a
# genuinely fresh VM (still on APIPA, 169.254.x.x), the check waits forever
# for an IP that nothing will ever set.
#
# This script breaks that deadlock using `VBoxManage guestcontrol` - VirtualBox's
# own Guest Additions channel, which needs no network path to the guest at
# all. This replaced an earlier WinRM-over-NAT-based bridge script after
# extensive direct testing (2026-07-26) found this host's VirtualBox NAT
# engine completes a bare TCP handshake to a guest's NAT-forwarded port but
# never actually delivers real application data across it for WinRM/RDP-style
# traffic - so a fix mechanism that itself depended on a WinRM session
# through that same NAT path could never run in the first place, no matter
# how long you waited. guestcontrol sidesteps this completely.
#
# scripts/fix_fresh_boot_guestcontrol.ps1 (copied into the guest and run via
# guestcontrol) does two things every VM needs: forces every non-NAT
# adapter's network category to Private (confirmed required - WinRM's
# firewall exception refuses to work if *any* interface is Public, and a
# fresh private_network adapter with no gateway can never be
# auto-classified by Windows, so it stays "Unidentified network" = Public
# forever unless forced), then applies the static IP.
#
# Safe to run against already-provisioned VMs too - it's a no-op if the
# static IP and network category are already correct.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

is_wsl() { grep -qi microsoft /proc/version 2>/dev/null; }
if is_wsl; then
    VBOX="VBoxManage.exe"
else
    VBOX="VBoxManage"
fi

log() { echo "[$(date +%H:%M:%S)] [prepare_fresh_boot] $*"; }

declare -A VM_IPS=(
    [SnowCorp-DC01]="192.168.136.10"
    [SnowCorp-WS01]="192.168.136.11,10.10.10.11"
    [SnowCorp-DC02]="10.10.10.20"
    [SnowCorp-WS02]="10.10.10.21"
)

# UBU01 (Linux/SSH) hits the same class of first-boot deadlock as the
# Windows guests, but via a different mechanism - see
# scripts/fix_fresh_boot_ssh_ip.sh for the full reasoning. Kept as its own
# map since it needs a different NAT-port lookup (ssh, not winrm) and a
# different fix script (SSH via ssh.exe, not guestcontrol - Linux guest
# additions don't expose the same guestcontrol PowerShell path, and SSH
# over NAT is confirmed working on this host unlike WinRM/RDP over NAT).
declare -A VM_IPS_SSH=(
    [SnowCorp-UBU01]="10.10.10.31"
)

get_ssh_port() {
    local vmname=$1
    "$VBOX" showvminfo "$vmname" --machinereadable 2>/dev/null \
        | grep -o '"ssh,tcp,[^,]*,[0-9]*,' \
        | grep -o '[0-9]*,$' \
        | tr -d ','
}

fix_one_vm() {
    local vmname=$1 ips=$2
    # Vagrant creates VMs one at a time in Vagrantfile order, and a Windows
    # guest's own box-import+boot+provision cycle can take 15-20+ minutes -
    # a VM later in the order may genuinely not exist yet for a long while.
    # 120 minutes covers even a slow run through all the VMs before this one.
    log "$vmname: waiting for VM to exist..."
    local vm_found=false
    for i in $(seq 1 720); do
        if "$VBOX" showvminfo "$vmname" >/dev/null 2>&1; then
            vm_found=true
            break
        fi
        sleep 10
    done
    if [[ "$vm_found" == false ]]; then
        log "$vmname: never got created within 120 minutes - giving up"
        return 1
    fi

    local fix_script="$(pwd)/scripts/fix_fresh_boot_guestcontrol.ps1"
    local fix_script_win="$fix_script"
    is_wsl && fix_script_win=$(wslpath -w "$fix_script")
    local guest_script_path="C:\\Users\\vagrant\\fix_fresh_boot_guestcontrol.ps1"

    local ip_arr=()
    IFS=',' read -ra ip_arr <<< "$ips"
    local primary_ip="${ip_arr[0]}"

    # Adding a private_network adapter makes Windows show an interactive
    # "Network discovery" prompt on first boot that blocks until answered -
    # confirmed happening well *after* the IP fix itself succeeded (not
    # tied to that timing at all), meaning the prompt can appear at almost
    # any point during the guest settling in after boot. NewNetworkWindowOff
    # (set by the guestcontrol script itself) should suppress this
    # permanently, but keep this keystroke loop as a defensive backstop in
    # case it doesn't - dismissing needs a real keystroke sent to the VM's
    # console (a host-side action), so send Enter repeatedly for a long,
    # generous window (20 minutes) independent of the fix loop's own
    # timing - harmless if no dialog is showing, effective whenever one
    # appears (Yes is the pre-highlighted default). Runs fully in the
    # background and is not waited on - it just dies out on its own.
    (
        for i in $(seq 1 150); do
            "$VBOX" controlvm "$vmname" keyboardputscancode 1c 9c >/dev/null 2>&1
            sleep 8
        done
    ) &
    disown

    # fix_fresh_boot_guestcontrol.ps1 now self-elevates via a genuine UAC
    # prompt (guestcontrol's "vagrant" session has a UAC-filtered token that
    # can't otherwise run Set-NetIPInterface/New-NetIPAddress - confirmed by
    # direct testing, 2026-07-26; no silent-elevation trick worked). That
    # prompt's default-focused button is "No", the opposite of the network
    # discovery dialog above - Enter alone would decline it - so send Alt+Y
    # (38=Alt down, 15=Y down, 95=Y up, b8=Alt up), the standard UAC "Yes"
    # accelerator.
    #
    # This must be a TIGHT burst fired immediately alongside each fix
    # attempt, not a loose independent timer - confirmed by direct testing
    # (2026-07-26) that a slow (~8s interval) background loop can lose the
    # race against the "Network discovery" dialog's own Enter-loop (which
    # declines this dialog if it lands first) often enough to matter, while
    # firing several Alt+Y presses ~500ms apart starting the moment the fix
    # attempt launches reliably wins it. send_alt_y_burst backgrounds itself
    # so the main loop below can proceed to wait on the fix attempt in
    # parallel - Start-Process -Wait inside the guest script blocks on the
    # real UAC prompt, so something has to be answering it concurrently.
    send_alt_y_burst() {
        local vmname=$1
        for i in $(seq 1 10); do
            "$VBOX" controlvm "$vmname" keyboardputscancode 38 15 95 b8 >/dev/null 2>&1
            sleep 0.5
        done
    }

    # Confirmed by direct testing: the guest's own "new network" profile
    # negotiation can revert the static IP back to APIPA *after* this fix
    # already applied it successfully once - a one-shot "fix it and stop"
    # isn't reliable. The guestcontrol script already no-ops harmlessly if
    # the IP/category are already correct, so keep reapplying periodically
    # for a long window instead of stopping at the first success.
    #
    # Verify against ground truth every single iteration (a real TCP
    # connect to the target IP's WinRM port - NOT the NAT-forwarded port,
    # since that path is confirmed broken on this host regardless of
    # anything this script does), not just whether the fix script itself
    # returned success.
    log "$vmname: applying static IP + network-category fix ($ips) via guestcontrol..."
    local ever_verified=false
    for i in $(seq 1 80); do
        "$VBOX" guestcontrol "$vmname" copyto "$fix_script_win" "$guest_script_path" --username vagrant --password vagrant >/dev/null 2>&1
        (
            "$VBOX" guestcontrol "$vmname" run --exe "C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe" --username vagrant --password vagrant --timeout 40000 -- powershell.exe -File "$guest_script_path" -IPAddressList "$ips" 2>&1
        ) &
        local fix_pid=$!
        send_alt_y_burst "$vmname"
        wait "$fix_pid"
        if timeout 5 bash -c "cat < /dev/null > /dev/tcp/$primary_ip/5985" 2>/dev/null; then
            log "$vmname: VERIFIED reachable at $primary_ip:5985"
            ever_verified=true
        else
            log "$vmname: NOT reachable at $primary_ip:5985 yet (attempt $i/80) - will keep retrying"
        fi
        sleep 15
    done
    [[ "$ever_verified" == true ]] && return 0
    log "$vmname: IP fix never actually verified reachable after 80 attempts - this machine is genuinely broken, not just slow"
    return 1
}

fix_one_vm_ssh() {
    local vmname=$1 target_ip=$2
    log "$vmname: waiting for VM to exist..."
    local vm_found=false
    for i in $(seq 1 720); do
        if "$VBOX" showvminfo "$vmname" >/dev/null 2>&1; then
            vm_found=true
            break
        fi
        sleep 10
    done
    if [[ "$vm_found" == false ]]; then
        log "$vmname: never got created within 120 minutes - giving up"
        return 1
    fi

    local port=""
    for i in $(seq 1 60); do
        port=$(get_ssh_port "$vmname")
        [[ -n "$port" ]] && break
        sleep 5
    done
    if [[ -z "$port" ]]; then
        log "$vmname: never got an SSH port forward - giving up"
        return 1
    fi
    log "$vmname: SSH forwarded to 127.0.0.1:$port"

    local fix_script="$(pwd)/scripts/fix_fresh_boot_ssh_ip.sh"

    # No "Network discovery" dialog for Linux guests (that's Windows-only)
    # and SSH over this same NAT path is confirmed working on this host
    # (unlike WinRM/RDP), so no NAT-bypass mechanism is needed here. Keep
    # reapplying periodically anyway for cheap insurance against anything
    # reverting it. Verify against ground truth every iteration (real TCP
    # connect) rather than trusting the script's own return code.
    log "$vmname: applying static IP fix ($target_ip) via SSH..."
    local ever_verified=false
    for i in $(seq 1 80); do
        bash "$fix_script" "$port" "$target_ip" 2>&1
        if timeout 5 bash -c "cat < /dev/null > /dev/tcp/$target_ip/22" 2>/dev/null; then
            log "$vmname: VERIFIED reachable at $target_ip:22"
            ever_verified=true
        else
            log "$vmname: NOT reachable at $target_ip:22 yet (attempt $i/80) - will keep retrying"
        fi
        sleep 15
    done
    [[ "$ever_verified" == true ]] && return 0
    log "$vmname: IP fix never actually verified reachable after 80 attempts - this machine is genuinely broken, not just slow"
    return 1
}

pids=()
for vmname in "${!VM_IPS[@]}"; do
    fix_one_vm "$vmname" "${VM_IPS[$vmname]}" &
    pids+=($!)
done
for vmname in "${!VM_IPS_SSH[@]}"; do
    fix_one_vm_ssh "$vmname" "${VM_IPS_SSH[$vmname]}" &
    pids+=($!)
done

for pid in "${pids[@]}"; do
    wait "$pid"
done

log "all VMs handled"
