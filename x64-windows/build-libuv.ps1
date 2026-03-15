# Copyright 2026 (C) Navegos. DevelVitorF. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
# file:x64-windows/build-libuv.ps1

param (
    [Parameter(HelpMessage="Base workspace path", Mandatory=$false)]
    [string]$WorkspacePath = "",

    [Parameter(HelpMessage="libuv git repo url", Mandatory=$false)]
    [string]$GitUrl = "https://github.com/Navegos/libuv.git",
    
    [Parameter(HelpMessage="libuv git branch to sync from", Mandatory=$false)]
    [string]$GitBranch = "v1.x",

    [Parameter(HelpMessage="Path for libuv library storage", Mandatory=$false)]
    [string]$libuvInstallDir = "$env:LIBRARIES_PATH\libuv"
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
            Write-Error "CRITICAL: Cannot load ninja environment. ninja is missing and $buildninjaEnvScript was not found."
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

$Source = Join-Path $RootPath "libuv"
$BuildDir = Join-Path $Source "build_dir"
$RepoUrl    = $GitUrl
$Branch     = $GitBranch
$CMakeSource = $Source

# --- 7. Source Management ---
if (Test-Path $Source) {
    Write-Host "Syncing libuv ($Branch) at $Source..." -ForegroundColor Cyan
    Set-Location $Source
    git fetch --all
    git reset --hard "origin/$Branch"
    git pull --recurse-submodules --force
} else {
    Write-Host "Cloning libuv ($Branch) into $Source..." -ForegroundColor Cyan
    git clone --recurse-submodules $RepoUrl $Source -b $Branch
    Set-Location $Source
}

# --- 8. Clean Final Destination ---
if (Test-Path $libuvInstallDir) {
    Write-Host "Wiping existing installation..." -ForegroundColor Yellow
    Remove-Item -Recurse -Force $libuvInstallDir -ErrorAction SilentlyContinue
}
New-Item -ItemType Directory -Path $libuvInstallDir -Force | Out-Null

# Ensure fresh build directory
if (Test-Path $BuildDir) { Remove-Item -Recurse -Force $BuildDir }
New-Item -ItemType Directory -Path $BuildDir -Force | Out-Null

# --- 9. STAGE 2: Build Libraries ---
Write-Host "Building Libraries..." -ForegroundColor Cyan
cmake -G "Ninja" `
    -S "$CMakeSource" `
    -B "$BuildDir" `
    -DCMAKE_C_COMPILER="clang" `
    -DCMAKE_CXX_COMPILER="clang++" `
    -DCMAKE_INSTALL_PREFIX="$libuvInstallDir" `
    -DCMAKE_BUILD_TYPE=Release `
    -DLIBUV_BUILD_SHARED=ON `
    -DBUILD_TESTING=OFF `
    -DLIBUV_BUILD_TESTS=OFF `
    -DLIBUV_BUILD_BENCH=OFF `
    -DCMAKE_C_FLAGS="-Wno-deprecated-declarations -D_CRT_SECURE_NO_WARNINGS=1" `
    -DCMAKE_CXX_FLAGS="-Wno-deprecated-declarations -D_CRT_SECURE_NO_WARNINGS=1"
    
if ($LASTEXITCODE -ne 0) { Write-Error "libuv CMake Libraries configuration failed."; Pop-Location; return }

cmake --build "$BuildDir" --target install --config Release --parallel

if ($LASTEXITCODE -ne 0) { Write-Error "libuv Build failed with exit code $LASTEXITCODE"; Pop-Location; return }

Write-Host "Successfully built and installed libuv to $libuvInstallDir!" -ForegroundColor Green

# Cleanup temporary build debris
Remove-Item -Recurse -Force $BuildDir

# Generate Environment Helper with Clean Paths
$libuvInstallDir = $libuvInstallDir.TrimEnd('\')
$libuvIncludeDir = Join-Path $libuvInstallDir "include"
$libuvLibDir = Join-Path $libuvInstallDir "lib"
$libuvBinPath = Join-Path $libuvInstallDir "bin"
$libuvCMakePath = $libuvInstallDir.Replace('\', '/')

# --- 10. Create Environment Helper ---
Write-Host "Generating environment helper script..." -ForegroundColor Cyan
$libuvEnvScript = Join-Path $EnvironmentDir "env-libuv.ps1"
$EnvContent = @'
# LIBUV Environment Setup
$libuvroot = "VALUE_ROOT_PATH"
$libuvinclude = "VALUE_INCLUDE_PATH"
$libuvlibrary = "VALUE_LIB_PATH"
$libuvbin = "VALUE_BIN_PATH"
$libuvcmakepath = "VALUE_CMAKE_PATH"
$env:LIBUV_PATH = $libuvroot
$env:LIBUV_ROOT = $libuvroot
$env:LIBUV_BIN = $libuvbin
$env:LIBUV_INCLUDEDIR = $libuvinclude
$env:LIBUV_LIBRARYDIR = $libuvlibrary
if ($env:CMAKE_PREFIX_PATH -notlike "*$libuvcmakepath*") { $env:CMAKE_PREFIX_PATH = $libuvcmakepath + ";" + $env:CMAKE_PREFIX_PATH }
if ($env:INCLUDE -notlike "*$libuvinclude*") { $env:INCLUDE = $libuvinclude + ";" + $env:INCLUDE }
if ($env:LIB -notlike "*$libuvlibrary*") { $env:LIB = $libuvlibrary + ";" + $env:LIB }
if ($env:PATH -notlike "*$libuvbin*") { $env:PATH = $libuvbin + ";" + $env:PATH }
Write-Host "LIBUV Environment Loaded." -ForegroundColor Green
Write-Host "LIBUV_ROOT: $env:LIBUV_ROOT" -ForegroundColor Gray
'@  -replace "VALUE_ROOT_PATH", $libuvInstallDir `
    -replace "VALUE_INCLUDE_PATH", $libuvIncludeDir `
    -replace "VALUE_LIB_PATH", $libuvLibDir `
    -replace "VALUE_BIN_PATH", $libuvBinPath `
    -replace "VALUE_CMAKE_PATH", $libuvCMakePath

$EnvContent | Out-File -FilePath $libuvEnvScript -Encoding utf8
Write-Host "Created: $libuvEnvScript" -ForegroundColor Gray

# --- Return to Start ---
Pop-Location
Write-Host "Done! and returned to: $(Get-Location)" -ForegroundColor Gray
