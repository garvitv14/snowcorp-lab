#!/usr/bin/env bash
# Wraps `vagrant up` with two layers of automatic recovery, both discovered
# empirically running this lab under WSL2:
#
#  1. Retry on known-transient WinRM/boot-timing error text ("not ready for
#     guest communication", "Timed out while waiting for the machine to
#     boot"). Before retrying, the specific machine that failed is
#     destroyed and reimported fresh from its box (see
#     recover_failed_machine below) — a plain reboot of the same VM
#     instance isn't enough here: on at least one box used in this lab
#     (stromweld/windows-11), a VM that hits this boot timeout once can be
#     left in a state where every subsequent boot of that *same disk*
#     fails again (observed: stuck in Windows' own "Automatic Repair"
#     loop, or the boot hanging identically even after a clean poweroff
#     and restart) — confirmed by testing power-cycling the exact same
#     instance repeatedly with no change, while a fresh reimport from the
#     box booted cleanly every time. A destroy+reimport discards that
#     instance's disk entirely and starts the next attempt from the same
#     pristine box image every other machine boots from, which is slower
#     per retry but has been reliable where a reboot alone was not. Any
#     provisioning progress already made on that specific machine before
#     the timeout is lost and redone — the machines that already
#     succeeded are untouched.
#
#  2. A stall watchdog for the WSL<->Windows interop hang: an in-flight
#     VBoxManage.exe/vmrun.exe call, invoked from WSL over the Windows
#     interop bridge, can occasionally hang forever even after the
#     Windows-side process has already exited — no error, no log output,
#     just silence. This is NOT the same as a legitimate long-silent step
#     (e.g. extracting a multi-GB box can produce zero log output for 20+
#     minutes while genuinely working) — so the watchdog only acts when
#     BOTH the log has stopped growing AND total CPU time across the whole
#     vagrant process tree has stopped advancing, for the same window. A
#     busy child (bsdtar, curl, VBoxManage actually working) keeps CPU time
#     climbing even with no log output; a truly stalled interop call does
#     not.
#
# Usage: vagrant_up_resilient.sh [extra args passed through to `vagrant up`]
#
# The stall watchdog (layer 2) only applies on WSL2, where the interop hang
# is possible in the first place — on native Linux/macOS there's no
# VBoxManage.exe/vmrun.exe interop bridge to hang, and this stays out of the
# way with just the plain error-text retry (layer 1), avoiding any risk from
# `ps` output differing on BSD/macOS.

set -uo pipefail

# ws01/ws02 (Windows 11) cannot go through `vagrant up`'s own box-import path
# on the VirtualBox provider: `VBoxManage import` from an OVF does not carry
# over the box's .nvram file (EFI boot variables) — it silently generates a
# fresh, different one with no valid Windows Boot Manager entry, which boots
# into an infinite "Install Windows — the computer restarted unexpectedly"
# crash-loop. See scripts/import_windows11.sh for the full explanation and
# the fix (copy the box's real .nvram file in before the VM's first boot).
# `vagrant up` has no hook between "VBoxManage import finishes" and "VM
# boots" to inject that fix, so ws01/ws02 are brought up by that script
# directly instead, and only THEN registered into vagrant's own
# .vagrant/machines/ tracking so every other vagrant command still works
# normally against them afterwards. This only applies to the (default)
# VirtualBox provider — the VMware path imports differently and isn't
# affected by this bug.
if ! printf '%s\n' "$@" | grep -qi vmware; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    WINDOWS11_MACHINES="ws01 ws02"

    requested_machines=()
    for arg in "$@"; do
        case "$arg" in
            -*) ;;  # flag, not a machine name
            *) requested_machines+=("$arg") ;;
        esac
    done

    # No machine name in the args means "bring everything up" — that
    # includes ws01/ws02. Otherwise only handle them here if explicitly
    # named, so `vagrant up dc01` etc. still behaves exactly as before.
    target_win11=()
    if [ "${#requested_machines[@]}" -eq 0 ]; then
        target_win11=($WINDOWS11_MACHINES)
    else
        for m in "${requested_machines[@]}"; do
            for w in $WINDOWS11_MACHINES; do
                [ "$m" = "$w" ] && target_win11+=("$m")
            done
        done
    fi

    for m in "${target_win11[@]:-}"; do
        [ -z "$m" ] && continue
        echo "=== $m: bringing up via scripts/import_windows11.sh (bypasses vagrant's own box-import path — see comment above) ==="
        "$SCRIPT_DIR/import_windows11.sh" "$m"
    done

    # Remove ws01/ws02 from the args `vagrant up` itself receives below —
    # they're already handled. If no machine was named at all (full "up"),
    # explicitly list the non-Windows-11 machines instead of leaving the
    # args empty, so vagrant doesn't also try (and fail) to import ws01/ws02.
    if [ "${#requested_machines[@]}" -eq 0 ]; then
        set -- dc01 dc02 ubu01
    else
        new_args=()
        for arg in "$@"; do
            skip=0
            for w in $WINDOWS11_MACHINES; do
                [ "$arg" = "$w" ] && skip=1
            done
            [ "$skip" -eq 0 ] && new_args+=("$arg")
        done
        # If every machine named was ws01/ws02, there's nothing left for
        # `vagrant up` to do — exit now instead of falling through to a
        # bare `vagrant up` with no machine args, which would mean "bring
        # up everything" instead of "nothing more to do".
        if [ "${#new_args[@]}" -eq 0 ]; then
            exit 0
        fi
        set -- "${new_args[@]}"
    fi
fi

MAX_ATTEMPTS="${VAGRANT_UP_MAX_ATTEMPTS:-5}"
RETRY_DELAY="${VAGRANT_UP_RETRY_DELAY:-15}"
STALL_CHECK_INTERVAL="${VAGRANT_UP_STALL_CHECK_INTERVAL:-60}"
STALL_THRESHOLD="${VAGRANT_UP_STALL_THRESHOLD:-300}"

IS_WSL=0
grep -qi microsoft /proc/version 2>/dev/null && IS_WSL=1

# vagrant's error output names the machine that failed (e.g. "==> ws01:
# Waiting for machine to boot..." followed by the timeout error). Destroy
# just that one machine — see the comment at the top of this file for why
# a reboot of the same instance isn't sufficient — and let the next loop
# iteration's `vagrant up` reimport it fresh from the box. Other machines
# that already succeeded are untouched (`vagrant destroy` only affects the
# named machine).
recover_failed_machine() {
    local logf="$1" name
    name=$(grep -oE '^==> [a-z0-9_-]+:' "$logf" | tail -1 | sed -E 's/^==> ([a-z0-9_-]+):$/\1/')
    [ -z "$name" ] && return 0
    echo "=== $name hit a boot timeout — destroying it so the retry reimports it fresh from the box instead of rebooting the same (possibly now-unbootable) disk ===" >> "$logf"
    vagrant destroy -f "$name" >> "$logf" 2>&1
}

# Sum CPU seconds (utime+stime, from ps' TIME field converted to seconds)
# across a process and all its descendants. Pure `ps` — no extra packages
# (e.g. psmisc/pstree) required, since this needs to work on a stock install.
tree_cpu_seconds() {
    local root="$1" total=0 pid time_str h m s
    local all_pids frontier next child ppid_pid
    all_pids=$(ps -eo pid,ppid --no-headers 2>/dev/null)
    frontier="$root"
    local collected="$root"
    while [ -n "$frontier" ]; do
        next=""
        for pid in $frontier; do
            while read -r child ppid_pid; do
                if [ "$ppid_pid" = "$pid" ]; then
                    case " $collected " in
                        *" $child "*) ;;
                        *) collected="$collected $child"; next="$next $child" ;;
                    esac
                fi
            done <<< "$all_pids"
        done
        frontier="$next"
    done
    for pid in $collected; do
        time_str=$(ps -o time= -p "$pid" 2>/dev/null | tr -d ' ')
        [ -z "$time_str" ] && continue
        IFS=: read -r h m s <<< "$(printf '%s' "$time_str" | awk -F: '{if (NF==2) print "0:"$0; else print}')"
        total=$((total + 10#${h:-0} * 3600 + 10#${m:-0} * 60 + 10#${s:-0}))
    done
    echo "$total"
}

attempt=0
while true; do
    attempt=$((attempt + 1))
    logf="$(mktemp)"

    vagrant up "$@" > "$logf" 2>&1 &
    vpid=$!

    # Live-tail so the user still sees real-time output.
    tail -f -n +1 "$logf" &
    tailpid=$!

    stalled=0

    if [ "$IS_WSL" -eq 1 ]; then
        last_size=0
        last_cpu=-1
        stall_since=0

        while kill -0 "$vpid" 2>/dev/null; do
            sleep "$STALL_CHECK_INTERVAL"
            kill -0 "$vpid" 2>/dev/null || break

            cur_size=$(wc -c < "$logf" 2>/dev/null || echo 0)
            cur_cpu=$(tree_cpu_seconds "$vpid")
            now=$(date +%s)

            if [ "$cur_size" != "$last_size" ] || [ "$cur_cpu" != "$last_cpu" ]; then
                last_size="$cur_size"
                last_cpu="$cur_cpu"
                stall_since=0
                continue
            fi

            if [ "$stall_since" -eq 0 ]; then
                stall_since="$now"
                continue
            fi

            if [ $((now - stall_since)) -ge "$STALL_THRESHOLD" ]; then
                echo "" >> "$logf"
                echo "=== No log output AND no CPU progress across the vagrant process tree for ${STALL_THRESHOLD}s — this matches the known WSL<->Windows interop hang. Killing and retrying. ===" >> "$logf"
                pkill -9 -P "$vpid" 2>/dev/null
                kill -9 "$vpid" 2>/dev/null
                stalled=1
                break
            fi
        done
    fi

    wait "$vpid" 2>/dev/null
    status=$?
    kill "$tailpid" 2>/dev/null
    wait "$tailpid" 2>/dev/null

    [ "$stalled" -eq 1 ] && status=1

    if [ "$status" -eq 0 ]; then
        rm -f "$logf"
        exit 0
    fi

    if [ "$attempt" -ge "$MAX_ATTEMPTS" ]; then
        echo ""
        echo "vagrant up failed after $MAX_ATTEMPTS attempts. See README Troubleshooting."
        rm -f "$logf"
        exit "$status"
    fi

    # Note: vagrant wraps this message across two lines ("...that is not\n
    # ready for guest communication...") — match the part guaranteed to be
    # on one line, not the full phrase spanning the line break.
    if [ "$stalled" -eq 1 ] || grep -qE "ready for guest communication|Timed out while waiting for the machine to boot" "$logf"; then
        recover_failed_machine "$logf"
        echo ""
        echo "=== Retrying vagrant up (attempt $((attempt + 1))/$MAX_ATTEMPTS) in ${RETRY_DELAY}s ==="
        rm -f "$logf"
        sleep "$RETRY_DELAY"
        continue
    fi

    rm -f "$logf"
    exit "$status"
done
