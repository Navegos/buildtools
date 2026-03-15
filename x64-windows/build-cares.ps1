# Copyright 2026 (C) Navegos. DevelVitorF. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
# file:x64-windows/build-cares.ps1

param (
    [Parameter(HelpMessage="Base workspace path", Mandatory=$false)]
    [string]$WorkspacePath = "",

    [Parameter(HelpMessage="c-ares git repo url", Mandatory=$false)]
    [string]$GitUrl = "https://github.com/Navegos/c-ares.git",
    
    [Parameter(HelpMessage="c-ares git branch to sync from", Mandatory=$false)]
    [string]$GitBranch = "main",

    [Parameter(HelpMessage="Path for c-ares library storage", Mandatory=$false)]
    [string]$caresInstallDir = "$env:LIBRARIES_PATH\cares"
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

$Source = Join-Path $RootPath "cares"
$BuildDirShared = Join-Path $Source "build_shared"
$BuildDirStatic = Join-Path $Source "build_static"
$RepoUrl    = $GitUrl
$Branch     = $GitBranch
$CMakeSource = $Source

# --- 7. Source Management ---
if (Test-Path $Source) {
    Write-Host "Syncing cares ($Branch) at $Source..." -ForegroundColor Cyan
    Set-Location $Source
    git fetch --all
    git reset --hard "origin/$Branch"
    git pull --recurse-submodules --force
} else {
    Write-Host "Cloning cares ($Branch) into $Source..." -ForegroundColor Cyan
    git clone --recurse-submodules $RepoUrl $Source -b $Branch
    Set-Location $Source
}

# --- 8. Clean Final Destination ---
if (Test-Path $caresInstallDir) {
    Write-Host "Wiping existing installation..." -ForegroundColor Yellow
    Remove-Item -Recurse -Force $caresInstallDir -ErrorAction SilentlyContinue
}
New-Item -ItemType Directory -Path $caresInstallDir -Force | Out-Null

# Ensure fresh build directory
if (Test-Path $BuildDirShared) { Remove-Item -Recurse -Force $BuildDirShared }
if (Test-Path $BuildDirStatic) { Remove-Item -Recurse -Force $BuildDirStatic }
New-Item -ItemType Directory -Path $BuildDirShared -Force | Out-Null
New-Item -ItemType Directory -Path $BuildDirStatic -Force | Out-Null

# Common CMake Flags 
$CommonCmakeArgs = @(
    "-G", "Ninja",
    "-DCMAKE_C_COMPILER=clang",
    "-DCMAKE_CXX_COMPILER=clang++",
    "-DCMAKE_BUILD_TYPE=Release",
    "-DCARES_THREADS=ON",
    "-DCARES_BUILD_TESTS=OFF",
    "-DCARES_BUILD_CONTAINER_TESTS=OFF",
    "-DCARES_BUILD_TOOLS=OFF"
)

# --- 9. STAGE 1: Build Static Libraries ---
Write-Host "Building Static (caress.lib)..." -ForegroundColor Cyan
cmake $CommonCmakeArgs `
    -S "$CMakeSource" `
    -B "$BuildDirStatic" `
    -DCMAKE_INSTALL_PREFIX="$caresInstallDir" `
    -DCARES_SHARED=OFF `
    -DCARES_STATIC=ON `
    -DCMAKE_C_FLAGS="-Wno-deprecated-declarations -D_CRT_SECURE_NO_WARNINGS=1" `
    -DCMAKE_CXX_FLAGS="-Wno-deprecated-declarations -D_CRT_SECURE_NO_WARNINGS=1"
    
if ($LASTEXITCODE -ne 0) { Write-Error "c-ares CMake Static (caress.lib) configuration failed."; Pop-Location; return }

cmake --build "$BuildDirStatic" --target install --config Release --parallel

if ($LASTEXITCODE -ne 0) { Write-Error "c-ares Static Build failed with exit code $LASTEXITCODE"; Pop-Location; return }

# Rename static lib to caress.lib to avoid collision
$StaticLibPath = Join-Path $caresInstallDir "lib/cares.lib"
$NewStaticName = Join-Path $caresInstallDir "lib/caress.lib"
if (Test-Path $StaticLibPath) {
    Move-Item -Path $StaticLibPath -Destination $NewStaticName -Force
    Write-Host "Static library renamed to caress.lib" -ForegroundColor Gray
}

# --- 10. STAGE 2: Build Shared Libraries ---
Write-Host "Building Shared (DLL)..." -ForegroundColor Cyan
cmake $CommonCmakeArgs `
    -S "$CMakeSource" `
    -B "$BuildDirShared" `
    -DCMAKE_INSTALL_PREFIX="$caresInstallDir" `
    -DCARES_SHARED=ON `
    -DCARES_STATIC=OFF `
    -DCMAKE_C_FLAGS="-Wno-deprecated-declarations -D_CRT_SECURE_NO_WARNINGS=1" `
    -DCMAKE_CXX_FLAGS="-Wno-deprecated-declarations -D_CRT_SECURE_NO_WARNINGS=1"
    
if ($LASTEXITCODE -ne 0) { Write-Error "c-ares CMake Shared (DLL) configuration failed."; Pop-Location; return }

cmake --build "$BuildDirShared" --target install --config Release --parallel

if ($LASTEXITCODE -ne 0) { Write-Error "c-ares Shared Build failed with exit code $LASTEXITCODE"; Pop-Location; return }

Write-Host "Successfully built and installed Dual-Build c-ares to $caresInstallDir!" -ForegroundColor Green

# Cleanup temporary build debris
Remove-Item -Recurse -Force $BuildDirShared
Remove-Item -Recurse -Force $BuildDirStatic

# Generate Environment Helper with Clean Paths
$caresInstallDir = $caresInstallDir.TrimEnd('\')
$caresIncludeDir = Join-Path $caresInstallDir "include"
$caresLibDir = Join-Path $caresInstallDir "lib"
$caresBinPath = Join-Path $caresInstallDir "bin"
$caresCMakePath = $caresInstallDir.Replace('\', '/')

# --- 11. Create Environment Helper ---
Write-Host "Generating environment helper script..." -ForegroundColor Cyan
$caresEnvScript = Join-Path $EnvironmentDir "env-cares.ps1"
$EnvContent = @'
# C-ARES Environment Setup
$caresroot = "VALUE_ROOT_PATH"
$caresinclude = "VALUE_INCLUDE_PATH"
$careslibrary = "VALUE_LIB_PATH"
$caresbin = "VALUE_BIN_PATH"
$carescmakepath = "VALUE_CMAKE_PATH"
$env:CARES_PATH = $caresroot
$env:CARES_ROOT = $caresroot
$env:CARES_BIN = $caresbin
$env:CARES_INCLUDEDIR = $caresinclude
$env:CARES_LIBRARYDIR = $careslibrary
if ($env:CMAKE_PREFIX_PATH -notlike "*$carescmakepath*") { $env:CMAKE_PREFIX_PATH = $carescmakepath + ";" + $env:CMAKE_PREFIX_PATH }
if ($env:INCLUDE -notlike "*$caresinclude*") { $env:INCLUDE = $caresinclude + ";" + $env:INCLUDE }
if ($env:LIB -notlike "*$careslibrary*") { $env:LIB = $careslibrary + ";" + $env:LIB }
if ($env:PATH -notlike "*$caresbin*") { $env:PATH = $caresbin + ";" + $env:PATH }
Write-Host "C-ARES Environment Loaded." -ForegroundColor Green
Write-Host "CARES_ROOT: $env:CARES_ROOT" -ForegroundColor Gray
'@  -replace "VALUE_ROOT_PATH", $caresInstallDir `
    -replace "VALUE_INCLUDE_PATH", $caresIncludeDir `
    -replace "VALUE_LIB_PATH", $caresLibDir `
    -replace "VALUE_BIN_PATH", $caresBinPath `
    -replace "VALUE_CMAKE_PATH", $caresCMakePath

$EnvContent | Out-File -FilePath $caresEnvScript -Encoding utf8
Write-Host "Created: $caresEnvScript" -ForegroundColor Gray

# --- Return to Start ---
Pop-Location
Write-Host "Done! and returned to: $(Get-Location)" -ForegroundColor Gray
