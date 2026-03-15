# Copyright 2026 (C) Navegos. DevelVitorF. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
# file:x64-windows/dep-icu.ps1

param (
    [Parameter(HelpMessage="Target vcpkg triplet")]
    [string]$Triplet = "x64-windows"
)

# 1. Bootstrap Environment if variables are missing
if ([string]::IsNullOrWhitespace($env:ENVIRONMENT_PATH) -or -not (Test-Path $env:ENVIRONMENT_PATH) -or [string]::IsNullOrWhitespace($env:BINARIES_PATH) -or -not (Test-Path $env:BINARIES_PATH) -or [string]::IsNullOrWhitespace($env:LIBRARIES_PATH) -or -not (Test-Path $env:LIBRARIES_PATH)) {
    Write-Error "User Environment variables missing. Please run adduserpaths.ps1 -LibrariesDir 'Path\for\Libraries' BinariesDir 'Path\for\Binaries' -EnvironmentDir 'Path\for\Environment'"
    return
}

$EnvironmentDir = "$env:ENVIRONMENT_PATH"

$vcpkgRoot = "$env:VCPKG_ROOT"

if ([string]::IsNullOrWhitespace($vcpkgRoot) -or !(Test-Path $vcpkgRoot)) {
    Write-Host "VCPKG_ROOT not found. Attempting to load vcpkg environment..." -ForegroundColor Yellow
    $vcpkgEnvScript = Join-Path $EnvironmentDir "env-vcpkg.ps1"
    if (Test-Path $vcpkgEnvScript) { . $vcpkgEnvScript }
    $vcpkgRoot = "$env:VCPKG_ROOT"
}

if ([string]::IsNullOrWhitespace($vcpkgRoot)) {
    Write-Error "VCPKG_ROOT is still missing. Please run dep-vcpkg.ps1 first."
    return
}

# --- 1. Install ICU via vcpkg ---
# Note: 'icu' is the meta-package in vcpkg
Write-Host "Installing ICU:$Triplet via vcpkg..." -ForegroundColor Cyan
Push-Location $vcpkgRoot
cmd /c "vcpkg install icu:$Triplet"
if ($LASTEXITCODE -ne 0) {
    Write-Error "vcpkg failed to install ICU."
    Pop-Location; return
}
Pop-Location

# --- 2. Resolve Paths ---
$installBase = Join-Path $vcpkgRoot "installed\$Triplet"
$icuLibPath = Join-Path $installBase "lib"

# Finalize Environment Helper
# ICU typically produces icuuc.lib (Common), icuin.lib (I18N), etc.
if (Test-Path (Join-Path $icuLibPath "icuuc.lib")) {
    # Generate Environment Helper with Clean Paths
    $icuInstallDir = $installBase.TrimEnd('\')
    $icuIncludeDir = Join-Path $icuInstallDir "include"
    $icuLibDir     = Join-Path $icuInstallDir "lib"
    $icuBinPath    = Join-Path $icuInstallDir "bin"
    $icuToolsBinPath = Join-Path $icuInstallDir "tools\icu\bin"
    $icuCMakePath  = $icuInstallDir.Replace('\', '/')
    
    # --- 3. Create Environment Helper ---
    Write-Host "Generating environment helper script..." -ForegroundColor Cyan
    $icuEnvScript = Join-Path $EnvironmentDir "env-icu.ps1"
    $EnvContent = @'
# ICU Environment Setup
$icuroot = "VALUE_ROOT_PATH"
$icuinclude = "VALUE_INCLUDE_PATH"
$iculibrary = "VALUE_LIB_PATH"
$icubin = "VALUE_BIN_PATH"
$icutoolsbin = "VALUE_TOOLS_BIN_PATH"
$icucmakepath = "VALUE_CMAKE_PATH"
$env:ICU_PATH = $icuroot
$env:ICU_ROOT = $icuroot
$env:ICU_BIN = $icubin
$env:ICU_TOOLS_BIN = $icutoolsbin
$env:ICU_INCLUDEDIR = $icuinclude
$env:ICU_LIBRARYDIR = $iculibrary
if ($env:CMAKE_PREFIX_PATH -notlike "*$icucmakepath*") { $env:CMAKE_PREFIX_PATH = $icucmakepath + ";" + $env:CMAKE_PREFIX_PATH }
if ($env:INCLUDE -notlike "*$icuinclude*") { $env:INCLUDE = $icuinclude + ";" + $env:INCLUDE }
if ($env:LIB -notlike "*$iculibrary*") { $env:LIB = $iculibrary + ";" + $env:LIB }
"$icubin", "$icutoolsbin" | ForEach-Object { if ($env:PATH -notlike "*$_*") { $env:PATH = $_ + ";" + $env:PATH } }
Write-Host "ICU Environment Loaded." -ForegroundColor Green
Write-Host "ICU_ROOT: $env:ICU_ROOT" -ForegroundColor Gray
'@  -replace "VALUE_ROOT_PATH", $icuInstallDir `
    -replace "VALUE_INCLUDE_PATH", $icuIncludeDir `
    -replace "VALUE_LIB_PATH", $icuLibDir `
    -replace "VALUE_BIN_PATH", $icuBinPath `
    -replace "VALUE_TOOLS_BIN_PATH", $icuToolsBinPath `
    -replace "VALUE_CMAKE_PATH", $icuCMakePath
    
    $EnvContent | Out-File -FilePath $icuEnvScript -Encoding utf8
    Write-Host "Created: $icuEnvScript" -ForegroundColor Gray
    
    # Update Current Session
    if (Test-Path $icuEnvScript) { . $icuEnvScript } else {
        Write-Error "icu dep install finished but $icuEnvScript was not created."
        return
    }
    Write-Host "icu Version: $(vcpkg list icu)" -ForegroundColor Gray
} else {
    Write-Error "icuuc.lib was not found in the $icuLibPath folder."
    return
}
