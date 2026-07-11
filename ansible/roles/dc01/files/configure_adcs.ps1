# lab.local — Configure ADCS and certificate templates

Import-Module ADCSAdministration -ErrorAction SilentlyContinue

# ── Install/configure CA ────────────────────────────────────────────────────
Install-AdcsCertificationAuthority `
    -CAType EnterpriseRootCa `
    -CryptoProviderName "RSA#Microsoft Software Key Storage Provider" `
    -KeyLength 2048 `
    -HashAlgorithmName SHA256 `
    -CACommonName "SnowCorp-Lab-CA" `
    -CADistinguishedNameSuffix "DC=lab,DC=local" `
    -DatabaseDirectory "C:\Windows\system32\CertLog" `
    -LogDirectory "C:\Windows\system32\CertLog" `
    -ValidityPeriod Years `
    -ValidityPeriodUnits 5 `
    -Force

Start-Sleep -Seconds 15

# ── Create UserAuthentication certificate template ───────────────────────────
# We use certutil + LDAP to set CT_FLAG_ENROLLEE_SUPPLIES_SUBJECT

$configContext = (Get-ADRootDSE).configurationNamingContext
$templateDN    = "CN=UserAuthentication,CN=Certificate Templates,CN=Public Key Services,CN=Services,$configContext"

# Copy the built-in "User" template as our base
$adsiPath = "LDAP://CN=User,CN=Certificate Templates,CN=Public Key Services,CN=Services,$configContext"
$sourceObj = [ADSI]$adsiPath

$newTemplateDN = "CN=Certificate Templates,CN=Public Key Services,CN=Services,$configContext"
$parentObj     = [ADSI]"LDAP://$newTemplateDN"

$newObj = $parentObj.Create("pKICertificateTemplate", "CN=UserAuthentication")
$newObj.Put("distinguishedName",          "CN=UserAuthentication,$newTemplateDN")
$newObj.Put("displayName",                "UserAuthentication")
$newObj.Put("pKIDefaultKeySpec",          1)
$newObj.Put("pKIMaxIssuingDepth",         0)
$newObj.Put("msPKI-Cert-Template-OID",    "1.3.6.1.4.1.311.21.8.$(Get-Random -Min 1000000 -Max 9999999).1.$(Get-Random -Min 1000000 -Max 9999999)")
$newObj.Put("msPKI-Certificate-Name-Flag", 1)         # CT_FLAG_ENROLLEE_SUPPLIES_SUBJECT = 0x00000001
$newObj.Put("msPKI-Enrollment-Flag",       0)
$newObj.Put("msPKI-RA-Signature",          0)
$newObj.Put("msPKI-Template-Schema-Version", 2)
$newObj.Put("msPKI-Template-Minor-Revision", 2)
$newObj.Put("msPKI-Private-Key-Flag",      16)
$newObj.Put("revision",                    100)
$newObj.Put("pKIDefaultCSPs",              @("1,Microsoft Enhanced Cryptographic Provider v1.0"))
$newObj.Put("pKIKeyUsage",                 [byte[]](0xa0, 0x00))   # Digital Signature + Key Encipherment
$newObj.Put("pKIExpirationPeriod",         $sourceObj.pKIExpirationPeriod.Value)
$newObj.Put("pKIOverlapPeriod",            $sourceObj.pKIOverlapPeriod.Value)

# Extended key usages: Client Authentication + Smart Card Logon
$newObj.Put("pKIExtendedKeyUsage", @("1.3.6.1.5.5.7.3.2","1.3.6.1.4.1.311.20.2.2"))
$newObj.SetInfo()

Write-Host "[+] UserAuthentication template created"

# ── Set ACL: Domain Users can Enroll ───────────────────────────────────────
$templateObj = [ADSI]"LDAP://$templateDN"
$domainUsersSID = New-Object System.Security.Principal.SecurityIdentifier("S-1-5-21-*")
# Use the actual Domain Users SID
$domainSID = (Get-ADDomain).DomainSID.Value
$domainUsersSID = New-Object System.Security.Principal.SecurityIdentifier("$domainSID-513")

$ace = New-Object System.DirectoryServices.ActiveDirectoryAccessRule(
    $domainUsersSID,
    [System.DirectoryServices.ActiveDirectoryRights]"ExtendedRight",
    [System.Security.AccessControl.AccessControlType]"Allow",
    [guid]"0e10c968-78fb-11d2-90d4-00c04f79dc55"   # Certificate-Enrollment extended right
)
$templateObj.ObjectSecurity.AddAccessRule($ace)
$templateObj.CommitChanges()

Write-Host "[+] Domain Users granted Enroll on UserAuthentication template"

# ── Publish template to the CA ──────────────────────────────────────────────
Add-CATemplate -Name "UserAuthentication" -Force
Write-Host "[+] UserAuthentication template published to CA"
