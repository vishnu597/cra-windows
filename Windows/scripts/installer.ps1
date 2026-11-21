# Builds Cra's installer (Windows/installer/Cra.iss, Inno Setup 6) from Windows/build/Cra, which
# build.ps1 assembles first, into Windows/build/installer/Cra-<version>-Setup.exe. The Windows
# App Runtime's own installer goes inside it, for PCs that don't have the runtime yet.
param([string]$Version = '0.0.0')
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$app = Join-Path $root 'build\Cra'
if (-not (Test-Path (Join-Path $app 'Cra.exe'))) { throw "No Cra.exe in ${app}: run build.ps1 first" }

$runtime = Join-Path $root 'build\windowsappruntimeinstall-x64.exe'
if (-not (Test-Path $runtime)) {
    curl.exe -L --fail --no-progress-meter -o $runtime https://aka.ms/windowsappsdk/1.7/latest/windowsappruntimeinstall-x64.exe
    if ($LASTEXITCODE) { throw 'The Windows App Runtime installer could not be downloaded' }
}

$iscc = @("${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe", "$env:ProgramFiles\Inno Setup 6\ISCC.exe",
          "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe") | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $iscc) {
    $found = Get-Command ISCC.exe -ErrorAction SilentlyContinue
    if ($found) { $iscc = $found.Source }
}
if (-not $iscc) {
    Write-Host 'Inno Setup 6 not found: installing it with winget'
    winget install --id JRSoftware.InnoSetup -e --silent --accept-package-agreements --accept-source-agreements | Out-Host
    $iscc = @("${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe", "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe") |
        Where-Object { Test-Path $_ } | Select-Object -First 1
    if (-not $iscc) { throw 'Inno Setup 6 (ISCC.exe) not found' }
}

$out = Join-Path $root 'build\installer'
New-Item -ItemType Directory -Force $out | Out-Null
& $iscc /Qp "/DAppVersion=$Version" "/DSourceDir=$app" "/DOutputDir=$out" (Join-Path $root 'installer\Cra.iss')
if ($LASTEXITCODE) { throw "ISCC failed ($LASTEXITCODE)" }
$setup = Join-Path $out "Cra-$Version-Setup.exe"
if (-not (Test-Path $setup)) { throw "$setup was not made" }
Write-Host "Installer: $setup ($([math]::Round((Get-Item $setup).Length / 1MB)) MB)"
