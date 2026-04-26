# SPDX-FileCopyrightText: Copyright (c) 2026 Navegos. @DevelVitorF. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
# project: buildtools
# file: x64-windows/build-ccache.ps1
# created: 2026-03-10
# lastModified: 2026-04-26

param (
    [Parameter(HelpMessage = "Base workspace path", Mandatory = $false)]
    [string]$workspacePath = $null,

    [Parameter(HelpMessage = "ccache git repo url", Mandatory = $false)]
    [string]$gitUrl = "https://github.com/Navegos/ccache.git",
    
    [Parameter(HelpMessage = "ccache git branch to sync from", Mandatory = $false)]
    [string]$gitBranch = "master",

    [Parameter(HelpMessage = "Path for ccache storage", Mandatory = $false)]
    [string]$ccacheInstallDir = "$env:LIBRARIES_PATH\ccache"
)

# Capture parameters
$ccacheWorkspacePath = $workspacePath
$ccacheGitUrl = $gitUrl
$ccacheGitBranch = $gitBranch
$ccacheWithMachineEnvironment = $withMachineEnvironment

# 1. Bootstrap Environment if variables are missing
if ([string]::IsNullOrWhitespace($env:ENVIRONMENT_PATH) -or -not (Test-Path $env:ENVIRONMENT_PATH) -or [string]::IsNullOrWhitespace($env:BINARIES_PATH) -or -not (Test-Path $env:BINARIES_PATH) -or [string]::IsNullOrWhitespace($env:LIBRARIES_PATH) -or -not (Test-Path $env:LIBRARIES_PATH)) {
    Write-Error "User Environment variables missing. Please run adduserpaths.ps1 -LibrariesDir 'Path\for\Libraries' BinariesDir 'Path\for\Binaries' -EnvironmentDir 'Path\for\Environment'"
    return
}

$EnvironmentDir = "$env:ENVIRONMENT_PATH"

# 1. Bootstrap Environment if variables are missing
if ([string]::IsNullOrWhitespace($env:ENVIRONMENT_PATH) -or -not (Test-Path $env:ENVIRONMENT_PATH) -or [string]::IsNullOrWhitespace($env:LIBRARIES_PATH) -or -not (Test-Path $env:LIBRARIES_PATH)) {
    Write-Error "User Environment variables missing. Please run adduserpaths.ps1 -LibrariesDir 'Path\for\Libraries' -EnvironmentDir 'Path\for\Environment'"
    return
}

# --- 1. Initialize Visual Studio 2026 Dev Environment ---
$DevShellBootstrapScript = Join-Path $PSScriptRoot "dev-shell.ps1"
if (Test-Path $DevShellBootstrapScript) { . $DevShellBootstrapScript } else {
    Write-Error "Required dependency '$DevShellBootstrapScript' not found!"
    return
}

$RootPath = if ([string]::IsNullOrWhitespace($ccacheWorkspacePath)) { Get-Location } else { $ccacheWorkspacePath }

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
            Write-Error "CRITICAL: Cannot load ninja environment. ninja is missing and $depninjaEnvScript was not found."
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

$Source = Join-Path $RootPath "ccache"
$BuildDir   = Join-Path $Source "build_dir"  # Nested inside source
$RepoUrl    = $ccacheGitUrl
$Branch     = $ccacheGitBranch
$CMakeSource = $Source

$ccacheEnvScript = Join-Path $EnvironmentDir "env-ccache.ps1"

# --- 7. Source Management ---
if (Test-Path $Source) {
    Write-Host "Syncing ccache ($Branch) at $Source..." -ForegroundColor Cyan
    Set-Location $Source
    git fetch --all
    git reset --hard "origin/$Branch"
    git pull --recurse-submodules --force
} else {
    Write-Host "Cloning ccache ($Branch) into $Source..." -ForegroundColor Cyan
    git clone --recurse-submodules $RepoUrl $Source -b $Branch
    Set-Location $Source
}

# --- 8. Clean & Build ---
if (Test-Path $ccacheInstallDir) {
    Write-Host "Wiping existing installation at $ccacheInstallDir..." -ForegroundColor Yellow
    Remove-Item $ccacheInstallDir -Recurse -Force -ErrorAction SilentlyContinue
}
New-Item -Path $ccacheInstallDir -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null

# Ensure fresh build directory
if (Test-Path $BuildDir) { Remove-Item $BuildDir -Recurse -Force -ErrorAction SilentlyContinue }
New-Item -Path $BuildDir -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null

Write-Host "Configuring with Clang/Ninja..." -ForegroundColor Cyan
cmake -G "Ninja" `
    -S "$CMakeSource" `
    -B "$BuildDir" `
    -DCMAKE_POLICY_DEFAULT_CMP0091=NEW `
    -DCMAKE_POLICY_DEFAULT_CMP0109=NEW `
    -DCMAKE_CXX_COMPILER="clang++" `
    -DCMAKE_INSTALL_PREFIX="$ccacheInstallDir" `
    -DCMAKE_BUILD_TYPE=Release `
    -DENABLE_TESTING=OFF `
    -DREDIS_STORAGE_BACKEND=ON `
    -DHTTP_STORAGE_BACKEND=ON `
    -DCMAKE_CXX_FLAGS="-Wno-deprecated-declarations -D_CRT_SECURE_NO_WARNINGS=1" `
    --no-warn-unused-cli

if ($LASTEXITCODE -ne 0) { Write-Error "ccache CMake configuration failed."; Pop-Location; return }

Write-Host "Building and Installing to $ccacheInstallDir..." -ForegroundColor Green
cmake --build "$BuildDir" --target install --config Release --parallel

if ($LASTEXITCODE -ne 0) { Write-Error "ccache Build failed with exit code $LASTEXITCODE"; Pop-Location; return }

Write-Host "Successfully built and installed ccache to $ccacheInstallDir!" -ForegroundColor Green

# Cleanup temporary build debris
Remove-Item $BuildDir -Recurse -Force -ErrorAction SilentlyContinue

# Generate Environment Helper with Clean Paths
$ccacheInstallDir = $ccacheInstallDir.TrimEnd('\')
$ccacheBinPath = Join-Path $ccacheInstallDir "bin"

# --- 9. Create Environment Helper ---
Write-Host "Generating environment helper script..." -ForegroundColor Cyan
$EnvContent = @'
# CCACHE Environment Setup
$ccachebin = "VALUE_BIN_PATH"
$ccacheroot = "VALUE_ROOT_PATH"
$env:CCACHE_PATH = $ccacheroot
$env:CCACHE_ROOT = $ccacheroot
$env:CCACHE_BIN = $ccachebin
if ($env:PATH -notlike "*$ccachebin*") { $env:PATH = $ccachebin + ";" + $env:PATH; $env:PATH = ($env:PATH).Replace(";;", ";") }
Write-Host "CCACHE Environment Loaded." -ForegroundColor Green
Write-Host "CCACHE_ROOT: $env:CCACHE_ROOT" -ForegroundColor Gray
'@ -replace "VALUE_BIN_PATH", $ccacheBinPath -replace "VALUE_ROOT_PATH", $ccacheInstallDir

$EnvContent | Out-File -FilePath $ccacheEnvScript -Encoding utf8
Write-Host "Created: $ccacheEnvScript" -ForegroundColor Gray

# Update Current Session
if (Test-Path $ccacheEnvScript) { . $ccacheEnvScript } else {
    Write-Error "ccache build install finished but $ccacheEnvScript was not created."
    return
}
Write-Host "ccache Version: $(ccache --version | Select-Object -First 1)" -ForegroundColor Gray

# --- Return to Start ---
Pop-Location
Write-Host "Successfully Done! and returned to: $(Get-Location)" -ForegroundColor DarkGreen
