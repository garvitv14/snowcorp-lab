#!/usr/bin/env bash
# Manually imports and boots ws01/ws02 (Windows 11) instead of letting
# `vagrant up` do it, because `VBoxManage import` from an OVF does not
# correctly carry over the box's .nvram file (EFI boot variables) — it
# silently generates a fresh, different one. `vagrant up` hits this exact
# same bug internally since it calls VBoxManage import the same way.
# Symptom without this fix: the VM boots into "Install Windows — the
# computer restarted unexpectedly" in an infinite crash-loop, because EFI
# has no valid boot entry for the Windows Boot Manager. The fix is simple
# once you know it exists: copy the box's own .nvram file over the
# freshly-imported VM's auto-generated one, before ever booting it.
#
# This script does the whole VM creation by hand (import, network,
# VRDE-off, port-forwarding, nvram fix, boot) and then registers the
# result with Vagrant's own .vagrant/machines/ tracking, so `vagrant
# status`/`vagrant provision`/etc. all still work normally afterwards —
# only the initial import+boot bypasses vagrant.
#
# Usage: scripts/import_windows11.sh ws01|ws02

set -euo pipefail

MACHINE="${1:?Usage: $0 ws01|ws02}"
BOX_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$BOX_DIR"

VBOX="/c/Program Files/Oracle/VirtualBox/VBoxManage.exe"
BOX_OVF_DIR="/c/Users/Admin/.vagrant.d/boxes/gusztavvargadr-VAGRANTSLASH-windows-11/2601.0.0/amd64/virtualbox"
BOX_OVF="$BOX_OVF_DIR/box.ovf"
BOX_NVRAM=$(find "$BOX_OVF_DIR" -maxdepth 1 -iname '*.nvram' | head -1)

case "$MACHINE" in
  ws01)
    VMNAME="SnowCorp-WS01"
    WINRM_PORT=15986
    HOSTONLY_ADAPTER="VirtualBox Host-Only Ethernet Adapter #4"   # 192.168.136.x (lab network — shared with dc01)
    RDP_PORT=3389
    ;;
  ws02)
    VMNAME="SnowCorp-WS02"
    WINRM_PORT=15988
    HOSTONLY_ADAPTER="VirtualBox Host-Only Ethernet Adapter #9"   # 10.10.10.x (corp network — shared with dc02/ubu01)
    RDP_PORT=53389
    ;;
  *)
    echo "Unknown machine '$MACHINE' — expected ws01 or ws02" >&2
    exit 1
    ;;
esac

if [ ! -f "$BOX_OVF" ]; then
  echo "Box not found at $BOX_OVF — run: vagrant box add gusztavvargadr/windows-11 --provider virtualbox" >&2
  exit 1
fi
if [ -z "$BOX_NVRAM" ]; then
  echo "No .nvram file found alongside $BOX_OVF — box layout may have changed" >&2
  exit 1
fi

# Idempotent: if the VM already exists, is running, and WinRM already
# answers, there's nothing to do — don't destroy a working machine just
# because this script (or `make up`) ran again. Only fall through to a
# full destroy+reimport if it's missing, stopped, or unreachable.
if "$VBOX" showvminfo "$VMNAME" >/dev/null 2>&1; then
  state=$("$VBOX" showvminfo "$VMNAME" --machinereadable | grep '^VMState=' | cut -d'"' -f2)
  if [ "$state" = "running" ] && timeout 15 ansible "$MACHINE" -i ansible/inventory.yml -m ansible.windows.win_ping >/dev/null 2>&1; then
    echo "=== $MACHINE: $VMNAME already running and WinRM-reachable — nothing to do ==="
    exit 0
  fi
  echo "=== $MACHINE: $VMNAME exists but is not in a known-good state (VMState=$state) — reimporting ==="
fi

echo "=== $MACHINE: removing any existing $VMNAME ==="
vagrant destroy -f "$MACHINE" >/dev/null 2>&1 || true
"$VBOX" controlvm "$VMNAME" poweroff >/dev/null 2>&1 || true
sleep 2
"$VBOX" unregistervm "$VMNAME" --delete >/dev/null 2>&1 || true

echo "=== $MACHINE: importing from box (memory pre-set, before first boot) ==="
# BOX_OVF is a POSIX path (this WSL instance mounts C:\ at /c, not the
# default /mnt/c — see install.sh's WIN_C_ROOT detection). VBoxManage.exe is
# a native Windows binary and does not understand POSIX paths passed as
# arguments (only the executable-lookup path gets interop translation) — a
# raw "/c/Users/..." argument was previously mangled into "C:\c\Users\...",
# which VBoxManage couldn't find, causing the OVF import to fail and this
# script's own not-in-a-known-good-state recovery path to then destroy the
# existing VM on every retry. Convert to a native Windows path explicitly.
BOX_OVF_WIN="$(wslpath -w "$BOX_OVF")"
"$VBOX" import "$BOX_OVF_WIN" --vsys 0 --vmname "$VMNAME" --memory 3121 --cpus 2

echo "=== $MACHINE: configuring network/VRDE (pre-boot) ==="
"$VBOX" modifyvm "$VMNAME" --vrde off
"$VBOX" modifyvm "$VMNAME" --nic1 nat
"$VBOX" modifyvm "$VMNAME" --nic2 hostonly --hostonlyadapter2 "$HOSTONLY_ADAPTER"
"$VBOX" modifyvm "$VMNAME" --natpf1 "winrm-ansible,tcp,127.0.0.1,${WINRM_PORT},,5985"
"$VBOX" modifyvm "$VMNAME" --natpf1 "rdp,tcp,127.0.0.1,${RDP_PORT},,3389"

echo "=== $MACHINE: fixing EFI NVRAM (must happen before first boot) ==="
VM_DIR="/c/Users/Admin/VirtualBox VMs/$VMNAME"
VM_NVRAM="$VM_DIR/$VMNAME.nvram"
if [ ! -d "$VM_DIR" ]; then
  echo "Expected VM directory not found: $VM_DIR" >&2
  exit 1
fi
cp "$BOX_NVRAM" "$VM_NVRAM"
if ! diff -q "$BOX_NVRAM" "$VM_NVRAM" >/dev/null; then
  echo "NVRAM copy verification failed" >&2
  exit 1
fi

echo "=== $MACHINE: booting ==="
"$VBOX" startvm "$VMNAME" --type headless

echo "=== $MACHINE: registering with vagrant's machine tracking ==="
UUID=$("$VBOX" showvminfo "$VMNAME" --machinereadable | grep '^UUID=' | cut -d'"' -f2)
mkdir -p ".vagrant/machines/$MACHINE/virtualbox"
printf '%s' "$UUID" > ".vagrant/machines/$MACHINE/virtualbox/id"
printf '%s' "$BOX_DIR" > ".vagrant/machines/$MACHINE/virtualbox/vagrant_cwd"
printf '1000' > ".vagrant/machines/$MACHINE/virtualbox/creator_uid"
printf '{"name":"gusztavvargadr/windows-11","version":"2601.0.0","provider":"virtualbox","directory":"boxes/gusztavvargadr-VAGRANTSLASH-windows-11/2601.0.0/amd64/virtualbox"}' \
  > ".vagrant/machines/$MACHINE/virtualbox/box_meta"
python3 -c "import uuid; print(uuid.uuid4().hex)" > ".vagrant/machines/$MACHINE/virtualbox/index_uuid"

echo "=== $MACHINE: waiting for WinRM ==="
for i in $(seq 1 20); do
  if timeout 15 ansible "$MACHINE" -i ansible/inventory.yml -m ansible.windows.win_ping >/dev/null 2>&1; then
    echo "=== $MACHINE: WinRM is up ==="
    exit 0
  fi
  sleep 15
done

echo "$MACHINE booted but WinRM did not become reachable within 5 minutes — check host RAM headroom (VirtualBox VMs need real free RAM, not just configured allocation) and VM state manually." >&2
exit 1
