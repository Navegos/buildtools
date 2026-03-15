# Copyright 2026 (C) Navegos. DevelVitorF. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
# file:x64-windows/dep-libiconv.ps1

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

# --- 1. Install libiconv via vcpkg ---
Write-Host "Installing libiconv:$Triplet via vcpkg..." -ForegroundColor Cyan
Push-Location $vcpkgRoot
cmd /c "vcpkg install libiconv:$Triplet"
if ($LASTEXITCODE -ne 0) {
    Write-Error "vcpkg failed to install libiconv."
    Pop-Location; return
}
Pop-Location

# --- 2. Resolve Paths ---
# vcpkg installs files to [root]/installed/[triplet]/
$installBase = Join-Path $vcpkgRoot "installed\$Triplet"
$libiconvLib = Join-Path $installBase "lib"

# Finalize Environment Helper
if (Test-Path (Join-Path $libiconvLib "iconv.lib")) {
    # Generate Environment Helper with Clean Paths
    $libiconvInstallDir = $installBase.TrimEnd('\')
    $libiconvIncludeDir = Join-Path $libiconvInstallDir "include"
    $libiconvLibDir = Join-Path $libiconvInstallDir "lib"
    $libiconvBinPath = Join-Path $libiconvInstallDir "bin"
    $libiconvToolsBinPath = Join-Path $libiconvInstallDir "tools\libiconv\bin"
    $libiconvCMakePath = $libiconvInstallDir.Replace('\', '/')
    
    # --- 3. Create Environment Helper ---
    Write-Host "Generating environment helper script..." -ForegroundColor Cyan
    $libiconvEnvScript = Join-Path $EnvironmentDir "env-libiconv.ps1"
    $EnvContent = @'
# LIBICONV Environment Setup
$libiconvroot = "VALUE_ROOT_PATH"
$libiconvinclude = "VALUE_INCLUDE_PATH"
$libiconvlibrary = "VALUE_LIB_PATH"
$libiconvbin = "VALUE_BIN_PATH"
$libiconvtoolsbin = "VALUE_TOOLS_BIN_PATH"
$libiconvcmakepath = "VALUE_CMAKE_PATH"
$env:LIBICONV_PATH = $libiconvroot
$env:LIBICONV_ROOT = $libiconvroot
$env:LIBICONV_BIN = $libiconvbin
$env:LIBICONV_TOOLS_BIN = $libiconvtoolsbin
$env:LIBICONV_INCLUDEDIR = $libiconvinclude
$env:LIBICONV_LIBRARYDIR = $libiconvlibrary
if ($env:CMAKE_PREFIX_PATH -notlike "*$libiconvcmakepath*") { $env:CMAKE_PREFIX_PATH = $libiconvcmakepath + ";" + $env:CMAKE_PREFIX_PATH }
if ($env:INCLUDE -notlike "*$libiconvinclude*") { $env:INCLUDE = $libiconvinclude + ";" + $env:INCLUDE }
if ($env:LIB -notlike "*$libiconvlibrary*") { $env:LIB = $libiconvlibrary + ";" + $env:LIB }
"$libiconvbin", "$libiconvtoolsbin" | ForEach-Object { if ($env:PATH -notlike "*$_*") { $env:PATH = $_ + ";" + $env:PATH } }
Write-Host "LIBICONV Environment Loaded." -ForegroundColor Green
Write-Host "LIBICONV_ROOT: $env:LIBICONV_ROOT" -ForegroundColor Gray
'@  -replace "VALUE_ROOT_PATH", $libiconvInstallDir `
    -replace "VALUE_INCLUDE_PATH", $libiconvIncludeDir `
    -replace "VALUE_LIB_PATH", $libiconvLibDir `
    -replace "VALUE_BIN_PATH", $libiconvBinPath `
    -replace "VALUE_TOOLS_BIN_PATH", $libiconvToolsBinPath `
    -replace "VALUE_CMAKE_PATH", $libiconvCMakePath
    
    $EnvContent | Out-File -FilePath $libiconvEnvScript -Encoding utf8
    Write-Host "Created: $libiconvEnvScript" -ForegroundColor Gray
    
    # Update Current Session
    if (Test-Path $libiconvEnvScript) { . $libiconvEnvScript } else {
        Write-Error "libiconv dep install finished but $libiconvEnvScript was not created."
        return
    }
    Write-Host "libiconv Version: $(vcpkg list libiconv)" -ForegroundColor Gray
} else {
    Write-Error "iconv.lib was not found in the $libiconvLibPath folder."
    return
}
