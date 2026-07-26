#!/usr/bin/env bash
# Runs INSIDE WSL (invoked by prepare_fresh_boot.sh, same as
# fix_fresh_boot_guestcontrol.ps1 for the Windows guests), but does its
# actual work via `ssh.exe` - the WINDOWS-side OpenSSH client - not WSL's
# own ssh.
#
# Why: under WSL2's default NAT networking mode (mirrored mode was dropped
# repo-wide for stability reasons - see install.sh), a guest's
# NAT-forwarded SSH port (127.0.0.1:<port>) is reachable from the Windows
# host but NOT from inside WSL itself (WSL has its own private loopback in
# NAT mode) - confirmed by direct testing (2026-07-26). Vagrant itself
# runs inside WSL, so its own SSH connection attempts hit this same wall.
#
# This breaks the same class of first-boot deadlock as
# fix_fresh_boot_guestcontrol.ps1 does for Windows: the guest's real, routable
# private-network IP (which WSL CAN reach, via the explicit routes
# install.sh sets up) is normally applied by Vagrant's own built-in
# network-configuration step - but that step needs a working SSH
# connection to run, which (see above) doesn't yet exist. Applying the IP
# here, over a connection that goes through the Windows host instead,
# breaks the deadlock.
#
# Uses Vagrant's own insecure keypair - a well-known, publicly-documented
# default shipped with every Vagrant install (not a secret), the same
# credential Vagrant itself would use for its first connection.
set -uo pipefail

NAT_PORT="$1"
TARGET_IP="$2"
PREFIX_LENGTH="${3:-24}"

is_wsl() { grep -qi microsoft /proc/version 2>/dev/null; }
if ! is_wsl; then
    exit 0
fi

insecure_key="$HOME/.vagrant.d/insecure_private_key"
if [[ ! -f "$insecure_key" ]]; then
    echo "fix_fresh_boot_ssh_ip: no insecure_private_key found at $insecure_key" >&2
    exit 1
fi

# ssh.exe (the Windows OpenSSH client) enforces private-key file
# permissions itself - a key accessed via its \\wsl.localhost UNC path
# carries WSL's own permission bits, which ssh.exe won't accept as safe -
# so stage a fresh copy on a real Windows-native path and lock it down
# there each time (idempotent; no persisted secret needed since this key
# is public).
staged_key="/tmp/vagrant_insecure_key_bridge"
cp "$insecure_key" "$staged_key"
staged_key_win="$(wslpath -w "$staged_key")"
powershell.exe -NoProfile -Command "
    icacls '$staged_key_win' /inheritance:r | Out-Null
    icacls '$staged_key_win' /grant:r (\"\$env:USERNAME\`:R\") | Out-Null
" >/dev/null 2>&1

ssh_opts=(-i "$staged_key_win" -p "$NAT_PORT" -o StrictHostKeyChecking=no -o UserKnownHostsFile=NUL -o ConnectTimeout=8 -o BatchMode=yes)

# VirtualBox assigns guest NICs to fixed, predictable PCI slots (NIC1 ->
# slot 3, NIC2 -> slot 8, ...), which systemd's predictable-naming scheme
# turns into stable interface names (enp0s3, enp0s8, ...) - this holds
# for any standard VirtualBox Linux guest, not just this one box.
# enp0s3 is always the NAT adapter (never the target here); enp0s8 is the
# first additional (private-network) adapter, which is what every guest
# in this repo actually needs configured.
guest_iface="enp0s8"

existing=$(ssh.exe "${ssh_opts[@]}" vagrant@127.0.0.1 "ip -4 addr show dev $guest_iface 2>/dev/null" 2>/dev/null)
if echo "$existing" | grep -q "inet ${TARGET_IP}/"; then
    echo "$guest_iface already has $TARGET_IP"
    exit 0
fi

ssh.exe "${ssh_opts[@]}" vagrant@127.0.0.1 \
    "sudo ip addr add '${TARGET_IP}/${PREFIX_LENGTH}' dev $guest_iface && sudo ip link set $guest_iface up" 2>&1
