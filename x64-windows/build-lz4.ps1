# Copyright 2026 (C) Navegos. DevelVitorF. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
# file:x64-windows/build-lz4.ps1

param (
    [Parameter(HelpMessage="Base workspace path", Mandatory=$false)]
    [string]$WorkspacePath = "",

    [Parameter(HelpMessage="lz4 git repo url", Mandatory=$false)]
    [string]$GitUrl = "https://github.com/Navegos/lz4.git",
    
    [Parameter(HelpMessage="lz4 git branch to sync from", Mandatory=$false)]
    [string]$GitBranch = "dev",

    [Parameter(HelpMessage="Path for lz4 library storage", Mandatory=$false)]
    [string]$lz4InstallDir = "$env:LIBRARIES_PATH\lz4"
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

$Source = Join-Path $RootPath "lz4"
$BuildDirShared = Join-Path $Source "build_shared"
$BuildDirStatic = Join-Path $Source "build_static"
$RepoUrl    = $GitUrl
$Branch     = $GitBranch
$CMakeSource = Join-Path $Source "build/cmake"

# --- 7. Source Management ---
if (Test-Path $Source) {
    Write-Host "Syncing lz4 ($Branch) at $Source..." -ForegroundColor Cyan
    Set-Location $Source
    git fetch --all
    git reset --hard "origin/$Branch"
    git pull --recurse-submodules --force
} else {
    Write-Host "Cloning lz4 ($Branch) into $Source..." -ForegroundColor Cyan
    git clone --recurse-submodules $RepoUrl $Source -b $Branch
    Set-Location $Source
}

# --- 8. Clean Final Destination ---
if (Test-Path $lz4InstallDir) {
    Write-Host "Wiping existing installation..." -ForegroundColor Yellow
    Remove-Item -Recurse -Force $lz4InstallDir -ErrorAction SilentlyContinue
}
New-Item -ItemType Directory -Path $lz4InstallDir -Force | Out-Null

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
    "-DLZ4_BUILD_CLI=OFF",
    "-DLZ4_BUNDLED_MODE=OFF"
)

# --- 9. STAGE 1: Build Static Libraries ---
Write-Host "Building Static (lz4s.lib)..." -ForegroundColor Cyan
cmake $CommonCmakeArgs `
    -S "$CMakeSource" `
    -B "$BuildDirStatic" `
    -DCMAKE_INSTALL_PREFIX="$lz4InstallDir" `
    -DBUILD_SHARED_LIBS=OFF `
    -DBUILD_STATIC_LIBS=ON `
    -DCMAKE_C_FLAGS="-Wno-deprecated-declarations -D_CRT_SECURE_NO_WARNINGS=1" `
    -DCMAKE_CXX_FLAGS="-Wno-deprecated-declarations -D_CRT_SECURE_NO_WARNINGS=1"
    
if ($LASTEXITCODE -ne 0) { Write-Error "lz4 CMake Static (lz4s.lib) configuration failed."; Pop-Location; return }

cmake --build "$BuildDirStatic" --target install --config Release --parallel

if ($LASTEXITCODE -ne 0) { Write-Error "lz4 Static Build failed with exit code $LASTEXITCODE"; Pop-Location; return }

# Rename static lib to lz4s.lib to avoid collision
$StaticLibPath = Join-Path $lz4InstallDir "lib/lz4.lib"
$NewStaticName = Join-Path $lz4InstallDir "lib/lz4s.lib"
if (Test-Path $StaticLibPath) {
    Move-Item -Path $StaticLibPath -Destination $NewStaticName -Force
    Write-Host "Static library renamed to lz4s.lib" -ForegroundColor Gray
}

# --- 10. STAGE 2: Build Shared Libraries ---
Write-Host "Building Shared (DLL)..." -ForegroundColor Cyan
cmake $CommonCmakeArgs `
    -S "$CMakeSource" `
    -B "$BuildDirShared" `
    -DCMAKE_INSTALL_PREFIX="$lz4InstallDir" `
    -DBUILD_SHARED_LIBS=ON `
    -DBUILD_STATIC_LIBS=OFF `
    -DCMAKE_C_FLAGS="-Wno-deprecated-declarations -D_CRT_SECURE_NO_WARNINGS=1" `
    -DCMAKE_CXX_FLAGS="-Wno-deprecated-declarations -D_CRT_SECURE_NO_WARNINGS=1"
    
if ($LASTEXITCODE -ne 0) { Write-Error "lz4 CMake Shared (DLL) configuration failed."; Pop-Location; return }

cmake --build "$BuildDirShared" --target install --config Release --parallel

if ($LASTEXITCODE -ne 0) { Write-Error "lz4 Shared Build failed with exit code $LASTEXITCODE"; Pop-Location; return }

Write-Host "Successfully built and installed Dual-Build lz4 to $lz4InstallDir!" -ForegroundColor Green

# Cleanup temporary build debris
Remove-Item -Recurse -Force $BuildDirShared
Remove-Item -Recurse -Force $BuildDirStatic

# Generate Environment Helper with Clean Paths
$lz4InstallDir = $lz4InstallDir.TrimEnd('\')
$lz4IncludeDir = Join-Path $lz4InstallDir "include"
$lz4LibDir = Join-Path $lz4InstallDir "lib"
$lz4BinPath = Join-Path $lz4InstallDir "bin"
$lz4CMakePath = $lz4InstallDir.Replace('\', '/')

# --- 11. Create Environment Helper ---
Write-Host "Generating environment helper script..." -ForegroundColor Cyan
$lz4EnvScript = Join-Path $EnvironmentDir "env-lz4.ps1"
$EnvContent = @'
# LZ4 Environment Setup
$lz4root = "VALUE_ROOT_PATH"
$lz4include = "VALUE_INCLUDE_PATH"
$lz4library = "VALUE_LIB_PATH"
$lz4bin = "VALUE_BIN_PATH"
$lz4cmakepath = "VALUE_CMAKE_PATH"
$env:LZ4_PATH = $lz4root
$env:LZ4_ROOT = $lz4root
$env:LZ4_BIN = $lz4bin
$env:LZ4_INCLUDEDIR = $lz4include
$env:LZ4_LIBRARYDIR = $lz4library
if ($env:CMAKE_PREFIX_PATH -notlike "*$lz4cmakepath*") { $env:CMAKE_PREFIX_PATH = $lz4cmakepath + ";" + $env:CMAKE_PREFIX_PATH }
if ($env:INCLUDE -notlike "*$lz4include*") { $env:INCLUDE = $lz4include + ";" + $env:INCLUDE }
if ($env:LIB -notlike "*$lz4library*") { $env:LIB = $lz4library + ";" + $env:LIB }
if ($env:PATH -notlike "*$lz4bin*") { $env:PATH = $lz4bin + ";" + $env:PATH }
Write-Host "LZ4 Environment Loaded." -ForegroundColor Green
Write-Host "LZ4_ROOT: $env:LZ4_ROOT" -ForegroundColor Gray
'@  -replace "VALUE_ROOT_PATH", $lz4InstallDir `
    -replace "VALUE_INCLUDE_PATH", $lz4IncludeDir `
    -replace "VALUE_LIB_PATH", $lz4LibDir `
    -replace "VALUE_BIN_PATH", $lz4BinPath `
    -replace "VALUE_CMAKE_PATH", $lz4CMakePath

$EnvContent | Out-File -FilePath $lz4EnvScript -Encoding utf8
Write-Host "Created: $lz4EnvScript" -ForegroundColor Gray

# --- Return to Start ---
Pop-Location
Write-Host "Done! and returned to: $(Get-Location)" -ForegroundColor Gray
