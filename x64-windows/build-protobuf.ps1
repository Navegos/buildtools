# Copyright 2026 (C) Navegos. DevelVitorF. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
# file:x64-windows/build-protobuf.ps1

param (
    [Parameter(HelpMessage="Base workspace path", Mandatory=$false)]
    [string]$WorkspacePath = "",

    [Parameter(HelpMessage="Protobuf git repo url", Mandatory=$false)]
    [string]$GitUrl = "https://github.com/Navegos/protobuf.git",
    
    [Parameter(HelpMessage="Protobuf branch/tag (e.g. v25.1)", Mandatory=$false)]
    [string]$GitBranch = "main",

    [Parameter(HelpMessage="Path for protobuf library storage", Mandatory=$false)]
    [string]$protoInstallDir = "$env:LIBRARIES_PATH\protobuf"
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

$Source = Join-Path $RootPath "protobuf"
$BuildDirShared = Join-Path $Source "build_shared"
$BuildDirStatic = Join-Path $Source "build_static"
$RepoUrl    = $GitUrl
$Branch     = $GitBranch
$CMakeSource = Join-Path $Source "build/cmake"

# --- 7. Source Management ---
if (Test-Path $Source) {
    Write-Host "Syncing Protobuf ($Branch) at $Source..." -ForegroundColor Cyan
    Set-Location $Source
    git fetch --all
    git reset --hard "origin/$Branch"
    git pull --recurse-submodules --force
} else {
    Write-Host "Cloning Protobuf ($Branch) into $Source..." -ForegroundColor Cyan
    git clone --recurse-submodules $RepoUrl $Source -b $Branch
    Set-Location $Source
}

# --- 8. Clean Final Destination ---
if (Test-Path $protoInstallDir) {
    Write-Host "Wiping existing installation at $protoInstallDir..." -ForegroundColor Yellow
    Remove-Item $protoInstallDir -Recurse -Force -ErrorAction SilentlyContinue
}
New-Item -ItemType Directory -Path $protoInstallDir -Force -ErrorAction SilentlyContinue | Out-Null

# Ensure fresh build directory
if (Test-Path $BuildDirShared) { Remove-Item $BuildDirShared -Recurse -Force -ErrorAction SilentlyContinue }
if (Test-Path $BuildDirStatic) { Remove-Item $BuildDirStatic -Recurse -Force -ErrorAction SilentlyContinue }
New-Item -ItemType Directory -Path $BuildDirShared -Force -ErrorAction SilentlyContinue | Out-Null
New-Item -ItemType Directory -Path $BuildDirStatic -Force -ErrorAction SilentlyContinue | Out-Null

# --- Dependencies: ---
[string]$RootLibprotoInstallDir = Split-Path -Path $protoInstallDir -Parent

# Load Zlib (protobuf requirement)
if ([string]::IsNullOrWhiteSpace($env:ZLIB_LIBRARYDIR) -or -not (Test-Path (Join-Path $env:ZLIB_LIBRARYDIR "z.lib"))) {
    $zlibEnvScript = Join-Path $EnvironmentDir "env-zlib.ps1"
    if (Test-Path $zlibEnvScript) { . $zlibEnvScript } else {
        $zlibBuildScript = Join-Path $PSScriptRoot "build-zlib.ps1"
        if (Test-Path $zlibBuildScript) {
            [string]$zlibInstallDir = Join-Path $RootLibprotoInstallDir "zlib"
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

# Common CMake Flags (No tests, no examples, no docs)
$CommonCmakeArgs = @(
    "-G", "Ninja",
    "-DCMAKE_C_COMPILER=clang",
    "-DCMAKE_CXX_COMPILER=clang++",
    "-DCMAKE_BUILD_TYPE=Release",
    "-Dprotobuf_BUILD_TESTS=OFF",
    "-Dprotobuf_BUILD_EXAMPLES=OFF",
    "-Dprotobuf_BUILD_CONFORMANCE=OFF",
    "-Dprotobuf_BUILD_LIBPROTOC=ON",
    "-Dprotobuf_BUILD_LIBUPB=ON",
    "-Dprotobuf_INSTALL=ON",
    "-Dprotobuf_WITH_ZLIB=ON",
    "-Dprotobuf_ALLOW_CCACHE=ON",
    "-Dprotobuf_MSVC_STATIC_RUNTIME=OFF"
)

# --- 9. STAGE 1: Build Static Libraries ---
Write-Host "Building Protobuf Static..." -ForegroundColor Cyan
cmake $CommonCmakeArgs `
    -S "$Source" `
    -B "$BuildDirStatic" `
    -DCMAKE_INSTALL_PREFIX="$protoInstallDir" `
    -Dprotobuf_BUILD_SHARED_LIBS=OFF `
    -Dprotobuf_BUILD_PROTOBUF_BINARIES=OFF `
    -Dprotobuf_BUILD_PROTOC_BINARIES=OFF `
    -DCMAKE_C_FLAGS="-Wno-deprecated-declarations -D_CRT_SECURE_NO_WARNINGS=1" `
    -DCMAKE_CXX_FLAGS="-Wno-deprecated-declarations -D_CRT_SECURE_NO_WARNINGS=1"
    
if ($LASTEXITCODE -ne 0) { Write-Error "protobuf CMake Static configuration failed."; Pop-Location; return }

cmake --build "$BuildDirStatic" --target install --config Release --parallel

if ($LASTEXITCODE -ne 0) { Write-Error "protobuf Static Build failed with exit code $LASTEXITCODE"; Pop-Location; return }

# --- 9.5. Rename Static Libraries (Suffix 's' Only) ---
Write-Host "Applying 's' suffix to static libs..." -ForegroundColor Gray
Get-ChildItem -Path "$protoInstallDir\lib\*.lib" | ForEach-Object {
    $newName = $_.BaseName + "s" + $_.Extension
    Move-Item -Path $_.FullName -Destination (Join-Path $_.DirectoryName $newName) -Force -ErrorAction SilentlyContinue
    Write-Host "  -> $newName" -ForegroundColor DarkGray
}

# --- 10. STAGE 2: Build Shared Libraries (DLLs + Protoc) ---
Write-Host "Building Protobuf Shared & Protoc Tools..." -ForegroundColor Cyan
cmake $CommonCmakeArgs `
    -S "$Source" `
    -B "$BuildDirShared" `
    -DCMAKE_INSTALL_PREFIX="$protoInstallDir" `
    -Dprotobuf_BUILD_SHARED_LIBS=ON `
    -Dprotobuf_BUILD_PROTOBUF_BINARIES=ON `
    -Dprotobuf_BUILD_PROTOC_BINARIES=ON `
    -DCMAKE_C_FLAGS="-Wno-deprecated-declarations -D_CRT_SECURE_NO_WARNINGS=1" `
    -DCMAKE_CXX_FLAGS="-Wno-deprecated-declarations -D_CRT_SECURE_NO_WARNINGS=1"

if ($LASTEXITCODE -ne 0) { Write-Error "protobuf CMake Shared (DLL) configuration failed."; Pop-Location; return }

cmake --build "$BuildDirShared" --target install --config Release --parallel

if ($LASTEXITCODE -ne 0) { Write-Error "protobuf Shared Build failed with exit code $LASTEXITCODE"; Pop-Location; return }

Write-Host "Successfully built and installed Protobuf to $protoInstallDir" -ForegroundColor Green

# Cleanup temporary build debris
Remove-Item $BuildDirShared -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item $BuildDirStatic -Recurse -Force -ErrorAction SilentlyContinue

# Generate Environment Helper with Clean Paths
$protoInstallDir = $protoInstallDir.TrimEnd('\')
$protoIncludeDir = Join-Path $protoInstallDir "include"
$protoLibDir = Join-Path $protoInstallDir "lib"
$protoBinPath = Join-Path $protoInstallDir "bin"
$protoCMakePath = $protoInstallDir.Replace('\', '/')

# --- 11. Create Environment Helper ---
Write-Host "Generating environment helper script..." -ForegroundColor Cyan
$protoEnvScript = Join-Path $EnvironmentDir "env-protobuf.ps1"
$EnvContent = @'
# PROTOBUF Environment Setup
$protoroot = "VALUE_ROOT_PATH"
$protoinclude = "VALUE_INCLUDE_PATH"
$protolibrary = "VALUE_LIB_PATH"
$protobin = "VALUE_BIN_PATH"
$protocmakepath = "VALUE_CMAKE_PATH"
$env:PROTOBUF_PATH = $protoroot
$env:PROTOBUF_ROOT = $protoroot
$env:PROTOBUF_BIN = $protobin
$env:PROTOBUF_INCLUDEDIR = $protoinclude
$env:PROTOBUF_LIBRARYDIR = $protolibrary
if ($env:CMAKE_PREFIX_PATH -notlike "*$protocmakepath*") { $env:CMAKE_PREFIX_PATH = $protocmakepath + ";" + $env:CMAKE_PREFIX_PATH }
if ($env:INCLUDE -notlike "*$protoinclude*") { $env:INCLUDE = $protoinclude + ";" + $env:INCLUDE }
if ($env:LIB -notlike "*$protolibrary*") { $env:LIB = $protolibrary + ";" + $env:LIB }
if ($env:PATH -notlike "*$protobin*") { $env:PATH = $protobin + ";" + $env:PATH }
Write-Host "PROTOBUF Environment Loaded." -ForegroundColor Green
Write-Host "PROTOBUF_ROOT: $env:PROTOBUF_ROOT" -ForegroundColor Gray
'@  -replace "VALUE_ROOT_PATH", $protoInstallDir `
    -replace "VALUE_INCLUDE_PATH", $protoIncludeDir `
    -replace "VALUE_LIB_PATH", $protoLibDir `
    -replace "VALUE_BIN_PATH", $protoBinPath `
    -replace "VALUE_CMAKE_PATH", $protoCMakePath

$EnvContent | Out-File -FilePath $protoEnvScript -Encoding utf8
Write-Host "Created: $protoEnvScript" -ForegroundColor Gray

# --- Return to Start ---
Pop-Location
Write-Host "Done! and returned to: $(Get-Location)" -ForegroundColor Gray
