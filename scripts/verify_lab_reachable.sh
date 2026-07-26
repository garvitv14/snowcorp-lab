#!/usr/bin/env bash
# Runs at the END of `make up`, after vagrant itself reports success.
#
# Why this exists: confirmed directly (2026-07-26) that Vagrant's own
# "success" is not trustworthy here. Vagrant tracks "provisioned" as a
# one-time flag per machine - if a provisioner (including the ansible run)
# fails once and the wrapper retries `vagrant up`, Vagrant sees the
# machine already has SOME prior provisioning history and skips it on the
# retry, even though the actual configuration (e.g. the ansible playbook)
# never genuinely completed. `vagrant up` (and this whole pipeline) can
# report exit 0 while a guest's real static IP is still wrong and nothing
# actually got configured. This script is the one thing that actually
# checks ground truth instead of trusting any exit code or log line.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

log() { echo "[$(date +%H:%M:%S)] [verify_lab] $*"; }

declare -A WINRM_TARGETS=(
    [DC01]="192.168.136.10"
    [WS01]="192.168.136.11"
    [DC02]="10.10.10.20"
    [WS02]="10.10.10.21"
)
SSH_TARGET_NAME="UBU01"
SSH_TARGET_IP="10.10.10.31"

failures=()

for name in "${!WINRM_TARGETS[@]}"; do
    ip="${WINRM_TARGETS[$name]}"
    if timeout 5 bash -c "cat < /dev/null > /dev/tcp/$ip/5985" 2>/dev/null; then
        log "$name: OK - reachable at $ip:5985"
    else
        log "$name: FAILED - $ip:5985 is not reachable (static IP likely never actually applied, despite vagrant reporting success)"
        failures+=("$name")
    fi
done

if timeout 5 bash -c "cat < /dev/null > /dev/tcp/$SSH_TARGET_IP/22" 2>/dev/null; then
    log "$SSH_TARGET_NAME: OK - reachable at $SSH_TARGET_IP:22"
else
    log "$SSH_TARGET_NAME: FAILED - $SSH_TARGET_IP:22 is not reachable"
    failures+=("$SSH_TARGET_NAME")
fi

if [[ ${#failures[@]} -gt 0 ]]; then
    log "VERIFICATION FAILED for: ${failures[*]}"
    log "This means 'make up' completed, but the lab is NOT actually working - do not trust the success exit code above this line."
    log "Re-run 'make up' again (it will skip whatever genuinely succeeded) or investigate the specific machine(s) listed above."
    exit 1
fi

log "All 5 machines verified genuinely reachable - the lab is actually up, not just reported as such."
exit 0
