# Copyright 2026 (C) Navegos. DevelVitorF. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
# file:x64-windows/build-boost.ps1

param (
    [Parameter(HelpMessage="Base workspace path", Mandatory=$false)]
    [string]$WorkspacePath = "",

    [Parameter(HelpMessage="Boost git repo url", Mandatory=$false)]
    [string]$GitUrl = "https://github.com/boostorg/boost.git",
    
    [Parameter(HelpMessage="Boost branch/tag (e.g. boost-1.84.0)", Mandatory=$false)]
    [string]$GitBranch = "master",

    [Parameter(HelpMessage="Path for boost library storage", Mandatory=$false)]
    [string]$boostInstallDir = "$env:LIBRARIES_PATH\boost"
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

# --- 2. Path Resolution ---
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

Push-Location $RootPath

$Source = Join-Path $RootPath "boost"
$BuildDirShared = Join-Path $Source "build_shared"
$BuildDirStatic = Join-Path $Source "build_static"
$StageDir   = Join-Path $Source "stage_dir"
$RepoUrl    = $GitUrl
$Branch     = $GitBranch
$Cores      = [int]$env:NUMBER_OF_PROCESSORS / 2

# --- 3. Source Management ---
if (Test-Path $Source) {
    Write-Host "Syncing Boost ($Branch) at $Source..." -ForegroundColor Cyan
    Set-Location $Source
    git fetch --all
    git reset --hard "origin/$Branch"
    git pull --recurse-submodules --force
} else {
    Write-Host "Cloning Boost ($Branch)..." -ForegroundColor Cyan
    git clone --recursive $RepoUrl $Source -b $Branch
    Set-Location $Source
}

# --- 4. Bootstrap B2 ---
$bootstrapPath = Join-Path $Source "bootstrap.bat"
Write-Host "Bootstrapping Boost Build Engine..." -ForegroundColor Yellow
cmd /c $bootstrapPath

$b2Path = Join-Path $Source "b2.exe"
if (!(Test-Path $b2Path)) {
    Write-Error "Boost bootstrap failed. b2.exe not found."
    Pop-Location; return
}

# --- 5. Clean Final Destination ---
if (Test-Path $boostInstallDir) {
    Write-Host "Wiping existing installation..." -ForegroundColor Yellow
    Remove-Item $boostInstallDir -Recurse -Force -ErrorAction SilentlyContinue
}
New-Item -ItemType Directory -Path $boostInstallDir -Force -ErrorAction SilentlyContinue | Out-Null

# Ensure fresh build directory
if (Test-Path $BuildDirShared) { Remove-Item $BuildDirShared -Recurse -Force -ErrorAction SilentlyContinue }
if (Test-Path $BuildDirStatic) { Remove-Item $BuildDirStatic -Recurse -Force -ErrorAction SilentlyContinue }
if (Test-Path $StageDir) { Remove-Item $StageDir -Recurse -Force -ErrorAction SilentlyContinue }
New-Item -ItemType Directory -Path $BuildDirShared -Force -ErrorAction SilentlyContinue | Out-Null
New-Item -ItemType Directory -Path $BuildDirStatic -Force -ErrorAction SilentlyContinue | Out-Null
New-Item -ItemType Directory -Path $StageDir -Force -ErrorAction SilentlyContinue | Out-Null

# --- 6. Build Execution (Navegos Dual-Build) ---
# Note: Using address-model=64 for Win64
$CommonArgs = "-j$Cores", "address-model=64", "architecture=x86", "threading=multi", "runtime-link=shared", "--build-type=minimal", "stage", "install"

# STAGE 1: Static Libraries (staged to stage/lib)
Write-Host "Building Boost Static Libraries..." -ForegroundColor Cyan
cmd /c $b2Path $CommonArgs toolset=msvc link=static --build-dir=$BuildDirStatic --stagedir="$StageDir" --prefix="$boostInstallDir"
if ($LASTEXITCODE -ne 0) { Write-Error "boost Static Build failed with exit code $LASTEXITCODE"; Pop-Location; return }

# STAGE 2: Shared Libraries (DLLs)
Write-Host "Building Boost Shared Libraries (DLLs)..." -ForegroundColor Cyan
cmd /c $b2Path $CommonArgs toolset=msvc link=shared --build-dir=$BuildDirShared --stagedir="$StageDir" --prefix="$boostInstallDir"
if ($LASTEXITCODE -ne 0) { Write-Error "boost Shared Build failed with exit code $LASTEXITCODE"; Pop-Location; return }

Write-Host "Successfully built and installed Dual-Build boost to $boostInstallDir!" -ForegroundColor Green

# --- 6.5. Post-Build: Migrate DLLs to \bin ---
# Generate Environment Helper with Clean Paths
$boostInstallDir = $boostInstallDir.TrimEnd('\')
$boostIncludeDir = Join-Path $boostInstallDir "include"
$boostLibDir = Join-Path $boostInstallDir "lib"
$boostBinPath = Join-Path $boostInstallDir "bin"
$boostCMakePath  = $boostInstallDir.Replace('\', '/')

if (!(Test-Path $boostBinPath)) { New-Item -ItemType Directory -Path $boostBinPath -Force -ErrorAction SilentlyContinue | Out-Null }

Write-Host "Migrating Boost DLLs from \lib to \bin..." -ForegroundColor Cyan
$dlls = Get-ChildItem -Path $boostLibDir -Filter "*.dll"
$pdbs = Get-ChildItem -Path $boostLibDir -Filter "*.pdb"

if ($dlls.Count -gt 0) {
    foreach ($dll in $dlls) {
        Move-Item -Path $dll.FullName -Destination $boostBinPath -Force -ErrorAction SilentlyContinue
    }
} else {
    Write-Host "No DLLs found in \lib. They may already be in \bin or build failed." -ForegroundColor Yellow
}

if ($pdbs.Count -gt 0) {
    foreach ($pdb in $pdbs) {
        Move-Item -Path $pdb.FullName -Destination $boostBinPath -Force -ErrorAction SilentlyContinue
    }
} else {
    Write-Host "No PDBs found in \lib. They may already be in \bin or build failed." -ForegroundColor Yellow
}

# Cleanup temporary build debris
Remove-Item $BuildDirShared -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item $BuildDirStatic -Recurse -Force -ErrorAction SilentlyContinue

# --- 7. Create Environment Helper ---
Write-Host "Generating environment helper script..." -ForegroundColor Cyan
$boostEnvScript = Join-Path $EnvironmentDir "env-boost.ps1"
$EnvContent = @'
# Boost Environment Setup
$boostroot = "VALUE_ROOT_PATH"
$boostinclude = "VALUE_INCLUDE_PATH"
$boostlibrary = "VALUE_LIB_PATH"
$boostbin = "VALUE_BIN_PATH"
$boostcmakepath = "VALUE_CMAKE_PATH"
$env:BOOST_PATH = $boostroot
$env:BOOST_ROOT = $boostroot
$env:BOOST_BIN = $boostbin
$env:BOOST_INCLUDEDIR = $boostinclude
$env:BOOST_LIBRARYDIR = $boostlibrary
if ($env:CMAKE_PREFIX_PATH -notlike "*$boostcmakepath*") { $env:CMAKE_PREFIX_PATH = $boostcmakepath + ";" + $env:CMAKE_PREFIX_PATH }
if ($env:INCLUDE -notlike "*$boostinclude*") { $env:INCLUDE = $boostinclude + ";" + $env:INCLUDE }
if ($env:LIB -notlike "*$boostlibrary*") { $env:LIB = $boostlibrary + ";" + $env:LIB }
if ($env:PATH -notlike "*$boostbin*") { $env:PATH = $boostbin + ";" + $env:PATH }
Write-Host "Boost Environment Loaded." -ForegroundColor Green
'@  -replace "VALUE_ROOT_PATH", $boostInstallDir `
    -replace "VALUE_INCLUDE_PATH", $boostIncludeDir `
    -replace "VALUE_LIB_PATH", $boostLibDir `
    -replace "VALUE_BIN_PATH", $boostBinPath `
    -replace "VALUE_CMAKE_PATH", $boostCMakePath

$EnvContent | Out-File -FilePath $boostEnvScript -Encoding utf8
Write-Host "Created: $boostEnvScript" -ForegroundColor Gray

# --- Return to Start ---
Pop-Location
Write-Host "Done! and returned to: $(Get-Location)" -ForegroundColor Gray
