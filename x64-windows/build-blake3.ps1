# Copyright 2026 (C) Navegos. DevelVitorF. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
# file:x64-windows/build-blake3.ps1

param (
    [Parameter(HelpMessage="Base workspace path", Mandatory=$false)]
    [string]$WorkspacePath = "",

    [Parameter(HelpMessage="BLAKE3 git repo url", Mandatory=$false)]
    [string]$GitUrl = "https://github.com/Navegos/BLAKE3.git",
    
    [Parameter(HelpMessage="BLAKE3 branch/tag", Mandatory=$false)]
    [string]$GitBranch = "master",

    [Parameter(HelpMessage="Path for BLAKE3 library storage", Mandatory=$false)]
    [string]$blake3InstallDir = "$env:LIBRARIES_PATH\blake3"
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

$Source = Join-Path $RootPath "blake3"
$BuildDirShared = Join-Path $Source "build_shared"
$BuildDirStatic = Join-Path $Source "build_static"
$RepoUrl    = $GitUrl
$Branch     = $GitBranch
$CMakeSource = Join-Path $Source "c" # Note: BLAKE3 C implementation uses a 'c' subdirectory for its CMakeLists.txt

# --- 7. Source Management ---
if (Test-Path $Source) {
    Write-Host "Syncing BLAKE3 ($Branch) at $Source..." -ForegroundColor Cyan
    Set-Location $Source
    git fetch --all
    git reset --hard "origin/$Branch"
    git pull --recurse-submodules --force
} else {
    Write-Host "Cloning BLAKE3 ($Branch) into $Source..." -ForegroundColor Cyan
    git clone --recurse-submodules $RepoUrl $Source -b $Branch
    Set-Location $Source
}

# --- 8. Clean Final Destination ---
if (Test-Path $blake3InstallDir) {
    Write-Host "Wiping existing installation..." -ForegroundColor Yellow
    Remove-Item -Recurse -Force $blake3InstallDir -ErrorAction SilentlyContinue
}
New-Item -ItemType Directory -Path $blake3InstallDir -Force | Out-Null

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
    "-DBLAKE3_EXAMPLES=OFF",
    "-DBLAKE3_TESTING=OFF",
    "-DBLAKE3_NO_SSE2=OFF",
    "-DBLAKE3_NO_SSE41=OFF",
    "-DBLAKE3_NO_AVX2=OFF",
    "-DBLAKE3_USE_TBB=ON"
)

# --- 9. STAGE 1: Build Static Libraries ---
Write-Host "Building BLAKE3 Static..." -ForegroundColor Cyan
cmake $CommonCmakeArgs `
    -S "$CMakeSource" `
    -B "$BuildDirStatic" `
    -DCMAKE_INSTALL_PREFIX="$blake3InstallDir" `
    -DBUILD_SHARED_LIBS=OFF `
    -DCMAKE_C_FLAGS="-Wno-deprecated-declarations -D_CRT_SECURE_NO_WARNINGS=1" `
    -DCMAKE_CXX_FLAGS="-Wno-deprecated-declarations -D_CRT_SECURE_NO_WARNINGS=1"

if ($LASTEXITCODE -ne 0) { Write-Error "blake3 CMake Static (blake3s.lib) configuration failed."; Pop-Location; return }

cmake --build "$BuildDirStatic" --target install --config Release --parallel

if ($LASTEXITCODE -ne 0) { Write-Error "blake3 Static Build failed with exit code $LASTEXITCODE"; Pop-Location; return }

# --- 9.5. Rename Static Libraries (Suffix 's') ---
Write-Host "Applying 's' suffix to static libs..." -ForegroundColor Gray
Get-ChildItem -Path "$blake3InstallDir\lib\*.lib" | ForEach-Object {
    $newName = $_.BaseName + "s" + $_.Extension
    Move-Item -Path $_.FullName -Destination (Join-Path $_.DirectoryName $newName) -Force
    Write-Host "  -> $newName" -ForegroundColor DarkGray
}

# --- 10. STAGE 2: Build Shared Libraries ---
Write-Host "Building BLAKE3 Shared..." -ForegroundColor Cyan
cmake $CommonCmakeArgs `
    -S "$CMakeSource" `
    -B "$BuildDirShared" `
    -DCMAKE_INSTALL_PREFIX="$blake3InstallDir" `
    -DBUILD_SHARED_LIBS=ON `
    -DCMAKE_C_FLAGS="-Wno-deprecated-declarations -D_CRT_SECURE_NO_WARNINGS=1" `
    -DCMAKE_CXX_FLAGS="-Wno-deprecated-declarations -D_CRT_SECURE_NO_WARNINGS=1"

if ($LASTEXITCODE -ne 0) { Write-Error "blake3 CMake Shared (DLL) configuration failed."; Pop-Location; return }

cmake --build "$BuildDirShared" --target install --config Release --parallel

if ($LASTEXITCODE -ne 0) { Write-Error "blake3 Shared Build failed with exit code $LASTEXITCODE"; Pop-Location; return }

Write-Host "Successfully built and installed Dual-Build blake3 to $blake3InstallDir!" -ForegroundColor Green

# Cleanup temporary build debris
Remove-Item -Recurse -Force $BuildDirShared
Remove-Item -Recurse -Force $BuildDirStatic

# Generate Environment Helper with Clean Paths
$blake3InstallDir = $blake3InstallDir.TrimEnd('\')
$blake3IncludeDir = Join-Path $blake3InstallDir "include"
$blake3LibDir = Join-Path $blake3InstallDir "lib"
$blake3BinPath = Join-Path $blake3InstallDir "bin"
$blake3CMakePath = $blake3InstallDir.Replace('\', '/')

# --- 11. Create Environment Helper ---
Write-Host "Generating environment helper script..." -ForegroundColor Cyan
$blake3EnvScript = Join-Path $EnvironmentDir "env-blake3.ps1"
$EnvContent = @'
# BLAKE3 Environment Setup
$blake3root = "VALUE_ROOT_PATH"
$blake3include = "VALUE_INCLUDE_PATH"
$blake3library = "VALUE_LIB_PATH"
$blake3bin = "VALUE_BIN_PATH"
$blake3cmakepath = "VALUE_CMAKE_PATH"
$env:BLAKE3_PATH = $blake3root
$env:BLAKE3_ROOT = $blake3root
$env:BLAKE3_BIN = $blake3bin
$env:BLAKE3_INCLUDEDIR = $blake3include
$env:BLAKE3_LIBRARYDIR = $blake3library
if ($env:CMAKE_PREFIX_PATH -notlike "*$blake3cmakepath*") { $env:CMAKE_PREFIX_PATH = $blake3cmakepath + ";" + $env:CMAKE_PREFIX_PATH }
if ($env:INCLUDE -notlike "*$blake3include*") { $env:INCLUDE = $blake3include + ";" + $env:INCLUDE }
if ($env:LIB -notlike "*$blake3library*") { $env:LIB = $blake3library + ";" + $env:LIB }
if ($env:PATH -notlike "*$blake3bin*") { $env:PATH = $blake3bin + ";" + $env:PATH }
Write-Host "BLAKE3 Environment Loaded." -ForegroundColor Green
Write-Host "BLAKE3_ROOT: $env:BLAKE3_ROOT" -ForegroundColor Gray
'@  -replace "VALUE_ROOT_PATH", $blake3InstallDir `
    -replace "VALUE_INCLUDE_PATH", $blake3IncludeDir `
    -replace "VALUE_LIB_PATH", $blake3LibDir `
    -replace "VALUE_BIN_PATH", $blake3BinPath `
    -replace "VALUE_CMAKE_PATH", $blake3CMakePath

$EnvContent | Out-File -FilePath $blake3EnvScript -Encoding utf8
Write-Host "Created: $blake3EnvScript" -ForegroundColor Gray

# --- Return to Start ---
Pop-Location
Write-Host "Done! and returned to: $(Get-Location)" -ForegroundColor Gray
