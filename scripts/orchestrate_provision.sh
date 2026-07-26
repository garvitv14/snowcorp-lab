#!/usr/bin/env bash
# Self-healing, per-host orchestrated provisioning for the SnowCorp lab.
#
# Why this exists: a single `ansible-playbook site.yml` run treats the whole
# 5-host pipeline as one unit - if DC02 (say) hits a transient WinRM blip or
# a genuinely stuck guest three hosts in, the only recourse with a plain
# playbook run is to restart the entire play from DC01. On this lab's
# Windows guests, transient blips and genuinely-stuck-guest states are both
# common enough that restarting from the beginning every time is why this
# lab sat unprovisioned for weeks.
#
# What this script does instead, one host at a time, in order
# (dc01, dc02, ws01, ws02, ubu01):
#   - skips a host entirely if it already shows its own completion marker
#     (a written flag file, or - for WS01/WS02, which don't write one -
#     confirmed domain membership) - so a run interrupted partway through
#     resumes at the actual point of failure, never redoing finished hosts.
#   - runs only that host's own role (--tags=role --limit=<host>)
#   - on failure, checks whether the guest is genuinely stuck (a
#     `VBoxManage guestcontrol` session fails to even start - this is
#     VirtualBox's own internal channel, independent of the network, so it's
#     unaffected by any WinRM/network flakiness) vs. just a transient WinRM
#     blip
#   - if stuck: resets the VM (non-destructive, reboots the guest only,
#     confirmed not to lose already-completed provisioning work) and waits
#     for it to become genuinely responsive (a real ansible win_ping/ping,
#     not just a port check) before retrying
#   - if transient: waits 5 minutes before retrying, rather than hammering a
#     server that's still catching up
#   - never restarts from the beginning - always resumes at the host that
#     actually failed
# Once all 5 hosts succeed, runs the cross-domain plays (routing, forest
# trust, ACLs) in one final pass - also safe to re-run, since both are
# idempotent (routes/DNS forwarders no-op if already present, forest trust
# creation checks Get-ADTrust first).
#
# Usage: bash scripts/orchestrate_provision.sh
# (or: make orchestrate)
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

is_wsl() { grep -qi microsoft /proc/version 2>/dev/null; }
if is_wsl; then
    VBOX="VBoxManage.exe"
else
    VBOX="VBoxManage"
fi

declare -A VM_NAME=( [dc01]="SnowCorp-DC01" [dc02]="SnowCorp-DC02" [ws01]="SnowCorp-WS01" [ws02]="SnowCorp-WS02" )
declare -A HOST_IP=( [dc01]="192.168.136.10" [dc02]="10.10.10.20" [ws01]="192.168.136.11" [ws02]="10.10.10.21" [ubu01]="10.10.10.31" )
declare -A HOST_PORT=( [dc01]="5985" [dc02]="5985" [ws01]="5985" [ws02]="5985" [ubu01]="22" )

log() { echo "[$(date +%H:%M:%S)] $*"; }

# UBU01 speaks SSH, not WinRM - a bare TCP connect is the right check there.
# curl'ing an HTTP path against port 22 (confirmed by direct testing,
# 2026-07-27) always reports "not reachable" for ubu01 regardless of its
# real state, since SSH never returns anything curl recognizes as HTTP -
# wait_for_host()'s ansible-ping fallback masked this from actually
# blocking progress, but it made every ubu01 run print a false
# "not reachable yet" and wait needlessly.
check_reachable() {
  local host=$1
  if [[ "$host" == "ubu01" ]]; then
    timeout 8 bash -c "cat < /dev/null > /dev/tcp/${HOST_IP[$host]}/${HOST_PORT[$host]}" 2>/dev/null
  else
    curl -s -o /dev/null --max-time 8 "http://${HOST_IP[$host]}:${HOST_PORT[$host]}/wsman" 2>/dev/null
  fi
}

is_stuck() {
  # Only meaningful for Windows hosts (have a VM_NAME entry).
  local host=$1 vmname="${VM_NAME[$host]:-}"
  [[ -z "$vmname" ]] && return 1
  "$VBOX" guestcontrol "$vmname" run --exe "C:\\Windows\\System32\\cmd.exe" --username vagrant --password vagrant --timeout 8000 -- /c echo ok >/dev/null 2>&1
  [[ $? -ne 0 ]]
}

reset_vm() {
  local vmname="${VM_NAME[$1]}"
  log "resetting $vmname (non-destructive reboot)"
  "$VBOX" controlvm "$vmname" reset >/dev/null 2>&1
}

wait_for_host() {
  local host=$1
  for i in $(seq 1 30); do
    if [[ "$host" == "ubu01" ]]; then
      timeout 20 ansible "$host" -i ansible/inventory.yml -m ping >/dev/null 2>&1 && { log "$host responsive (attempt $i)"; return 0; }
    else
      timeout 20 ansible "$host" -i ansible/inventory.yml -m ansible.windows.win_ping >/dev/null 2>&1 && { log "$host responsive (attempt $i)"; return 0; }
    fi
    sleep 10
  done
  return 1
}

# Each host's own completion marker - checked BEFORE running its role, so an
# interrupted run resumes at the actual point of failure rather than redoing
# already-finished hosts. WS01/WS02 don't write a flag file, so domain
# membership (the actual point of their role) is used instead.
is_already_done() {
  local host=$1
  case "$host" in
    dc01|dc02)
      # Forward slashes, not \f\l... - a literal backslash-f in the path
      # gets misread as a form-feed escape by ansible's arg parsing.
      timeout 20 ansible "$host" -i ansible/inventory.yml -m ansible.windows.win_stat \
        -a "path=C:/Users/Administrator/Desktop/flag.txt" 2>/dev/null | grep -q '"exists": true'
      ;;
    ws01)
      timeout 20 ansible ws01 -i ansible/inventory.yml -m ansible.windows.win_shell \
        -a "(Get-CimInstance Win32_ComputerSystem).Domain" 2>/dev/null | grep -qi '^lab\.local'
      ;;
    ws02)
      timeout 20 ansible ws02 -i ansible/inventory.yml -m ansible.windows.win_shell \
        -a "(Get-CimInstance Win32_ComputerSystem).Domain" 2>/dev/null | grep -qi '^corp\.local'
      ;;
    ubu01)
      timeout 20 ansible ubu01 -i ansible/inventory.yml -m stat -a "path=/root/flag.txt" 2>/dev/null | grep -q '"exists": true'
      ;;
    *) return 1 ;;
  esac
}

for host in dc01 dc02 ws01 ws02 ubu01; do
  log "=================================================="
  log "=== $host ==="
  log "=================================================="

  if is_already_done "$host"; then
    log "$host already provisioned - skipping"
    continue
  fi

  attempt=0
  while true; do
    attempt=$((attempt+1))
    log "$host attempt $attempt"

    if ! check_reachable "$host"; then
      log "$host not reachable yet - waiting for it"
      wait_for_host "$host" || log "still not reachable, trying the run anyway"
    fi

    ansible-playbook --tags=role --limit="$host" --inventory-file=ansible/inventory.yml -v ansible/site.yml
    rc=$?

    if [[ $rc -eq 0 ]]; then
      log "$host SUCCEEDED"
      break
    fi

    log "$host failed (exit $rc)"

    if is_stuck "$host"; then
      log "$host is genuinely stuck (guest-control session failed) - resetting"
      reset_vm "$host"
      wait_for_host "$host" || log "$host still not responsive after reset - retrying anyway"
    else
      log "$host: transient failure, not stuck - waiting 5 minutes before retry"
      sleep 300
    fi
  done
done

log "=================================================="
log "=== All 5 hosts done - running cross-domain plays (routing, trust, ACLs) ==="
log "=================================================="
attempt=0
while true; do
  attempt=$((attempt+1))
  log "crossdomain attempt $attempt"
  ansible-playbook --tags=crossdomain --inventory-file=ansible/inventory.yml -v ansible/site.yml
  rc=$?
  if [[ $rc -eq 0 ]]; then
    log "crossdomain plays SUCCEEDED"
    break
  fi
  log "crossdomain plays failed (exit $rc) - waiting 2 minutes before retry"
  sleep 120
done

log "=================================================="
log "=== PROVISIONING COMPLETE ==="
log "=================================================="
