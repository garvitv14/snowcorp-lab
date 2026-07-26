# Runs INSIDE the guest (copied in and executed via `VBoxManage guestcontrol`,
# never over the network) to break the first-boot deadlock for Windows guests.
#
# Why this exists, and why it replaced the earlier WinRM-based bridge script:
# confirmed by extensive direct testing (2026-07-26) that this host's
# VirtualBox NAT engine completes a bare TCP handshake to a guest's
# NAT-forwarded port but never actually delivers real application data across
# it for WinRM/RDP-style traffic - so a fix script that itself depends on a
# WinRM session THROUGH that same NAT path can never run in the first place.
# `guestcontrol` sidesteps this completely: it talks to the guest over
# VirtualBox's own Guest Additions channel, which needs no network path at
# all, so it works even while the guest's real static IP is still unset and
# its NAT path is broken.
#
# Also confirmed the same day: even once the static IP is applied, WinRM
# still refuses external connections until the guest's network profile
# category is Private/Domain - a fresh `private_network` adapter with no
# gateway can never be auto-classified by Windows (Network Location
# Awareness has no signal to identify a gateway-less network), so it stays
# "Unidentified network" = Public forever unless forced. This script forces
# it, for every non-NAT adapter, every time - cheap and idempotent.
param(
    [int]$PrefixLength = 24,
    # PowerShell's `-File script.ps1 -IPAddresses val1 val2` does NOT
    # reliably bind multiple bare values into a [string[]] parameter -
    # confirmed by direct testing (2026-07-26) across multiple parameter
    # orderings that the extra value(s) leak into whatever other parameter
    # exists instead of extending the array, regardless of declaration
    # order. Comma-joining into a single string sidesteps CLI array binding
    # entirely - there's exactly one value to bind, so there's nothing left
    # to mis-split.
    [Parameter(Mandatory = $true)][string]$IPAddressList
)
$IPAddresses = $IPAddressList -split ','

# guestcontrol logs "vagrant" on with a genuinely UAC-filtered token -
# confirmed by direct testing (2026-07-26) that this is NOT special-cased
# for guest-control sessions the way it was assumed to be: whoami /groups
# shows "BUILTIN\Administrators ... Group used for deny only" here, exactly
# like a normal non-elevated interactive logon, and LocalAccountTokenFilterPolicy
# (which only affects *network*-type logons) doesn't help since this is an
# interactive-type logon. Set-NetIPInterface/New-NetIPAddress both hard-fail
# with "Access is denied" under this token, no ErrorAction suppresses it.
#
# Fix: self-elevate via a real UAC prompt. There's no way to silently
# escalate this token (scheduled-task-as-SYSTEM registration and direct
# registry writes to UAC policy keys were both tested and also hit Access
# Denied under this same token - only a genuine elevation consent works).
# The prompt itself is answered automatically, with no real person
# involved: prepare_fresh_boot.sh runs a parallel keystroke loop sending
# Alt+Y (the UAC "Yes" accelerator) to this VM's console for the whole
# fix-application window. Confirmed by direct testing that Enter alone is
# NOT enough - this dialog's default-focused button is "No", not "Yes" (the
# opposite of the "Network discovery" dialog below), so Enter alone
# declines it silently.
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    $argList = @('-NoProfile', '-File', "`"$PSCommandPath`"", '-PrefixLength', $PrefixLength, '-IPAddressList', $IPAddressList)
    Start-Process powershell.exe -Verb RunAs -Wait -WindowStyle Hidden -ArgumentList $argList
    exit
}

# Suppresses the interactive "Network discovery" prompt that a fresh
# private_network adapter triggers. Previously applied via a WinRM session
# (which may never have actually taken effect, given everything else that
# turned out to be broken about that path) - registry writes via
# guestcontrol are confirmed reliable, unlike netsh/service-control calls
# through the same channel (those hit UAC token filtering for this
# non-built-in admin account; plain registry writes and PowerShell
# networking cmdlets don't).
New-Item -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Network\NewNetworkWindowOff" -Force -ErrorAction SilentlyContinue | Out-Null

# Sort by PCI bus/device/function, NOT by Windows' "Ethernet N" display
# name - confirmed by direct testing (2026-07-26) that name-based ordering
# is unreliable after a VM reset: Windows can re-enumerate and rename
# adapters in a different order than their actual VirtualBox NIC slot,
# silently swapping which private network gets which IP. PCI
# bus/device/function directly reflects VirtualBox's own fixed NIC1/NIC2/NIC3
# slot assignment (NIC1 is always the NAT adapter, defined first in the
# Vagrantfile/VBoxManage config) and is immune to OS-level renaming.
$adaptersWithSlot = Get-NetAdapter | Where-Object { $_.Name -match '^Ethernet( \d+)?$' } | ForEach-Object {
    $hwInfo = $_ | Get-NetAdapterHardwareInfo -ErrorAction SilentlyContinue
    [PSCustomObject]@{
        Adapter = $_
        Bus     = if ($hwInfo) { $hwInfo.Bus } else { 0 }
        Device  = if ($hwInfo) { $hwInfo.Device } else { 0 }
        Function = if ($hwInfo) { $hwInfo.Function } else { 0 }
    }
}
$sortedAdapters = $adaptersWithSlot | Sort-Object Bus, Device, Function | ForEach-Object { $_.Adapter }
$privateAdapters = $sortedAdapters | Select-Object -Skip 1

# Force every non-NAT adapter to Private - not just the ones we're about to
# address IP, since WinRM's firewall exception refuses to work if *any*
# interface on the machine is Public (confirmed via `winrm quickconfig`'s
# own explicit error message).
foreach ($adapter in $privateAdapters) {
    try {
        Set-NetConnectionProfile -InterfaceAlias $adapter.Name -NetworkCategory Private -ErrorAction Stop
        Write-Output "$($adapter.Name): network category set to Private"
    } catch {
        Write-Output "$($adapter.Name): could not set network category - $($_.Exception.Message)"
    }
}

for ($i = 0; $i -lt $IPAddresses.Count; $i++) {
    $targetIp = $IPAddresses[$i]
    $adapter = $privateAdapters[$i]
    if (-not $adapter) {
        Write-Output "No adapter found for private network #$($i+1) (expected IP $targetIp)"
        continue
    }
    $existing = Get-NetIPAddress -InterfaceIndex $adapter.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue
    if ($existing.IPAddress -contains $targetIp) {
        Write-Output "$($adapter.Name) already has $targetIp"
        continue
    }
    $existing | Remove-NetIPAddress -Confirm:$false -ErrorAction SilentlyContinue
    # Disable DHCP before adding the static IP - without this, the adapter's
    # DHCP client keeps negotiating in the background on this isolated
    # host-only network (no DHCP server present) and falls back to APIPA on
    # failure, silently reverting the static IP (confirmed by direct
    # testing).
    Set-NetIPInterface -InterfaceIndex $adapter.ifIndex -Dhcp Disabled -ErrorAction SilentlyContinue
    New-NetIPAddress -InterfaceIndex $adapter.ifIndex -IPAddress $targetIp -PrefixLength $PrefixLength -ErrorAction Stop | Out-Null
    Write-Output "$($adapter.Name) set to $targetIp (DHCP disabled)"
}
