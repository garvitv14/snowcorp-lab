# Vagrant's own Windows guest network configuration (guest_network.rb,
# configure_static_interface) runs its `netsh interface ip set address
# ... static ...` command over WinRM with elevated: false (the
# communicator's default, never overridden for this call). netsh needs
# admin rights to change adapter IP config, so on guests where that
# command actually requires elevation to succeed, it silently fails and
# the adapter is left on DHCP/APIPA (169.254.x.x) - confirmed by direct
# testing on this exact box. This script re-applies the intended static
# IPs itself, as a provisioner that Vagrant always runs elevated by
# default, to correct whatever the built-in step failed to do.
#
# Usage: pass each intended private-network IP in adapter order (i.e. the
# order the "private_network" lines appear in the Vagrantfile for this
# machine - NAT's "Ethernet" adapter is never included here).
param(
    [Parameter(Mandatory = $true)]
    [string[]]$IPAddresses,
    [int]$PrefixLength = 24
)

$ErrorActionPreference = "Stop"

$adapters = Get-NetAdapter | Where-Object { $_.Name -match '^Ethernet( \d+)?$' } | Sort-Object {
    if ($_.Name -eq "Ethernet") { 1 } else { [int]($_.Name -replace '\D','') }
}

# First adapter ("Ethernet") is always VirtualBox's NAT adapter; the
# private-network ones follow in the order they're defined.
$privateAdapters = $adapters | Select-Object -Skip 1

# Force every non-NAT adapter to Private - confirmed required (2026-07-26)
# via `winrm quickconfig`'s own error message: its firewall exception
# refuses to work if *any* interface on the machine is Public, and a fresh
# private_network adapter with no gateway can never be auto-classified by
# Windows (no signal for Network Location Awareness to identify it), so it
# stays "Unidentified network" = Public forever unless forced. Applied
# here too (not just in the fresh-boot bridge script) as defense-in-depth,
# in case this provisioner ever re-runs after something reverts it.
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
        Write-Warning "No adapter found for private network #$($i+1) (expected IP $targetIp)"
        continue
    }

    $existing = Get-NetIPAddress -InterfaceIndex $adapter.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue
    if ($existing.IPAddress -contains $targetIp) {
        Write-Output "$($adapter.Name) already has $targetIp"
        continue
    }

    Write-Output "$($adapter.Name) has $($existing.IPAddress -join ', ') instead of $targetIp - correcting"
    $existing | Remove-NetIPAddress -Confirm:$false -ErrorAction SilentlyContinue
    # Disable DHCP on this adapter before adding the static IP - confirmed
    # by direct testing (2026-07-26) that skipping this step lets the
    # IP keep reverting back to APIPA: New-NetIPAddress alone adds an
    # address but doesn't stop the adapter's DHCP client, which keeps
    # negotiating in the background on this isolated host-only network
    # (no DHCP server present) and falls back to APIPA on failure,
    # overriding whatever static IP was manually set.
    Set-NetIPInterface -InterfaceIndex $adapter.ifIndex -Dhcp Disabled -ErrorAction SilentlyContinue
    New-NetIPAddress -InterfaceIndex $adapter.ifIndex -IPAddress $targetIp -PrefixLength $PrefixLength | Out-Null
    Write-Output "$($adapter.Name) set to $targetIp (DHCP disabled)"
}
