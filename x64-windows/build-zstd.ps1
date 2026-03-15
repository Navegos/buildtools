# Copyright 2026 (C) Navegos. DevelVitorF. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
# file:x64-windows/build-zstd.ps1

param (
    [Parameter(HelpMessage="Base workspace path", Mandatory=$false)]
    [string]$WorkspacePath = "",

    [Parameter(HelpMessage="zstd git repo url", Mandatory=$false)]
    [string]$GitUrl = "https://github.com/Navegos/zstd.git",
    
    [Parameter(HelpMessage="zstd git branch to sync from", Mandatory=$false)]
    [string]$GitBranch = "dev",

    [Parameter(HelpMessage="Path for zstd library storage", Mandatory=$false)]
    [string]$zstdInstallDir = "$env:LIBRARIES_PATH\zstd"
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

$Source = Join-Path $RootPath "zstd"
$BuildDirShared = Join-Path $Source "build_shared"
$BuildDirStatic = Join-Path $Source "build_static"
$RepoUrl    = $GitUrl
$Branch     = $GitBranch
$CMakeSource = Join-Path $Source "build/cmake"

# --- 7. Source Management ---
if (Test-Path $Source) {
    Write-Host "Syncing zstd ($Branch) at $Source..." -ForegroundColor Cyan
    Set-Location $Source
    git fetch --all
    git reset --hard "origin/$Branch"
    git pull --recurse-submodules --force
} else {
    Write-Host "Cloning zstd ($Branch) into $Source..." -ForegroundColor Cyan
    git clone --recurse-submodules $RepoUrl $Source -b $Branch
    Set-Location $Source
}

# --- 8. Clean Final Destination ---
if (Test-Path $zstdInstallDir) {
    Write-Host "Wiping existing installation at $zstdInstallDir..." -ForegroundColor Yellow
    Remove-Item -Recurse -Force $zstdInstallDir -ErrorAction SilentlyContinue
}
New-Item -ItemType Directory -Path $zstdInstallDir -Force | Out-Null

# Ensure fresh build directory
if (Test-Path $BuildDirShared) { Remove-Item -Recurse -Force $BuildDirShared }
if (Test-Path $BuildDirStatic) { Remove-Item -Recurse -Force $BuildDirStatic }
New-Item -ItemType Directory -Path $BuildDirShared -Force | Out-Null
New-Item -ItemType Directory -Path $BuildDirStatic -Force | Out-Null

# --- Dependencies: ---
[string]$RootLibzstdInstallDir = Split-Path -Path $zstdInstallDir -Parent

# Load Lzma requirement
if ([string]::IsNullOrWhiteSpace($env:LZMA_LIBRARYDIR) -or -not (Test-Path (Join-Path $env:LZMA_LIBRARYDIR "lzma.lib"))) {
    $lzmaEnvScript = Join-Path $EnvironmentDir "env-lzma.ps1"
    if (Test-Path $lzmaEnvScript) { . $lzmaEnvScript } else {
        $lzmaBuildScript = Join-Path $PSScriptRoot "build-lzma.ps1"
        if (Test-Path $lzmaBuildScript) {
            [string]$lzmaInstallDir = Join-Path $RootLibzstdInstallDir "lzma"
            & $lzmaBuildScript -WorkspacePath $WorkspacePath -lzmaInstallDir $lzmaInstallDir
            if (Test-Path $lzmaEnvScript) { . $lzmaEnvScript } else {
                Write-Error "lzma build finished but $lzmaEnvScript was not created."
                return
            }
        } else {
            Write-Error "CRITICAL: Cannot build lzma. lzma is missing and $lzmaBuildScript was not found."
            return
        }
    }
}

# Load Lz4 requirement
if ([string]::IsNullOrWhiteSpace($env:LZ4_LIBRARYDIR) -or -not (Test-Path (Join-Path $env:LZ4_LIBRARYDIR "lz4.lib"))) {
    $lz4EnvScript = Join-Path $EnvironmentDir "env-lz4.ps1"
    if (Test-Path $lz4EnvScript) { . $lz4EnvScript } else {
        $lz4BuildScript = Join-Path $PSScriptRoot "build-lz4.ps1"
        if (Test-Path $lz4BuildScript) {
            [string]$lz4InstallDir = Join-Path $RootLibzstdInstallDir "lz4"
            & $lz4BuildScript -WorkspacePath $WorkspacePath -lz4InstallDir $lz4InstallDir
            if (Test-Path $lz4EnvScript) { . $lz4EnvScript } else {
                Write-Error "lz4 build finished but $lz4EnvScript was not created."
                return
            }
        } else {
            Write-Error "CRITICAL: Cannot build lz4. lz4 is missing and $lz4BuildScript was not found."
            return
        }
    }
}

# Load Zlib requirement
if ([string]::IsNullOrWhiteSpace($env:ZLIB_LIBRARYDIR) -or -not (Test-Path (Join-Path $env:ZLIB_LIBRARYDIR "z.lib"))) {
    $zlibEnvScript = Join-Path $EnvironmentDir "env-zlib.ps1"
    if (Test-Path $zlibEnvScript) { . $zlibEnvScript } else {
        $zlibBuildScript = Join-Path $PSScriptRoot "build-zlib.ps1"
        if (Test-Path $zlibBuildScript) {
            [string]$zlibInstallDir = Join-Path $RootLibzstdInstallDir "zlib"
            & $zlibBuildScript -WorkspacePath $WorkspacePath -zlibInstallDir $zlibInstallDir
            if (Test-Path $zlibEnvScript) { . $zlibEnvScript } else {
                Write-Error "zlib build finished but $zlibEnvScript was not created."
                return
            }
        } else {
            Write-Error "CRITICAL: Cannot build zlib. zlib is missing and $zlibBuildScript was not found."
            return
        }
    }
}

# Common CMake Flags 
$CommonCmakeArgs = @(
    "-G", "Ninja",
    "-DCMAKE_C_COMPILER=clang",
    "-DCMAKE_CXX_COMPILER=clang++",
    "-DCMAKE_BUILD_TYPE=Release",
    "-DZSTD_LEGACY_SUPPORT=ON",
    "-DZSTD_MULTITHREAD_SUPPORT=ON",
    "-DZSTD_ENABLE_CXX=ON",
    "-DZSTD_BUILD_PROGRAMS=OFF",
    "-DZSTD_BUILD_TESTS=OFF",
    "-DZSTD_BUILD_TOOLS=OFF",
    "-DZSTD_BUILD_CONTRIB=OFF",
    "-DZSTD_BUILD_EXAMPLES=OFF",
    "-DZSTD_BUILD_DOCS=OFF"
)

# --- 9. STAGE 1: Build Static Libraries ---
Write-Host "Building Static (zstds.lib)..." -ForegroundColor Cyan
cmake $CommonCmakeArgs `
    -S "$CMakeSource" `
    -B "$BuildDirStatic" `
    -DCMAKE_INSTALL_PREFIX="$zstdInstallDir" `
    -DZSTD_BUILD_SHARED=OFF `
    -DZSTD_BUILD_STATIC=ON `
    -DCMAKE_C_FLAGS="-DLZMA_API_STATIC -DLZ4_DLL_IMPORT=0 -DZLIB_STATIC -Wno-deprecated-declarations -D_CRT_SECURE_NO_WARNINGS=1" `
    -DCMAKE_CXX_FLAGS="-DLZMA_API_STATIC -DLZ4_DLL_IMPORT=0 -DZLIB_STATIC -Wno-deprecated-declarations -D_CRT_SECURE_NO_WARNINGS=1"

if ($LASTEXITCODE -ne 0) { Write-Error "zstd CMake Static (zstds.lib) configuration failed."; Pop-Location; return }

cmake --build "$BuildDirStatic" --target install --config Release --parallel

if ($LASTEXITCODE -ne 0) { Write-Error "zstd Static Build failed with exit code $LASTEXITCODE"; Pop-Location; return }

# Rename static lib to zstds.lib to avoid collision
$StaticLibPath = Join-Path $zstdInstallDir "lib/zstd.lib"
$NewStaticName = Join-Path $zstdInstallDir "lib/zstds.lib"
if (Test-Path $StaticLibPath) {
    Move-Item -Path $StaticLibPath -Destination $NewStaticName -Force
    Write-Host "Static library renamed to zstds.lib" -ForegroundColor Gray
}

# --- 10. STAGE 2: Build Shared Libraries ---
Write-Host "Building Shared (DLL)..." -ForegroundColor Cyan
cmake $CommonCmakeArgs `
    -S "$CMakeSource" `
    -B "$BuildDirShared" `
    -DCMAKE_INSTALL_PREFIX="$zstdInstallDir" `
    -DZSTD_BUILD_SHARED=ON `
    -DZSTD_BUILD_STATIC=OFF `
    -DCMAKE_C_FLAGS="-Wno-deprecated-declarations -D_CRT_SECURE_NO_WARNINGS=1" `
    -DCMAKE_CXX_FLAGS="-Wno-deprecated-declarations -D_CRT_SECURE_NO_WARNINGS=1"
    
if ($LASTEXITCODE -ne 0) { Write-Error "zstd CMake Shared (DLL) configuration failed."; Pop-Location; return }

cmake --build "$BuildDirShared" --target install --config Release --parallel

if ($LASTEXITCODE -ne 0) { Write-Error "zstd Shared Build failed with exit code $LASTEXITCODE"; Pop-Location; return }

Write-Host "Successfully built and installed zstd to $zstdInstallDir!" -ForegroundColor Green

# Cleanup temporary build debris
Remove-Item -Recurse -Force $BuildDirShared
Remove-Item -Recurse -Force $BuildDirStatic

# Generate Environment Helper with Clean Paths
$zstdInstallDir = $zstdInstallDir.TrimEnd('\')
$zstdIncludeDir = Join-Path $zstdInstallDir "include"
$zstdLibDir = Join-Path $zstdInstallDir "lib"
$zstdBinPath = Join-Path $zstdInstallDir "bin"
$zstdCMakePath = $zstdInstallDir.Replace('\', '/')

# --- 11. Create Environment Helper ---
Write-Host "Generating environment helper script..." -ForegroundColor Cyan
$zstdEnvScript = Join-Path $EnvironmentDir "env-zstd.ps1"
$EnvContent = @'
# ZSTD Environment Setup
$zstdroot = "VALUE_ROOT_PATH"
$zstdinclude = "VALUE_INCLUDE_PATH"
$zstdlibrary = "VALUE_LIB_PATH"
$zstdbin = "VALUE_BIN_PATH"
$zstdcmakepath = "VALUE_CMAKE_PATH"
$env:ZSTD_PATH = $zstdroot
$env:ZSTD_ROOT = $zstdroot
$env:ZSTD_BIN = $zstdbin
$env:ZSTD_INCLUDEDIR = $zstdinclude
$env:ZSTD_LIBRARYDIR = $zstdlibrary
if ($env:CMAKE_PREFIX_PATH -notlike "*$zstdcmakepath*") { $env:CMAKE_PREFIX_PATH = $zstdcmakepath + ";" + $env:CMAKE_PREFIX_PATH }
if ($env:INCLUDE -notlike "*$zstdinclude*") { $env:INCLUDE = $zstdinclude + ";" + $env:INCLUDE }
if ($env:LIB -notlike "*$zstdlibrary*") { $env:LIB = $zstdlibrary + ";" + $env:LIB }
if ($env:PATH -notlike "*$zstdbin*") { $env:PATH = $zstdbin + ";" + $env:PATH }
Write-Host "ZSTD Environment Loaded." -ForegroundColor Green
Write-Host "ZSTD_ROOT: $env:ZSTD_ROOT" -ForegroundColor Gray
'@  -replace "VALUE_ROOT_PATH", $zstdInstallDir `
    -replace "VALUE_INCLUDE_PATH", $zstdIncludeDir `
    -replace "VALUE_LIB_PATH", $zstdLibDir `
    -replace "VALUE_BIN_PATH", $zstdBinPath `
    -replace "VALUE_CMAKE_PATH", $zstdCMakePath

$EnvContent | Out-File -FilePath $zstdEnvScript -Encoding utf8
Write-Host "Created: $zstdEnvScript" -ForegroundColor Gray

# --- Return to Start ---
Pop-Location
Write-Host "Done! and returned to: $(Get-Location)" -ForegroundColor Gray
