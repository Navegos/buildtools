# Copyright 2026 (C) Navegos. DevelVitorF. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
# file:x64-windows/build-onetbb.ps1

param (
    [Parameter(HelpMessage="Base workspace path", Mandatory=$false)]
    [string]$WorkspacePath = "",

    [Parameter(HelpMessage="oneTBB git repo url", Mandatory=$false)]
    [string]$GitUrl = "https://github.com/Navegos/oneTBB.git",
    
    [Parameter(HelpMessage="oneTBB git branch to sync from", Mandatory=$false)]
    [string]$GitBranch = "master",

    [Parameter(HelpMessage="Path for oneTBB library storage", Mandatory=$false)]
    [string]$oneTBBInstallDir = "$env:LIBRARIES_PATH\oneTBB"
)

# 1. Bootstrap Environment if variables are missing
if ([string]::IsNullOrWhitespace($env:ENVIRONMENT_PATH) -or -not (Test-Path $env:ENVIRONMENT_PATH) -or [string]::IsNullOrWhitespace($env:BINARIES_PATH) -or -not (Test-Path $env:BINARIES_PATH) -or [string]::IsNullOrWhitespace($env:LIBRARIES_PATH) -or -not (Test-Path $env:LIBRARIES_PATH)) {
    Write-Error "User Environment variables missing. Please run adduserpaths.ps1 -LibrariesDir 'Path\for\Libraries' BinariesDir 'Path\for\Binaries' -EnvironmentDir 'Path\for\Environment'"
    return
}

$EnvironmentDir = "$env:ENVIRONMENT_PATH"

# --- 1. Initialize Visual Studio 2026 Dev Environment ---
$DevShellBootstrapScript = Join-Path $PSScriptRoot "devshell.ps1"
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

$Source = Join-Path $RootPath "oneTBB"
$BuildDir   = Join-Path $Source "build_dir"  # Nested inside source
$RepoUrl    = $GitUrl
$Branch     = $GitBranch
$CMakeSource = $Source

# --- 7. Source Management ---
if (Test-Path $Source) {
    Write-Host "Syncing oneTBB ($Branch) at $Source..." -ForegroundColor Cyan
    Set-Location $Source
    git fetch --all
    git reset --hard "origin/$Branch"
    git pull --recurse-submodules --force
} else {
    Write-Host "Cloning oneTBB ($Branch) into $Source..." -ForegroundColor Cyan
    git clone --recurse-submodules $RepoUrl $Source -b $Branch
    Set-Location $Source
}

# --- 8. Clean & Build ---
if (Test-Path $oneTBBInstallDir) {
    Write-Host "Wiping existing installation at $oneTBBInstallDir..." -ForegroundColor Yellow
    Remove-Item -Recurse -Force $oneTBBInstallDir -ErrorAction SilentlyContinue
}
New-Item -ItemType Directory -Path $oneTBBInstallDir -Force | Out-Null

# Ensure fresh build directory
if (Test-Path $BuildDir) { Remove-Item -Recurse -Force $BuildDir }
New-Item -ItemType Directory -Path $BuildDir -Force | Out-Null

Write-Host "Configuring with Clang/Ninja..." -ForegroundColor Cyan
cmake -G "Ninja" `
    -S "$CMakeSource" `
    -B "$BuildDir" `
    -DCMAKE_C_COMPILER="clang" `
    -DCMAKE_CXX_COMPILER="clang++" `
    -DCMAKE_INSTALL_PREFIX="$oneTBBInstallDir" `
    -DCMAKE_BUILD_TYPE=Release `
    -DTBB_TEST=OFF `
    -DTBB_EXAMPLES=OFF `
    -DTBB_DOC_EXAMPLES=OFF `
    -DTBB_BENCH=OFF `
    -DTBB_STRICT=OFF `
    -DTBB4PY_BUILD=ON `
    -DTBB_BUILD=ON `
    -DTBBMALLOC_BUILD=ON `
    -DTBBMALLOC_PROXY_BUILD=ON `
    -DTBB_CPF=ON `
    -DTBB_ENABLE_IPO=ON `
    -DTBB_FUZZ_TESTING=OFF `
    -DTBB_INSTALL=ON `
    -DTBB_FILE_TRIM=ON `
    -DBUILD_SHARED_LIBS=ON `
    -DCMAKE_C_FLAGS="-Wno-deprecated-declarations -D_CRT_SECURE_NO_WARNINGS=1" `
    -DCMAKE_CXX_FLAGS="-Wno-deprecated-declarations -D_CRT_SECURE_NO_WARNINGS=1"

if ($LASTEXITCODE -ne 0) { Write-Error "oneTBB CMake configuration failed."; Pop-Location; return }

Write-Host "Building and Installing to $oneTBBInstallDir..." -ForegroundColor Green
cmake --build "$BuildDir" --target install --config Release --parallel

if ($LASTEXITCODE -ne 0) { Write-Error "oneTBB Build failed with exit code $LASTEXITCODE"; Pop-Location; return }

Write-Host "Successfully built and installed oneTBB to $oneTBBInstallDir!" -ForegroundColor Green

# Cleanup temporary build debris
Remove-Item -Recurse -Force $BuildDir

# Generate Environment Helper with Clean Paths
$oneTBBInstallDir = $oneTBBInstallDir.TrimEnd('\')
$oneTBBIncludeDir = Join-Path $oneTBBInstallDir "include"
$oneTBBLibDir = Join-Path $oneTBBInstallDir "lib"
$oneTBBBinPath = Join-Path $oneTBBInstallDir "bin"
$oneTBBCMakePath = $oneTBBInstallDir.Replace('\', '/')

# --- 9. Create Environment Helper ---
Write-Host "Generating environment helper script..." -ForegroundColor Cyan
$oneTBBEnvScript = Join-Path $EnvironmentDir "env-oneTBB.ps1"
$EnvContent = @'
# TBB Environment Setup
$oneTBBroot = "VALUE_ROOT_PATH"
$oneTBBinclude = "VALUE_INCLUDE_PATH"
$oneTBBlibrary = "VALUE_LIB_PATH"
$oneTBBbin = "VALUE_BIN_PATH"
$oneTBBcmakepath = "VALUE_CMAKE_PATH"
$env:TBB_PATH = $oneTBBroot
$env:TBB_ROOT = $oneTBBroot
$env:TBB_BIN = $oneTBBbin
$env:TBB_INCLUDEDIR = $oneTBBinclude
$env:TBB_LIBRARYDIR = $oneTBBlibrary
if ($env:CMAKE_PREFIX_PATH -notlike "*$oneTBBcmakepath*") { $env:CMAKE_PREFIX_PATH = $oneTBBcmakepath + ";" + $env:CMAKE_PREFIX_PATH }
if ($env:INCLUDE -notlike "*$oneTBBinclude*") { $env:INCLUDE = $oneTBBinclude + ";" + $env:INCLUDE }
if ($env:LIB -notlike "*$oneTBBlibrary*") { $env:LIB = $oneTBBlibrary + ";" + $env:LIB }
if ($env:PATH -notlike "*$oneTBBbin*") { $env:PATH = $oneTBBbin + ";" + $env:PATH }
Write-Host "OneTBB Environment Loaded." -ForegroundColor Green
Write-Host "TBB_ROOT: $env:TBB_ROOT" -ForegroundColor Gray
'@  -replace "VALUE_ROOT_PATH", $oneTBBInstallDir `
    -replace "VALUE_INCLUDE_PATH", $oneTBBIncludeDir `
    -replace "VALUE_LIB_PATH", $oneTBBLibDir `
    -replace "VALUE_BIN_PATH", $oneTBBBinPath `
    -replace "VALUE_CMAKE_PATH", $oneTBBCMakePath

$EnvContent | Out-File -FilePath $oneTBBEnvScript -Encoding utf8
Write-Host "Created: $oneTBBEnvScript" -ForegroundColor Gray

# --- Return to Start ---
Pop-Location
Write-Host "Done! and returned to: $(Get-Location)" -ForegroundColor Gray
