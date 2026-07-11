# corp.local — Create users, GMSA, and configure permissions
# Phase 1: runs when DC02 is first promoted (WS02 has not joined yet)

Import-Module ActiveDirectory

$domain = "corp.local"
$dc     = "DC=corp,DC=local"

# ── Organisational Units ────────────────────────────────────────────────────
foreach ($ou in @("Corp Users","Service Accounts","Workstations")) {
    New-ADOrganizationalUnit -Name $ou -Path $dc `
        -ProtectedFromAccidentalDeletion $false -ErrorAction SilentlyContinue
}

# ── Users ───────────────────────────────────────────────────────────────────
$users = @(
    @{ Name="corpuser";     Pass="Corp@2026!";   Desc="General Corp User";    OU="Corp Users" },
    @{ Name="sarah.jones";  Pass="Sarah@2026!";  Desc="IT Administrator";     OU="Corp Users" },
    @{ Name="svc_deploy";   Pass="Deploy@2026!"; Desc="Cross-domain svc acct";OU="Service Accounts" },
    @{ Name="bob.miller";   Pass="Bob@2026!";    Desc="Finance";              OU="Corp Users" }
)

foreach ($u in $users) {
    $secPass = ConvertTo-SecureString $u.Pass -AsPlainText -Force
    New-ADUser -Name $u.Name `
               -SamAccountName $u.Name `
               -UserPrincipalName "$($u.Name)@$domain" `
               -AccountPassword $secPass `
               -Description $u.Desc `
               -Path "OU=$($u.OU),$dc" `
               -Enabled $true `
               -PasswordNeverExpires $true `
               -ErrorAction SilentlyContinue
}

# ── GMSA — svc_corp_gmsa$ ───────────────────────────────────────────────────
New-ADServiceAccount -Name "svc_corp_gmsa" `
    -DNSHostName "svc_corp_gmsa.corp.local" `
    -PrincipalsAllowedToRetrieveManagedPassword "corpuser" `
    -ErrorAction SilentlyContinue

Write-Host "[+] GMSA svc_corp_gmsa created"

# ── ACL: corpuser has GenericAll on sarah.jones ─────────────────────────────
$corpuserSID = (Get-ADUser -Identity "corpuser").SID
$sarahDN     = (Get-ADUser -Identity "sarah.jones").DistinguishedName
$sarahObj    = [ADSI]"LDAP://$sarahDN"

$ace = New-Object System.DirectoryServices.ActiveDirectoryAccessRule(
    $corpuserSID,
    [System.DirectoryServices.ActiveDirectoryRights]"GenericAll",
    [System.Security.AccessControl.AccessControlType]"Allow"
)
$sarahObj.ObjectSecurity.AddAccessRule($ace)
$sarahObj.CommitChanges()

Write-Host "[+] corpuser -> GenericAll -> sarah.jones"

# ── svc_deploy SPN in corp.local ───────────────────────────────────────────
Set-ADUser -Identity "svc_deploy" `
           -ServicePrincipalNames @{Add="HTTP/deploy.corp.local"} `
           -ErrorAction SilentlyContinue

Write-Host "[+] svc_deploy SPN set in corp.local"
