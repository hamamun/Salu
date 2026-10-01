<#
.SYNOPSIS
    Clean, rebuild and package SALU into a standalone Windows installer.

.DESCRIPTION
    The Windows mirror of the release loop in salu.md, section 25:

        1. flutter clean                       (removes build\ and .dart_tool\)
        2. flutter pub get                     (regenerates windows\flutter\generated_*)
        3. flutter analyze / flutter test      (release gate)
        4. flutter build windows --release
        5. ISCC.exe salu.iss                   (Inno Setup -> dist\)

    Run from anywhere; the script resolves the repository root itself.

.PARAMETER SkipClean
    Keep the existing build\ folder (incremental rebuild - much faster, but not
    a "clean" build).

.PARAMETER SkipTests
    Skip the flutter analyze / flutter test gate.

.PARAMETER AllowVersionMismatch
    Proceed even when salu.iss MyAppVersion differs from pubspec.yaml version.

.PARAMETER OpenOutput
    Reveal the generated installer in File Explorer when done.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File tools\build_installer.ps1

.EXAMPLE
    # quick incremental rebuild, no clean, no tests
    powershell -ExecutionPolicy Bypass -File tools\build_installer.ps1 -SkipClean -SkipTests
#>
[CmdletBinding()]
param(
    [switch]$SkipClean,
    [switch]$SkipTests,
    [switch]$AllowVersionMismatch,
    [switch]$OpenOutput
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repoRoot  = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $repoRoot   # flutter/dart/ISCC all resolve paths from here
$issPath   = Join-Path $repoRoot 'salu.iss'
$pubspec   = Join-Path $repoRoot 'pubspec.yaml'
$releaseDir = Join-Path $repoRoot 'build\windows\x64\runner\Release'
$distDir   = Join-Path $repoRoot 'dist'

function Write-Step([string]$Text) {
    Write-Host ''
    Write-Host "=== $Text ===" -ForegroundColor Cyan
}

function Invoke-Tool([string]$Label, [string]$Exe, [string[]]$ToolArgs) {
    Write-Host "> $Exe $($ToolArgs -join ' ')" -ForegroundColor DarkGray
    & $Exe @ToolArgs
    if ($LASTEXITCODE -ne 0) {
        throw "$Label failed with exit code $LASTEXITCODE."
    }
}

function Find-Iscc {
    $onPath = Get-Command 'ISCC.exe' -ErrorAction SilentlyContinue
    if ($onPath) { return $onPath.Source }

    $candidates = @()
    if (${env:ProgramFiles(x86)}) { $candidates += "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe" }
    if ($env:ProgramFiles)        { $candidates += "$env:ProgramFiles\Inno Setup 6\ISCC.exe" }
    foreach ($key in @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Inno Setup 6_is1',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\Inno Setup 6_is1')) {
        if (Test-Path $key) {
            $loc = (Get-ItemProperty -Path $key -Name InstallLocation -ErrorAction SilentlyContinue).InstallLocation
            if ($loc) { $candidates += (Join-Path $loc 'ISCC.exe') }
        }
    }
    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path $candidate)) { return $candidate }
    }
    return $null
}

foreach ($tool in @('flutter', 'dart')) {
    if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
        throw "'$tool' is not on PATH. Install the Flutter SDK (salu.md section 2: Flutter 3.47.5) and reopen the terminal."
    }
}
$iscc = Find-Iscc
if (-not $iscc) {
    throw 'ISCC.exe (Inno Setup 6 compiler) not found on PATH or in "Program Files\Inno Setup 6". Install Inno Setup 6 from https://jrsoftware.org/isdl.php.'
}
if (-not (Test-Path $issPath)) { throw "Missing $issPath." }

# -- Version gate: salu.iss must state the same version as pubspec.yaml -------
$pubMatch = Select-String -Path $pubspec -Pattern '^version:\s*([0-9]+\.[0-9]+\.[0-9]+)' | Select-Object -First 1
$issMatch = Select-String -Path $issPath -Pattern '^#define\s+MyAppVersion\s+"([^"]+)"' | Select-Object -First 1
$pubVersion = if ($pubMatch) { $pubMatch.Matches[0].Groups[1].Value } else { $null }
$issVersion = if ($issMatch) { $issMatch.Matches[0].Groups[1].Value } else { $null }
if (-not $pubVersion -or -not $issVersion) {
    throw 'Could not read the version from pubspec.yaml or salu.iss.'
}
if ($issVersion -match '\+') {
    throw "salu.iss MyAppVersion is '$issVersion'. Keep it to the three numeric parts (e.g. $pubVersion): " +
          'the pubspec build number (+N) is not valid Windows version metadata for the installer .exe.'
}
Write-Host "pubspec.yaml version : $pubVersion"
Write-Host "salu.iss MyAppVersion: $issVersion"
if ($pubVersion -ne $issVersion) {
    $message = "Version mismatch: salu.iss says $issVersion, pubspec.yaml says $pubVersion. " +
               'Update the ''#define MyAppVersion'' line in salu.iss (or re-run with -AllowVersionMismatch).'
    if (-not $AllowVersionMismatch) { throw $message }
    Write-Warning $message
}

# -- 1. Clean -----------------------------------------------------------------
if ($SkipClean) {
    Write-Step '1/5 flutter clean - SKIPPED (-SkipClean)'
} else {
    Write-Step '1/5 flutter clean (removing build\ and .dart_tool\)'
    Invoke-Tool 'flutter clean' 'flutter' @('clean')
}

# -- 2. Dependencies ----------------------------------------------------------
Write-Step '2/5 flutter pub get'
Invoke-Tool 'flutter pub get' 'flutter' @('pub', 'get')

# -- 3. Release gate ----------------------------------------------------------
if ($SkipTests) {
    Write-Step '3/5 flutter analyze + test - SKIPPED (-SkipTests)'
} else {
    Write-Step '3/5 flutter analyze / flutter test / dart format check'
    Invoke-Tool 'flutter analyze' 'flutter' @('analyze')
    Invoke-Tool 'flutter test' 'flutter' @('test')
    Invoke-Tool 'dart format' 'dart' @('format', '--set-exit-if-changed', 'lib', 'test')
}

# -- 4. Release build ---------------------------------------------------------
Write-Step '4/5 flutter build windows --release'
Invoke-Tool 'flutter build windows --release' 'flutter' @('build', 'windows', '--release')

if (-not (Test-Path (Join-Path $releaseDir 'salu.exe'))) {
    throw "Build finished but salu.exe is missing from $releaseDir."
}
$bundledRuntime = @(Get-ChildItem -Path $releaseDir -File |
    Where-Object { $_.Name -match '^(msvcp140|vcruntime140|vcruntime140_1)\.dll$' } |
    Select-Object -ExpandProperty Name)
if ($bundledRuntime.Count -lt 3) {
    Write-Warning "MSVC runtime DLLs next to salu.exe: $($bundledRuntime -join ', ') - expected msvcp140.dll, vcruntime140.dll, vcruntime140_1.dll (salu.md section 25)."
}
if (-not (Test-Path (Join-Path $releaseDir 'data'))) {
    throw "Build output is incomplete: $releaseDir\data is missing."
}

# -- 5. Inno Setup ------------------------------------------------------------
Write-Step "5/5 Inno Setup - $iscc"
Invoke-Tool 'ISCC' $iscc @($issPath)

$installer = Get-ChildItem -Path $distDir -Filter 'SALU-Setup-*.exe' -File -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1
if (-not $installer) { throw "Inno Setup reported success but no installer .exe is in $distDir." }

$sizeMb = [math]::Round($installer.Length / 1MB, 1)
Write-Host ''
Write-Host 'DONE' -ForegroundColor Green
Write-Host "  Installer : $($installer.FullName)  ($sizeMb MB)"
Write-Host "  Version   : $issVersion"
Write-Host "  Test on a clean Windows 10 1809+/11 x64 VM: install, launch, single instance,"
Write-Host '  associations (if selected), then uninstall and confirm HKCU entries are gone.'

if ($OpenOutput) { Invoke-Item (Split-Path -Parent $installer.FullName) }
