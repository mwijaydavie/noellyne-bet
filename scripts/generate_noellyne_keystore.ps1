<#
.SYNOPSIS
    Generates a permanent Android release keystore (.jks / PKCS12) for Noellyne
    strictly OUTSIDE the git repository, prints its SHA-1 / SHA-256 fingerprints,
    and copies the Base64 string to your clipboard for GitHub Actions Secrets.

.NOTES
    Never commit the generated .jks file or passwords to Git.
    Back up C:\Users\<you>\Documents\Noellyne-Keystore\noellyne-release.jks
    and your password in a private password manager / private Google Drive folder.
#>

$ErrorActionPreference = 'Stop'

$aliasName = 'noellyne'
$dname = 'CN=David Erick Mwijage, OU=Engineering, O=Altraware Technology Ltd, L=Dar es Salaam, ST=Dar es Salaam, C=TZ'
$outDir = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'Noellyne-Keystore'
$ksPath = Join-Path $outDir 'noellyne-release.jks'
$fpPath = Join-Path $outDir 'fingerprints.txt'

function Find-Keytool {
    $cmd = Get-Command keytool -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }

    $roots = @(
        'C:\Program Files\Eclipse Adoptium',
        'C:\Program Files\Java',
        'C:\Program Files\Microsoft',
        'C:\Program Files\Android\Android Studio\jbr'
    )
    foreach ($root in $roots) {
        if (Test-Path $root) {
            $found = Get-ChildItem -Path $root -Filter 'keytool.exe' -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($found) { return $found.FullName }
        }
    }
    throw "keytool.exe was not found. Install Temurin JDK 21 (winget install EclipseAdoptium.Temurin.21.JDK) and re-run."
}

function ConvertFrom-SecureStringPlain([Security.SecureString]$sec) {
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec)
    try {
        return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
    } finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    }
}

Write-Host ""
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "  Noellyne Permanent Android Release Keystore Setup" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "Keystore location (outside git): $ksPath"
Write-Host ""

$keytool = Find-Keytool
Write-Host "[OK] Using keytool: $keytool" -ForegroundColor Green

New-Item -ItemType Directory -Force -Path $outDir | Out-Null

if (Test-Path $ksPath) {
    Write-Host ""
    Write-Host "[SAFEGUARD] A permanent keystore ALREADY exists at:" -ForegroundColor Yellow
    Write-Host "  $ksPath" -ForegroundColor Yellow
    Write-Host "Refusing to overwrite it (replacing a release key breaks in-place updates!)." -ForegroundColor Yellow
    Write-Host ""
    $copyChoice = Read-Host "Copy Base64 of this EXISTING keystore to clipboard? (Y/n)"
    if ($copyChoice -eq '' -or $copyChoice -match '^[Yy]') {
        $b64Existing = [Convert]::ToBase64String([IO.File]::ReadAllBytes($ksPath))
        Set-Clipboard -Value $b64Existing
        Write-Host "[OK] Base64 copied to clipboard ($($b64Existing.Length) chars). Paste into GitHub Secret: NOELLYNE_KEYSTORE_BASE64" -ForegroundColor Green
    }
    exit 0
}

Write-Host "Choose a STRONG password for your permanent Noellyne release keystore." -ForegroundColor White
Write-Host "(Tip: Use letters + numbers, min 10 chars, avoid spaces. Save it in a password manager!)" -ForegroundColor Gray
Write-Host ""

$sec1 = Read-Host "Enter keystore password (hidden)" -AsSecureString
$sec2 = Read-Host "Confirm keystore password (hidden)" -AsSecureString
$pass1 = ConvertFrom-SecureStringPlain $sec1
$pass2 = ConvertFrom-SecureStringPlain $sec2

if ($pass1 -ne $pass2) {
    throw "Passwords do not match. Re-run the script and try again."
}
if ($pass1.Length -lt 8) {
    throw "Password must be at least 8 characters long."
}
if ($pass1.Trim() -ne $pass1) {
    throw "Password must not start or end with spaces."
}

$env:NOELLYNE_TMP_KS_PASS = $pass1
try {
    Write-Host ""
    Write-Host "[1/3] Generating RSA-2048 PKCS12 release keystore (valid 10,000 days)..." -ForegroundColor Cyan
    & $keytool -genkeypair `
        -storetype PKCS12 `
        -keystore $ksPath `
        -alias $aliasName `
        -keyalg RSA `
        -keysize 2048 `
        -validity 10000 `
        -storepass:env NOELLYNE_TMP_KS_PASS `
        -keypass:env NOELLYNE_TMP_KS_PASS `
        -dname $dname `
        -noprompt

    if ($LASTEXITCODE -ne 0 -or -not (Test-Path $ksPath)) {
        throw "keytool failed to generate keystore (exit code $LASTEXITCODE)."
    }

    Write-Host "[2/3] Reading public certificate fingerprints (SHA-1 & SHA-256)..." -ForegroundColor Cyan
    $listOut = & $keytool -list -v `
        -keystore $ksPath `
        -alias $aliasName `
        -storepass:env NOELLYNE_TMP_KS_PASS

    if ($LASTEXITCODE -ne 0) {
        throw "keytool verification failed (exit code $LASTEXITCODE)."
    }

    $fpLines = $listOut | Select-String -Pattern 'Alias name:|Owner:|Valid from:|SHA1:|SHA256:' | ForEach-Object { $_.Line.Trim() }
    @(
        "Noellyne Permanent Release Keystore (Public Certificate Info Only - NO PASSWORD STORED)",
        "File: $ksPath",
        "Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz')",
        "------------------------------------------------------------"
    ) + $fpLines | Set-Content -Path $fpPath -Encoding UTF8

    Write-Host ""
    foreach ($line in $fpLines) {
        Write-Host "  $line" -ForegroundColor Gray
    }
} finally {
    Remove-Item Env:NOELLYNE_TMP_KS_PASS -ErrorAction SilentlyContinue
    $pass1 = $null
    $pass2 = $null
}

Write-Host ""
Write-Host "[3/3] Encoding keystore to Base64 and copying to clipboard..." -ForegroundColor Cyan
$b64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes($ksPath))
Set-Clipboard -Value $b64

Write-Host ""
Write-Host "==========================================================" -ForegroundColor Green
Write-Host "  SUCCESS! Permanent Keystore Ready!" -ForegroundColor Green
Write-Host "==========================================================" -ForegroundColor Green
Write-Host "Keystore file : $ksPath"
Write-Host "Fingerprints  : $fpPath"
Write-Host "Clipboard     : NOELLYNE_KEYSTORE_BASE64 ($($b64.Length) chars) COPIED!" -ForegroundColor Green
Write-Host ""
Write-Host "NEXT: Add these 4 Repository Secrets on GitHub:" -ForegroundColor Yellow
Write-Host "  https://github.com/mwijaydavie/noellyne-bet/settings/secrets/actions" -ForegroundColor Cyan
Write-Host ""
Write-Host "  1. NOELLYNE_KEYSTORE_BASE64   -> Press Ctrl+V (already in your clipboard!)"
Write-Host "  2. NOELLYNE_KEYSTORE_PASSWORD -> The password you just typed"
Write-Host "  3. NOELLYNE_KEY_ALIAS         -> $aliasName"
Write-Host "  4. NOELLYNE_KEY_PASSWORD      -> The exact same password you just typed"
Write-Host ""
Write-Host "BACKUP WARNING:" -ForegroundColor Red
Write-Host "  Copy $ksPath to a PRIVATE Google Drive / password manager." -ForegroundColor Red
Write-Host "  Never commit it to Git and never lose it!" -ForegroundColor Red
Write-Host ""
