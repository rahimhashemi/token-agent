# firefox-ca-install.ps1
# Installs BankMellat Root CA into all Firefox profiles on this machine.
# Called by NSIS installer after main install.

$CertPath = Join-Path $PSScriptRoot "..\bankmellat-ca.crt"
$CertName = "BankMellat Token Agent CA"

Write-Host "Installing CA into Firefox profiles..."

# Find all Firefox profile directories
$ProfilesDir = "$env:APPDATA\Mozilla\Firefox\Profiles"
if (-not (Test-Path $ProfilesDir)) {
    Write-Host "No Firefox profiles found. Skipping."
    exit 0
}

# Check if certutil (NSS) is available
$CertUtil = "$env:PROGRAMFILES\Mozilla Firefox\certutil.exe"
if (-not (Test-Path $CertUtil)) {
    Write-Warning "Firefox certutil not found at $CertUtil"
    Write-Host "Falling back to enterprise policy method..."

    # Write Firefox enterprise policy to auto-import OS root CAs
    $PolicyDir = "$env:PROGRAMFILES\Mozilla Firefox\distribution"
    New-Item -ItemType Directory -Force -Path $PolicyDir | Out-Null

    $Policy = @{
        policies = @{
            Certificates = @{
                ImportEnterpriseRoots = $true
            }
        }
    } | ConvertTo-Json -Depth 5

    Set-Content -Path "$PolicyDir\policies.json" -Value $Policy -Encoding UTF8
    Write-Host "Firefox enterprise policy written. CA will be trusted on next Firefox start."
    exit 0
}

# Install into each profile using NSS certutil
Get-ChildItem $ProfilesDir -Directory | ForEach-Object {
    $Profile = $_.FullName
    Write-Host "  → Profile: $Profile"

    & $CertUtil -A `
        -n $CertName `
        -t "CT,," `
        -i $CertPath `
        -d "sql:$Profile" 2>&1

    if ($LASTEXITCODE -eq 0) {
        Write-Host "     ✅ Installed"
    } else {
        Write-Warning "     ⚠️ Failed for profile $Profile"
    }
}

Write-Host "Firefox CA installation complete."
