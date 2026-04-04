# Copyright 2026 (C) Navegos. DevelVitorF. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
# file:x64-windows/build-lzma.ps1

param (
    [Parameter(HelpMessage="Base workspace path", Mandatory=$false)]
    [string]$WorkspacePath = "",

    [Parameter(HelpMessage="lzma (xz) git repo url", Mandatory=$false)]
    [string]$GitUrl = "https://github.com/Navegos/xz.git",
    
    [Parameter(HelpMessage="lzma git branch to sync from", Mandatory=$false)]
    [string]$GitBranch = "VitorEAFeliciano-patch-1",

    [Parameter(HelpMessage="Path for lzma library storage", Mandatory=$false)]
    [string]$lzmaInstallDir = "$env:LIBRARIES_PATH\lzma"
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

$Source = Join-Path $RootPath "lzma"
$BuildDirShared = Join-Path $Source "build_shared"
$BuildDirStatic = Join-Path $Source "build_static"
$RepoUrl    = $GitUrl
$Branch     = $GitBranch
$CMakeSource = $Source

# --- 7. Source Management ---
if (Test-Path $Source) {
    Write-Host "Syncing LZMA ($Branch) at $Source..." -ForegroundColor Cyan
    Set-Location $Source
    git fetch --all
    git reset --hard "origin/$Branch"
    git pull --recurse-submodules --force
} else {
    Write-Host "Cloning LZMA ($Branch) into $Source..." -ForegroundColor Cyan
    git clone --recurse-submodules $RepoUrl $Source -b $Branch
    Set-Location $Source
}

# --- 8. Clean Final Destination ---
if (Test-Path $lzmaInstallDir) {
    Write-Host "Wiping existing installation..." -ForegroundColor Yellow
    Remove-Item $lzmaInstallDir -Recurse -Force -ErrorAction SilentlyContinue
}
New-Item -ItemType Directory -Path $lzmaInstallDir -Force -ErrorAction SilentlyContinue | Out-Null

# Ensure fresh build directory
if (Test-Path $BuildDirShared) { Remove-Item $BuildDirShared -Recurse -Force -ErrorAction SilentlyContinue }
if (Test-Path $BuildDirStatic) { Remove-Item $BuildDirStatic -Recurse -Force -ErrorAction SilentlyContinue }
New-Item -ItemType Directory -Path $BuildDirShared -Force -ErrorAction SilentlyContinue | Out-Null
New-Item -ItemType Directory -Path $BuildDirStatic -Force -ErrorAction SilentlyContinue | Out-Null

# Common CMake Flags 
$CommonCmakeArgs = @(
    "-G", "Ninja",
    "-DCMAKE_C_COMPILER=clang",
    "-DCMAKE_CXX_COMPILER=clang++",
    "-DCMAKE_BUILD_TYPE=Release",
    "-DXZ_DOC=OFF",
    "-DXZ_TOOL_XZDEC=OFF",
    "-DXZ_TOOL_LZMADEC=OFF",
    "-DXZ_TOOL_LZMAINFO=OFF",
    "-DXZ_TOOL_XZ=OFF",
    "-DBUILD_TESTING=OFF"
)

# --- 9. STAGE 1: Build Static Libraries ---
Write-Host "Building LZMA Static (lzmas.lib)..." -ForegroundColor Cyan
cmake $CommonCmakeArgs `
    -S "$CMakeSource" `
    -B "$BuildDirStatic" `
    -DCMAKE_INSTALL_PREFIX="$lzmaInstallDir" `
    -DBUILD_SHARED_LIBS=OFF `
    -DXZ_THREADS="vista" `
    -DCMAKE_C_FLAGS="-Wno-deprecated-declarations -D_CRT_SECURE_NO_WARNINGS=1" `
    -DCMAKE_CXX_FLAGS="-Wno-deprecated-declarations -D_CRT_SECURE_NO_WARNINGS=1"

if ($LASTEXITCODE -ne 0) { Write-Error "lzma CMake Static (lzmas.lib) configuration failed."; Pop-Location; return }

cmake --build "$BuildDirStatic" --target install --config Release --parallel

if ($LASTEXITCODE -ne 0) { Write-Error "lzma Static Build failed with exit code $LASTEXITCODE"; Pop-Location; return }

# Rename static lib to lzmas.lib to avoid collision
$StaticLibPath = Join-Path $lzmaInstallDir "lib/lzma.lib"
$NewStaticName = Join-Path $lzmaInstallDir "lib/lzmas.lib"
if (Test-Path $StaticLibPath) {
    Move-Item -Path $StaticLibPath -Destination $NewStaticName -Force -ErrorAction SilentlyContinue
    Write-Host "Static library renamed to lzmas.lib" -ForegroundColor Gray
}

# --- 10. STAGE 2: Build Shared Libraries ---
Write-Host "Building LZMA Shared (DLL)..." -ForegroundColor Cyan
cmake $CommonCmakeArgs `
    -S "$CMakeSource" `
    -B "$BuildDirShared" `
    -DCMAKE_INSTALL_PREFIX="$lzmaInstallDir" `
    -DBUILD_SHARED_LIBS=ON `
    -DXZ_THREADS="vista" `
    -DCMAKE_C_FLAGS="-Wno-deprecated-declarations -D_CRT_SECURE_NO_WARNINGS=1" `
    -DCMAKE_CXX_FLAGS="-Wno-deprecated-declarations -D_CRT_SECURE_NO_WARNINGS=1"

if ($LASTEXITCODE -ne 0) { Write-Error "lzma CMake Shared (DLL) configuration failed."; Pop-Location; return }

cmake --build "$BuildDirShared" --target install --config Release --parallel

if ($LASTEXITCODE -ne 0) { Write-Error "lzma Shared Build failed with exit code $LASTEXITCODE"; Pop-Location; return }

Write-Host "Successfully built and installed Dual-Build lzma to $lzmaInstallDir!" -ForegroundColor Green

# Cleanup temporary build debris
Remove-Item $BuildDirShared -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item $BuildDirStatic -Recurse -Force -ErrorAction SilentlyContinue

# Generate Environment Helper with Clean Paths
$lzmaInstallDir = $lzmaInstallDir.TrimEnd('\')
$lzmaIncludeDir = Join-Path $lzmaInstallDir "include"
$lzmaLibDir = Join-Path $lzmaInstallDir "lib"
$lzmaBinPath = Join-Path $lzmaInstallDir "bin"
$lzmaCMakePath = $lzmaInstallDir.Replace('\', '/')

# --- 11. Create Environment Helper ---
Write-Host "Generating environment helper script..." -ForegroundColor Cyan
$lzmaEnvScript = Join-Path $EnvironmentDir "env-lzma.ps1"
$EnvContent = @'
# LZMA Environment Setup
$lzmaroot = "VALUE_ROOT_PATH"
$lzmainclude = "VALUE_INCLUDE_PATH"
$lzmalibrary = "VALUE_LIB_PATH"
$lzmabin = "VALUE_BIN_PATH"
$lzmacmakepath = "VALUE_CMAKE_PATH"
$env:LZMA_PATH = $lzmaroot
$env:LZMA_ROOT = $lzmaroot
$env:LZMA_BIN = $lzmabin
$env:LZMA_INCLUDEDIR = $lzmainclude
$env:LZMA_LIBRARYDIR = $lzmalibrary
if ($env:CMAKE_PREFIX_PATH -notlike "*$lzmacmakepath*") { $env:CMAKE_PREFIX_PATH = $lzmacmakepath + ";" + $env:CMAKE_PREFIX_PATH }
if ($env:INCLUDE -notlike "*$lzmainclude*") { $env:INCLUDE = $lzmainclude + ";" + $env:INCLUDE }
if ($env:LIB -notlike "*$lzmalibrary*") { $env:LIB = $lzmalibrary + ";" + $env:LIB }
if ($env:PATH -notlike "*$lzmabin*") { $env:PATH = $lzmabin + ";" + $env:PATH }
Write-Host "LZMA Environment Loaded." -ForegroundColor Green
Write-Host "LZMA_ROOT: $env:LZMA_ROOT" -ForegroundColor Gray
'@  -replace "VALUE_ROOT_PATH", $lzmaInstallDir `
    -replace "VALUE_INCLUDE_PATH", $lzmaIncludeDir `
    -replace "VALUE_LIB_PATH", $lzmaLibDir `
    -replace "VALUE_BIN_PATH", $lzmaBinPath `
    -replace "VALUE_CMAKE_PATH", $lzmaCMakePath

$EnvContent | Out-File -FilePath $lzmaEnvScript -Encoding utf8
Write-Host "Created: $lzmaEnvScript" -ForegroundColor Gray

# --- Return to Start ---
Pop-Location
Write-Host "Done! and returned to: $(Get-Location)" -ForegroundColor Gray
