# lab.local side — Create bidirectional forest trust with corp.local
# Runs after dc02 is already a DC for corp.local
#
# Real root cause and fix (2026-07-26): the original script called
# .CreateLocalSideOfTrust() on the object returned by Get-ADForest, but that
# PowerShell-module object type has no such method (confirmed via a genuine
# MethodNotFound error on first run, unmodified). The real, documented API
# is System.DirectoryServices.ActiveDirectory.Forest's
# CreateLocalSideOfTrustRelationship() method - a different underlying .NET
# type than what Get-ADForest returns, and note the "Relationship" suffix
# the original code was also missing.
#
# This also needs to run as the actual Administrator account, not `vagrant`
# (who ansible/WinRM connects as): vagrant is only in BUILTIN\Administrators
# on this domain, not Enterprise Admins, and forest trust creation requires
# Enterprise Admins specifically - confirmed by a genuine "Access is denied"
# .NET exception as vagrant vs success as Administrator, both using the
# identical API call. (netdom.exe was tried first and abandoned - it
# produced confusing, inconsistent "parameter is incorrect"/"access denied"
# errors across ~20 isolated tests that never converged on a working
# combination; this .NET API worked on the very first genuinely-elevated
# attempt.)
#
# Each side is created independently with a shared trust password (like a
# DSRM password) rather than domain admin credential objects for the other
# side - both sides must use the identical trustPassword value.

$existing = Get-ADTrust -Filter {Target -eq "corp.local"}
if ($existing) {
    Write-Host "[+] Trust already exists, skipping creation"
} else {
    $context = New-Object System.DirectoryServices.ActiveDirectory.DirectoryContext(
        "Forest", "lab.local", "LAB\Administrator", "Adminpass2026x"
    )
    $labForest = [System.DirectoryServices.ActiveDirectory.Forest]::GetForest($context)
    $labForest.CreateLocalSideOfTrustRelationship("corp.local", "Bidirectional", "TrustSecret2026x")
}

# Verify
$trust = Get-ADTrust -Filter {Target -eq "corp.local"}
Write-Host "[+] Trust direction: $($trust.Direction)"
Write-Host "[+] Trust type: $($trust.TrustType)"
Write-Host "[+] SID Filtering (ForestTransitive): $($trust.ForestTransitive)"
