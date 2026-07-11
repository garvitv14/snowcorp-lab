# lab.local — Create users, groups, and service accounts

Import-Module ActiveDirectory

$domain = "lab.local"
$dc     = "DC=lab,DC=local"

# ── Organisational Units ────────────────────────────────────────────────────
foreach ($ou in @("Corp Users","Service Accounts","Workstations")) {
    New-ADOrganizationalUnit -Name $ou -Path $dc -ProtectedFromAccidentalDeletion $false `
        -ErrorAction SilentlyContinue
}

# ── Regular domain users ────────────────────────────────────────────────────
$users = @(
    @{ Name="john.smith";  Pass="Summer2026!"; Desc="IT Support";       OU="Corp Users" },
    @{ Name="jane.doe";    Pass="Flower2026!"; Desc="HR Manager";        OU="Corp Users" },
    @{ Name="alice.jones"; Pass="Alice@2026!"; Desc="Finance Analyst";   OU="Corp Users" }
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

# ── Service account ─────────────────────────────────────────────────────────
$svcPass = ConvertTo-SecureString "Deploy@2026!" -AsPlainText -Force
New-ADUser -Name "svc_deploy" `
           -SamAccountName "svc_deploy" `
           -UserPrincipalName "svc_deploy@$domain" `
           -AccountPassword $svcPass `
           -Description "Deployment Service Account" `
           -Path "OU=Service Accounts,$dc" `
           -Enabled $true `
           -PasswordNeverExpires $true `
           -ErrorAction SilentlyContinue

Set-ADUser -Identity "svc_deploy" -ServicePrincipalNames @{Add="HTTP/deploy.lab.local"}

# ── jane.doe account settings ───────────────────────────────────────────────
Set-ADAccountControl -Identity "jane.doe" -DoesNotRequirePreAuth $true

# ── ADCS access ─────────────────────────────────────────────────────────────
Add-ADGroupMember -Identity "Cert Publishers" -Members "svc_deploy" -ErrorAction SilentlyContinue
