# lab.local side — Create bidirectional forest trust with corp.local
# Runs after dc02 is already a DC for corp.local

$labCred  = New-Object System.Management.Automation.PSCredential(
    "LAB\Administrator",
    (ConvertTo-SecureString "Admin@2026!" -AsPlainText -Force)
)
$corpCred = New-Object System.Management.Automation.PSCredential(
    "CORP\Administrator",
    (ConvertTo-SecureString "Admin@2026!" -AsPlainText -Force)
)

$labForest  = Get-ADForest -Identity "lab.local"
$corpForest = Get-ADForest -Identity "corp.local" -Credential $corpCred

# Create forest-level bidirectional trust
$labForest.CreateLocalSideOfTrust("corp.local", "Bidirectional", $corpCred)
$corpForest.CreateLocalSideOfTrust("lab.local", "Bidirectional", $labCred)

# Verify
$trust = Get-ADTrust -Filter {Target -eq "corp.local"}
Write-Host "[+] Trust direction: $($trust.Direction)"
Write-Host "[+] Trust type: $($trust.TrustType)"
Write-Host "[+] SID Filtering (ForestTransitive): $($trust.ForestTransitive)"
