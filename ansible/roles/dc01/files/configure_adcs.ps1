# lab.local — Configure ADCS and certificate templates

Import-Module ADCSAdministration -ErrorAction SilentlyContinue

# ── Install/configure CA (skip if already configured) ───────────────────────
# Install-AdcsCertificationAuthority isn't idempotent — re-running it against
# an already-configured CA throws. CertSvc only reaches "Running" once a CA
# is actually configured (the ADCS-Cert-Authority *feature* can be installed
# with the service still Stopped/unconfigured), so that's a reliable guard.
$certSvc = Get-Service CertSvc -ErrorAction SilentlyContinue
if (-not $certSvc -or $certSvc.Status -ne 'Running') {
    # -ErrorAction Stop is required here: Install-AdcsCertificationAuthority
    # writes failures to the non-terminating error stream by default, which
    # ansible.windows.win_powershell does NOT treat as a task failure (it
    # only fails on an uncaught terminating exception) — without this, a
    # genuinely failed CA install was silently falling through to the
    # certificate-template steps below, which then "succeeded" configuring
    # templates for a CA that was never actually installed. CertSvc stayed
    # Stopped while the whole task reported "changed: true".
    try {
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
            -Force -ErrorAction Stop
    } catch {
        throw "CA installation failed: $($_.Exception.Message)"
    }

    Start-Sleep -Seconds 15

    $certSvc = Get-Service CertSvc -ErrorAction SilentlyContinue
    if (-not $certSvc -or $certSvc.Status -ne 'Running') {
        throw "Install-AdcsCertificationAuthority reported success but CertSvc is not Running (status: $($certSvc.Status))"
    }
} else {
    Write-Host "[+] CertSvc already running — CA already configured, skipping install"
}

# ── Create UserAuthentication certificate template (skip if it exists) ──────
# We use certutil + LDAP to set CT_FLAG_ENROLLEE_SUPPLIES_SUBJECT

$configContext = (Get-ADRootDSE).configurationNamingContext
$templateDN    = "CN=UserAuthentication,CN=Certificate Templates,CN=Public Key Services,CN=Services,$configContext"

if ([ADSI]::Exists("LDAP://$templateDN")) {
    Write-Host "[+] UserAuthentication template already exists, skipping creation"
} else {
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
    # Required for a schema-version-2 template — without it, the CA
    # rejects issuance with CERTSRV_E_UNSUPPORTED_CERT_TYPE even though
    # the template object itself enumerates fine over LDAP (e.g. via
    # Certipy), since that's a schema-existence check, not the CA's own
    # issuance-compatibility check.
    $newObj.Put("msPKI-Minimal-Key-Size",      2048)
    $newObj.Put("revision",                    100)
    $newObj.Put("pKIDefaultCSPs",              @("1,Microsoft Enhanced Cryptographic Provider v1.0"))
    $newObj.Put("pKIKeyUsage",                 [byte[]](0xa0, 0x00))   # Digital Signature + Key Encipherment
    $newObj.Put("pKIExpirationPeriod",         $sourceObj.pKIExpirationPeriod.Value)
    $newObj.Put("pKIOverlapPeriod",            $sourceObj.pKIOverlapPeriod.Value)

    # Extended key usages: Client Authentication + Smart Card Logon
    $newObj.Put("pKIExtendedKeyUsage", @("1.3.6.1.5.5.7.3.2","1.3.6.1.4.1.311.20.2.2"))
    $newObj.SetInfo()

    Write-Host "[+] UserAuthentication template created"

    # ── Set ACL: Domain Users can Enroll ─────────────────────────────────────
    $templateObj = [ADSI]"LDAP://$templateDN"
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
}

# ── Publish template to the CA (Add-CATemplate errors if already published) ─
$published = certutil -CATemplates | Select-String -SimpleMatch "UserAuthentication"
if ($published) {
    Write-Host "[+] UserAuthentication template already published to CA, skipping"
} else {
    Add-CATemplate -Name "UserAuthentication" -Force
    Write-Host "[+] UserAuthentication template published to CA"
}
