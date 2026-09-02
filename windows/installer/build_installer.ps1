# ─────────────────────────────────────────────────────────────────────────────
# SALU — one-shot installer build (Phase 9 · Step 4)
#
#   .\windows\installer\build_installer.ps1
#
# Prerequisites:
#   * Flutter SDK (stable) with the Windows desktop toolchain
#   * Inno Setup 6  → https://jrsoftware.org/isdl.php
#
# Output: windows\installer\output\SALU-1.0.0-setup.exe
# ─────────────────────────────────────────────────────────────────────────────
$ErrorActionPreference = 'Stop'
Set-Location (Join-Path $PSScriptRoot '..\..')

Write-Host '» flutter build windows --release' -ForegroundColor Cyan
flutter build windows --release
if ($LASTEXITCODE -ne 0) { throw 'Release build failed.' }

$iscc = Get-Command iscc.exe -ErrorAction SilentlyContinue
if ($iscc) {
    $isccPath = $iscc.Source
} else {
    $candidates = @(
        "$env:ProgramFiles\Inno Setup 6\ISCC.exe",
        "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe"
    )
    $isccPath = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
}
if (-not $isccPath) {
    throw 'Inno Setup 6 not found. Install it from https://jrsoftware.org/isdl.php and retry.'
}

Write-Host '» iscc windows\installer\SALU.iss' -ForegroundColor Cyan
& $isccPath 'windows\installer\SALU.iss'
if ($LASTEXITCODE -ne 0) { throw 'Inno Setup compilation failed.' }

Write-Host "`nDone → windows\installer\output\SALU-1.0.0-setup.exe" -ForegroundColor Green
