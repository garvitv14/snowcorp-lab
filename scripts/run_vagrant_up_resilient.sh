#!/usr/bin/env bash
# Wraps `vagrant up` with automatic recovery from a real, recurring bug
# confirmed on this stack (2026-07-26): the vagrant/ruby process's own WinRM
# boot-readiness check can get permanently stuck with a socket in SYN-SENT
# state - the guest is genuinely reachable the whole time (confirmed: a
# fresh raw `bash /dev/tcp` connect or a real PowerShell Invoke-Command from
# the Windows host both succeed instantly while vagrant's own connection
# attempt sits in SYN-SENT indefinitely, retrying with new source ports that
# also get stuck). This isn't specific to one VM - it recurred independently
# for both dc01 and ws01 in the same run. Killing just the vagrant process
# and re-running `vagrant up` immediately succeeds (a fresh ruby process
# gets a fresh socket) - vagrant itself skips any VM already provisioned or
# already past boot-wait, so restarting never redoes finished work.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

log() { echo "[$(date +%H:%M:%S)] [vagrant-watchdog] $*"; }

STUCK_THRESHOLD_SECS=90
CHECK_INTERVAL_SECS=15
NET_BROKEN_THRESHOLD_SECS=60

# Distinct from the SYN-SENT bug above: confirmed separately (2026-07-26)
# that WSL2's mirrored networking can totally drop every interface mirroring
# a VirtualBox host-only adapter mid-run (matches known, still-open upstream
# reports - e.g. microsoft/WSL#13454, #40752 - not a bug in this repo). No
# amount of retrying `vagrant up` fixes this - the guests are fine, WSL just
# has no route to them - so blind retries just silently retry-and-skip
# forever while Vagrant's own provisioner-tracking marks a host "already
# provisioned" even though its ansible run never actually completed,
# masking the failure as a false "success". install.sh's own pre-flight
# check (see ensure_wsl_mirrored_interface) only runs once, before this
# script starts, so it can't catch a failure that develops later - hence
# this separate, ongoing check.
wsl_networks_reachable() {
    ip route get 192.168.136.1 >/dev/null 2>&1 || ip route get 10.10.10.1 >/dev/null 2>&1
}

for attempt in $(seq 1 20); do
    log "vagrant up attempt $attempt"
    vagrant up 2>&1 &
    vagrant_shell_pid=$!

    # Confirmed by direct testing: ruby itself DOES keep retrying while
    # stuck (each retry uses a fresh local port - visible as the SYN-SENT
    # peer changing between checks), but every retry gets stuck too. So
    # tracking "is it the SAME port stuck" never reaches the threshold -
    # each retry looks "new" and resets the counter, even though the
    # process has functionally been unable to complete any connection for
    # much longer. Track "is *any* ruby socket stuck in SYN-SENT" instead,
    # regardless of which port - that's the condition that actually matters.
    stuck_since=0
    net_broken_since=0
    while kill -0 "$vagrant_shell_pid" 2>/dev/null; do
        sleep "$CHECK_INTERVAL_SECS"

        if ! wsl_networks_reachable; then
            net_broken_since=$((net_broken_since + CHECK_INTERVAL_SECS))

            if [[ $net_broken_since -ge $NET_BROKEN_THRESHOLD_SECS ]]; then
                log "WSL2 has lost ALL routes to both VirtualBox host-only networks (192.168.136.0/24 and 10.10.10.0/24) for ${net_broken_since}s - this is not fixable by retrying vagrant/ansible, since the guests themselves are fine and WSL just can't reach them."
                log "Known Windows/WSL2 platform bug (matches microsoft/WSL#13454, #40752 - currently unresolved upstream), not a bug in this repo. Confirmed remediation: reboot Windows, then re-run 'make up' (already-created VMs and completed provisioning steps will be skipped automatically)."
                pkill -9 -f "vagrant-2\.[0-9.]+/bin/vagrant" 2>/dev/null
                pkill -9 -f "bin/vagrant up" 2>/dev/null
                exit 2
            fi
        else
            net_broken_since=0
        fi

        if ss -tnp 2>/dev/null | grep -q 'SYN-SENT.*ruby'; then
            stuck_since=$((stuck_since + CHECK_INTERVAL_SECS))

            if [[ $stuck_since -ge $STUCK_THRESHOLD_SECS ]]; then
                log "vagrant's WinRM connection has been stuck in SYN-SENT for ${stuck_since}s (retrying with new ports but never completing) - killing vagrant process to force a fresh connection"
                pkill -9 -f "vagrant-2\.[0-9.]+/bin/vagrant" 2>/dev/null
                pkill -9 -f "bin/vagrant up" 2>/dev/null
                break
            fi
        else
            stuck_since=0
        fi
    done

    wait "$vagrant_shell_pid" 2>/dev/null
    rc=$?

    if [[ $rc -eq 0 ]]; then
        log "vagrant up SUCCEEDED"
        exit 0
    fi

    log "vagrant up exited (code $rc) - retrying (vagrant will skip anything already done)"
    sleep 5
done

log "vagrant up did not succeed after 20 attempts - giving up"
exit 1
