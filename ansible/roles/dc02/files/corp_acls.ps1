# corp.local — Set ACL on WS02$ after WS02 has joined the domain
# Phase 4: WS02 must already be a domain member when this runs

Import-Module ActiveDirectory

$sarahSID = (Get-ADUser -Identity "sarah.jones").SID
$ws02DN   = (Get-ADComputer -Identity "WS02").DistinguishedName
$ws02Obj  = [ADSI]"LDAP://$ws02DN"

$aceGW = New-Object System.DirectoryServices.ActiveDirectoryAccessRule(
    $sarahSID,
    [System.DirectoryServices.ActiveDirectoryRights]"GenericWrite",
    [System.Security.AccessControl.AccessControlType]"Allow"
)
$ws02Obj.ObjectSecurity.AddAccessRule($aceGW)
$ws02Obj.CommitChanges()

Write-Host "[+] sarah.jones -> GenericWrite -> WS02$"

# Runs locally on dc02 rather than via Invoke-Command from ws02 — a
# cross-host WinRM call to a bare IP (10.10.10.20) fails by default
# ("WinRM client cannot process the request... TrustedHosts") since
# WS02 has no reason to trust that endpoint without extra config: this
# machine IS that endpoint, so no remoting is needed at all.
Set-ADComputer -Identity "WS02" -TrustedForDelegation $true
Write-Host "[+] WS02 TrustedForDelegation set"
