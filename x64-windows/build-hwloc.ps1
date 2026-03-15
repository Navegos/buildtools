# Copyright 2026 (C) Navegos. DevelVitorF. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
# file:x64-windows/build-hwloc.ps1

param (
    [Parameter(HelpMessage="Base workspace path", Mandatory=$false)]
    [string]$WorkspacePath = "",

    [Parameter(HelpMessage="hwloc git repo url", Mandatory=$false)]
    [string]$GitUrl = "https://github.com/Navegos/hwloc.git",
    
    [Parameter(HelpMessage="hwloc git branch to sync from", Mandatory=$false)]
    [string]$GitBranch = "master",

    [Parameter(HelpMessage="Path for hwloc library storage", Mandatory=$false)]
    [string]$hwlocInstallDir = "$env:LIBRARIES_PATH\hwloc"
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

$Source = Join-Path $RootPath "hwloc"
$BuildDir   = Join-Path $Source "build_dir"  # Nested inside source
$RepoUrl    = $GitUrl
$Branch     = $GitBranch
$CMakeSource = Join-Path $Source "contrib/windows-cmake"

# --- 7. Source Management ---
if (Test-Path $Source) {
    Write-Host "Syncing hwloc ($Branch) at $Source..." -ForegroundColor Cyan
    Set-Location $Source
    git fetch --all
    git reset --hard "origin/$Branch"
    git pull --recurse-submodules --force
} else {
    Write-Host "Cloning hwloc ($Branch) into $Source..." -ForegroundColor Cyan
    git clone --recurse-submodules $RepoUrl $Source -b $Branch
    Set-Location $Source
}

# --- 8. Clean & Build ---
if (Test-Path $hwlocInstallDir) {
    Write-Host "Wiping existing installation at $hwlocInstallDir..." -ForegroundColor Yellow
    Remove-Item -Recurse -Force $hwlocInstallDir -ErrorAction SilentlyContinue
}
New-Item -ItemType Directory -Path $hwlocInstallDir -Force | Out-Null

# Ensure fresh build directory
if (Test-Path $BuildDir) { Remove-Item -Recurse -Force $BuildDir }
New-Item -ItemType Directory -Path $BuildDir -Force | Out-Null

# --- Dependencies: ---
[string]$RoothwlocInstallDir = Split-Path -Path $hwlocInstallDir -Parent

# Load libxml2 requirement
if ([string]::IsNullOrWhiteSpace($env:LIBXML2_LIBRARYDIR) -or -not (Test-Path (Join-Path $env:LIBXML2_LIBRARYDIR "libxml2.lib"))) {
    $libxml2EnvScript = Join-Path $EnvironmentDir "env-libxml2.ps1"
    if (Test-Path $libxml2EnvScript) { . $libxml2EnvScript } else {
        $libxml2BuildScript = Join-Path $PSScriptRoot "build-libxml2.ps1"
        if (Test-Path $libxml2BuildScript) {
            [string]$libxml2InstallDir = Join-Path $RoothwlocInstallDir "libxml2"
            & $libxml2BuildScript -WorkspacePath $WorkspacePath -libxml2InstallDir $libxml2InstallDir
            if (Test-Path $libxml2EnvScript) { . $libxml2EnvScript } else {
                Write-Error "libxml2 build finished but $libxml2EnvScript was not created."
                return
            }
        } else {
            Write-Error "CRITICAL: Cannot build libxml2. libxml2 is missing and $libxml2BuildScript was not found."
            return
        }
    }
}

# Load cuda requirement
if ([string]::IsNullOrWhitespace($env:CUDA_PATH) -or -not (Test-Path (Join-Path $env:CUDA_PATH "bin\nvcc.exe"))) {
    $cudaEnvScript = Join-Path $EnvironmentDir "env-cuda.ps1"
    if (Test-Path $cudaEnvScript) { . $cudaEnvScript } else {
        $depcudaEnvScript = Join-Path $PSScriptRoot "dep-cuda.ps1"
        if (Test-Path $depcudaEnvScript) { . $depcudaEnvScript
        } else {
            Write-Error "CRITICAL: Cannot load cuda environment. cuda is missing and $cudaEnvScript was not found."
            return
        }
    }
}

Write-Host "Configuring with Clang/Ninja..." -ForegroundColor Cyan
cmake -G "Ninja" `
    -S "$CMakeSource" `
    -B "$BuildDir" `
    -DCMAKE_C_COMPILER="clang-cl" `
    -DCMAKE_CXX_COMPILER="clang-cl" `
    -DCMAKE_INSTALL_PREFIX="$hwlocInstallDir" `
    -DCMAKE_BUILD_TYPE=Release `
    -DBUILD_SHARED_LIBS=ON `
    -DHWLOC_ENABLE_TESTING=OFF `
    -DHWLOC_ENABLE_PLUGINS=OFF `
    -DHWLOC_WITH_LIBXML2=ON `
    -DHWLOC_WITH_OPENCL=ON `
    -DHWLOC_WITH_CUDA=ON `
    -DCMAKE_C_FLAGS="-Wno-deprecated-declarations -Wno-incompatible-pointer-types -D_CRT_SECURE_NO_WARNINGS=1" `
    -DCMAKE_CXX_FLAGS="-Wno-deprecated-declarations -Wno-incompatible-pointer-types -D_CRT_SECURE_NO_WARNINGS=1"

if ($LASTEXITCODE -ne 0) { Write-Error "hwloc CMake configuration failed."; Pop-Location; return }

Write-Host "Building and Installing to $hwlocInstallDir..." -ForegroundColor Green
cmake --build "$BuildDir" --target install --config Release --parallel

if ($LASTEXITCODE -ne 0) { Write-Error "hwloc Build failed with exit code $LASTEXITCODE"; Pop-Location; return }

Write-Host "Successfully built and installed hwloc to $hwlocInstallDir!" -ForegroundColor Green

# Cleanup temporary build debris
Remove-Item -Recurse -Force $BuildDir

# Generate Environment Helper with Clean Paths
$hwlocInstallDir = $hwlocInstallDir.TrimEnd('\')
$hwlocIncludeDir = Join-Path $hwlocInstallDir "include"
$hwlocLibDir = Join-Path $hwlocInstallDir "lib"
$hwlocBinPath = Join-Path $hwlocInstallDir "bin"
$hwlocCMakePath = $hwlocInstallDir.Replace('\', '/')

# --- 8.5 Deploy Dependencies ---
$libxml2Dll = Join-Path $env:LIBXML2_PATH "bin\libxml2.dll"

if (Test-Path $libxml2Dll) {
    Write-Host "Deploying libxml2.dll to hwloc bin..." -ForegroundColor Cyan
    Copy-Item -Path $libxml2Dll -Destination $hwlocBinPath -Force
} else {
    Write-Warning "Could not find libxml2.dll at $libxml2Dll. You may need to add its bin folder to PATH manually."
}

# --- 9. Create Environment Helper ---
Write-Host "Generating environment helper script..." -ForegroundColor Cyan
$hwlocEnvScript = Join-Path $EnvironmentDir "env-hwloc.ps1"
$EnvContent = @'
# HWLOC Environment Setup
$hwlocroot = "VALUE_ROOT_PATH"
$hwlocinclude = "VALUE_INCLUDE_PATH"
$hwloclibrary = "VALUE_LIB_PATH"
$hwlocbin = "VALUE_BIN_PATH"
$hwloccmakepath = "VALUE_CMAKE_PATH"
$env:HWLOC_PATH = $hwlocroot
$env:HWLOC_ROOT = $hwlocroot
$env:HWLOC_BIN = $hwlocbin
$env:HWLOC_INCLUDEDIR = $hwlocinclude
$env:HWLOC_LIBRARYDIR = $hwloclibrary
if ($env:CMAKE_PREFIX_PATH -notlike "*$hwloccmakepath*") { $env:CMAKE_PREFIX_PATH = $hwloccmakepath + ";" + $env:CMAKE_PREFIX_PATH }
if ($env:INCLUDE -notlike "*$hwlocinclude*") { $env:INCLUDE = $hwlocinclude + ";" + $env:INCLUDE }
if ($env:LIB -notlike "*$hwloclibrary*") { $env:LIB = $hwloclibrary + ";" + $env:LIB }
if ($env:PATH -notlike "*$hwlocbin*") { $env:PATH = $hwlocbin + ";" + $env:PATH }
Write-Host "HWLOC Environment Loaded." -ForegroundColor Green
Write-Host "HWLOC_ROOT: $env:HWLOC_ROOT" -ForegroundColor Gray
'@  -replace "VALUE_ROOT_PATH", $hwlocInstallDir `
    -replace "VALUE_INCLUDE_PATH", $hwlocIncludeDir `
    -replace "VALUE_LIB_PATH", $hwlocLibDir `
    -replace "VALUE_BIN_PATH", $hwlocBinPath `
    -replace "VALUE_CMAKE_PATH", $hwlocCMakePath

$EnvContent | Out-File -FilePath $hwlocEnvScript -Encoding utf8
Write-Host "Created: $hwlocEnvScript" -ForegroundColor Gray

# --- Return to Start ---
Pop-Location
Write-Host "Done! and returned to: $(Get-Location)" -ForegroundColor Gray
