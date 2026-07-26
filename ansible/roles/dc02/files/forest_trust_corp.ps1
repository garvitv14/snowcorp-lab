# corp.local side — Create bidirectional forest trust with lab.local
# See roles/dc01/files/forest_trust.ps1 for the full root-cause writeup.
# CreateLocalSideOfTrustRelationship only creates the LOCAL side of the
# trust from whichever forest's context it's called against, so this needs
# its own call here on corp.local's own DC, using the same shared
# trustPassword as the lab.local side.

$existing = Get-ADTrust -Filter {Target -eq "lab.local"}
if ($existing) {
    Write-Host "[+] Trust already exists, skipping creation"
} else {
    $context = New-Object System.DirectoryServices.ActiveDirectory.DirectoryContext(
        "Forest", "corp.local", "CORP\Administrator", "Adminpass2026x"
    )
    $corpForest = [System.DirectoryServices.ActiveDirectory.Forest]::GetForest($context)
    $corpForest.CreateLocalSideOfTrustRelationship("lab.local", "Bidirectional", "TrustSecret2026x")
}

# Verify
$trust = Get-ADTrust -Filter {Target -eq "lab.local"}
Write-Host "[+] Trust direction: $($trust.Direction)"
Write-Host "[+] Trust type: $($trust.TrustType)"
Write-Host "[+] SID Filtering (ForestTransitive): $($trust.ForestTransitive)"
