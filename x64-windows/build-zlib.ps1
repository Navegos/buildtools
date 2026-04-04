# Copyright 2026 (C) Navegos. DevelVitorF. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
# file:x64-windows/build-zlib.ps1

param (
    [Parameter(HelpMessage="Base workspace path", Mandatory=$false)]
    [string]$WorkspacePath = "",

    [Parameter(HelpMessage="zlib git repo url", Mandatory=$false)]
    [string]$GitUrl = "https://github.com/Navegos/zlib.git",
    
    [Parameter(HelpMessage="zlib git branch to sync from", Mandatory=$false)]
    [string]$GitBranch = "develop",

    [Parameter(HelpMessage="Path for zlib library storage", Mandatory=$false)]
    [string]$zlibInstallDir = "$env:LIBRARIES_PATH\zlib"
)

# 1. Bootstrap Environment if variables are missing
if ([string]::IsNullOrWhitespace($env:ENVIRONMENT_PATH) -or -not (Test-Path $env:ENVIRONMENT_PATH) -or [string]::IsNullOrWhitespace($env:BINARIES_PATH) -or -not (Test-Path $env:BINARIES_PATH) -or [string]::IsNullOrWhitespace($env:LIBRARIES_PATH) -or -not (Test-Path $env:LIBRARIES_PATH)) {
    Write-Error "User Environment variables missing. Please run adduserpaths.ps1 -LibrariesDir 'Path\for\Libraries' BinariesDir 'Path\for\Binaries' -EnvironmentDir 'Path\for\Environment'"
    return
}

$EnvironmentDir = "$env:ENVIRONMENT_PATH"

# --- 1. Initialize Visual Studio 2026 Dev Environment ---
$DevShellBootstrapScript = Join-Path $PSScriptRoot "dev-shell.ps1"
if (Test-Path $DevShellBootstrapScript) { . $DevShellBootstrapScript } else {
    Write-Error "Required dependency '$DevShellBootstrapScript' not found!"
    return
}

$RootPath = if ([string]::IsNullOrWhitespace($WorkspacePath)) { Get-Location } else { $WorkspacePath }

# --- 2. Initialize git environment if missing ---
if (!(Get-Command git -ErrorAction SilentlyContinue)) {
    $gitEnvScript = Join-Path $EnvironmentDir "env-git.ps1"
    if (Test-Path $gitEnvScript) { . $gitEnvScript } 
    if (!(Get-Command git -ErrorAction SilentlyContinue)) {
        $depgitEnvScript = Join-Path $PSScriptRoot "dep-git.ps1"
        if (Test-Path $depgitEnvScript) { . $depgitEnvScript
        } else {
            Write-Error "CRITICAL: Cannot load Git environment. git is missing and $depgitEnvScript was not found."
            return
        }
    }
}

# --- 3. Initialize cmake environment if missing ---
if (!(Get-Command cmake -ErrorAction SilentlyContinue)) {
    $cmakeEnvScript = Join-Path $EnvironmentDir "env-cmake.ps1"
    if (Test-Path $cmakeEnvScript) { . $cmakeEnvScript } 
    if (!(Get-Command cmake -ErrorAction SilentlyContinue)) {
        $depcmakeEnvScript = Join-Path $PSScriptRoot "dep-cmake.ps1"
        if (Test-Path $depcmakeEnvScript) { . $depcmakeEnvScript
        } else {
            Write-Error "CRITICAL: Cannot load CMake environment. cmake is missing and $depcmakeEnvScript was not found."
            return
        }
    }
}

# --- 4. Initialize ninja environment if missing ---
if (!(Get-Command ninja -ErrorAction SilentlyContinue)) {
    $ninjaEnvScript = Join-Path $EnvironmentDir "env-ninja.ps1"
    if (Test-Path $ninjaEnvScript) { . $ninjaEnvScript } 
    if (!(Get-Command ninja -ErrorAction SilentlyContinue)) {
        $depninjaEnvScript = Join-Path $PSScriptRoot "dep-ninja.ps1"
        if (Test-Path $depninjaEnvScript) { . $depninjaEnvScript
        } else {
            Write-Error "CRITICAL: Cannot load Ninja environment. ninja is missing and $depninjaEnvScript was not found."
            return
        }
    }
}

# --- 5. Initialize clang environment if missing ---
if (!(Get-Command clang -ErrorAction SilentlyContinue)) {
    $llvmEnvScript = Join-Path $EnvironmentDir "env-llvm.ps1"
    if (Test-Path $llvmEnvScript) { . $llvmEnvScript } 
    if (!(Get-Command clang -ErrorAction SilentlyContinue)) {
        $depllvmEnvScript = Join-Path $PSScriptRoot "dep-llvm.ps1"
        if (Test-Path $depllvmEnvScript) { . $depllvmEnvScript
        } else {
            Write-Error "CRITICAL: Cannot load clang environment. clang is missing and $depllvmEnvScript was not found."
            return
        }
    }
}

# --- 6. Path Resolution ---
Push-Location $RootPath

$Source = Join-Path $RootPath "zlib"
$BuildDir   = Join-Path $Source "build_dir"  # Nested inside source
$RepoUrl    = $GitUrl
$Branch     = $GitBranch
$CMakeSource = $Source

# --- 7. Source Management ---
if (Test-Path $Source) {
    Write-Host "Syncing zlib ($Branch) at $Source..." -ForegroundColor Cyan
    Set-Location $Source
    git fetch --all
    git reset --hard "origin/$Branch"
    git pull --recurse-submodules --force
} else {
    Write-Host "Cloning zlib ($Branch) into $Source..." -ForegroundColor Cyan
    git clone --recurse-submodules $RepoUrl $Source -b $Branch
    Set-Location $Source
}

# --- 8. Clean & Build ---
if (Test-Path $zlibInstallDir) {
    Write-Host "Wiping existing installation at $zlibInstallDir..." -ForegroundColor Yellow
    Remove-Item $zlibInstallDir -Recurse -Force -ErrorAction SilentlyContinue
}
New-Item -ItemType Directory -Path $zlibInstallDir -Force -ErrorAction SilentlyContinue | Out-Null

# Ensure fresh build directory
if (Test-Path $BuildDir) { Remove-Item $BuildDir -Recurse -Force -ErrorAction SilentlyContinue }
New-Item -ItemType Directory -Path $BuildDir -Force -ErrorAction SilentlyContinue | Out-Null

Write-Host "Configuring with Clang/Ninja..." -ForegroundColor Cyan
cmake -G "Ninja" `
    -S "$CMakeSource" `
    -B "$BuildDir" `
    -DCMAKE_C_COMPILER="clang" `
    -DCMAKE_INSTALL_PREFIX="$zlibInstallDir" `
    -DCMAKE_BUILD_TYPE=Release `
    -DCMAKE_C_FLAGS="-Wno-deprecated-declarations -D_CRT_SECURE_NO_WARNINGS=1"

if ($LASTEXITCODE -ne 0) { Write-Error "zlib CMake configuration failed."; Pop-Location; return }

Write-Host "Building and Installing to $zlibInstallDir..." -ForegroundColor Green
cmake --build "$BuildDir" --target install --config Release --parallel

if ($LASTEXITCODE -ne 0) { Write-Error "zlib Build failed with exit code $LASTEXITCODE"; Pop-Location; return }

Write-Host "Successfully built and installed zlib to $zlibInstallDir!" -ForegroundColor Green

# Cleanup temporary build debris
Remove-Item $BuildDir -Recurse -Force -ErrorAction SilentlyContinue

# Generate Environment Helper with Clean Paths
$zlibInstallDir = $zlibInstallDir.TrimEnd('\')
$zlibIncludeDir = Join-Path $zlibInstallDir "include"
$zlibLibDir = Join-Path $zlibInstallDir "lib"
$zlibBinPath = Join-Path $zlibInstallDir "bin"
$zlibCMakePath = $zlibInstallDir.Replace('\', '/')

# --- 9. Create Environment Helper ---
Write-Host "Generating environment helper script..." -ForegroundColor Cyan
$zlibEnvScript = Join-Path $EnvironmentDir "env-zlib.ps1"
$EnvContent = @'
# ZLIB Environment Setup
$zlibroot = "VALUE_ROOT_PATH"
$zlibinclude = "VALUE_INCLUDE_PATH"
$zliblibrary = "VALUE_LIB_PATH"
$zlibbin = "VALUE_BIN_PATH"
$zlibcmakepath = "VALUE_CMAKE_PATH"
$env:ZLIB_PATH = $zlibroot
$env:ZLIB_ROOT = $zlibroot
$env:ZLIB_BIN = $zlibbin
$env:ZLIB_INCLUDEDIR = $zlibinclude
$env:ZLIB_LIBRARYDIR = $zliblibrary
if ($env:CMAKE_PREFIX_PATH -notlike "*$zlibcmakepath*") { $env:CMAKE_PREFIX_PATH = $zlibcmakepath + ";" + $env:CMAKE_PREFIX_PATH }
if ($env:INCLUDE -notlike "*$zlibinclude*") { $env:INCLUDE = $zlibinclude + ";" + $env:INCLUDE }
if ($env:LIB -notlike "*$zliblibrary*") { $env:LIB = $zliblibrary + ";" + $env:LIB }
if ($env:PATH -notlike "*$zlibbin*") { $env:PATH = $zlibbin + ";" + $env:PATH }
Write-Host "ZLIB Environment Loaded." -ForegroundColor Green
Write-Host "ZLIB_ROOT: $env:ZLIB_ROOT" -ForegroundColor Gray
'@  -replace "VALUE_ROOT_PATH", $zlibInstallDir `
    -replace "VALUE_INCLUDE_PATH", $zlibIncludeDir `
    -replace "VALUE_LIB_PATH", $zlibLibDir `
    -replace "VALUE_BIN_PATH", $zlibBinPath `
    -replace "VALUE_CMAKE_PATH", $zlibCMakePath

$EnvContent | Out-File -FilePath $zlibEnvScript -Encoding utf8
Write-Host "Created: $zlibEnvScript" -ForegroundColor Gray

# --- Return to Start ---
Pop-Location
Write-Host "Done! and returned to: $(Get-Location)" -ForegroundColor Gray
