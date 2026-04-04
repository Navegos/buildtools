# Copyright 2026 (C) Navegos. DevelVitorF. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
# file:x64-windows/build-ninja.ps1

param (
    [Parameter(HelpMessage="Base workspace path", Mandatory=$false)]
    [string]$WorkspacePath = "",

    [Parameter(HelpMessage="ninja git repo url", Mandatory=$false)]
    [string]$GitUrl = "https://github.com/Navegos/ninja.git",
    
    [Parameter(HelpMessage="ninja git branch to sync from", Mandatory=$false)]
    [string]$GitBranch = "master",

    [Parameter(HelpMessage="Path for ninja storage", Mandatory=$false)]
    [string]$ninjaInstallDir = "$env:LIBRARIES_PATH\ninja"
)

if ([string]::IsNullOrWhitespace($env:ENVIRONMENT_PATH) -or -not (Test-Path $env:ENVIRONMENT_PATH) -or [string]::IsNullOrWhitespace($env:BINARIES_PATH) -or -not (Test-Path $env:BINARIES_PATH) -or [string]::IsNullOrWhitespace($env:LIBRARIES_PATH) -or -not (Test-Path $env:LIBRARIES_PATH)) {
    Write-Error "User Environment variables missing. With administrator privileges run adduserpaths.ps1 -LibrariesDir 'Path\for\Libraries' -BinariesDir 'Path\for\Binaries' -EnvironmentDir 'Path\for\Environment'"
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

$Source = Join-Path $RootPath "ninja"
$BuildDir   = Join-Path $Source "build_dir"  # Nested inside source
$RepoUrl    = $GitUrl
$Branch     = $GitBranch
$CMakeSource = $Source
$tag_name    = $Branch
$url        = $RepoUrl

# --- 7. Source Management ---
if (Test-Path $Source) {
    Write-Host "Syncing ninja ($Branch) at $Source..." -ForegroundColor Cyan
    Set-Location $Source
    git fetch --all
    git reset --hard "origin/$Branch"
    git pull --recurse-submodules --force
    $tagCommit = (& git rev-parse --verify HEAD).Trim()
} else {
    Write-Host "Cloning ninja ($Branch) into $Source..." -ForegroundColor Cyan
    git clone --recurse-submodules $RepoUrl $Source -b $Branch
    Set-Location $Source
    $tagCommit = (& git rev-parse --verify HEAD).Trim()
}

# --- 8. Clean & Build (Shadow Swap Logic) ---
# We use .exe extension so it remains 'executable' and detectable
$GlobalBinDir = "$env:BINARIES_PATH"
$TargetLink = Join-Path $GlobalBinDir "ninja.exe"
$ninjaBinPath = Join-Path $ninjaInstallDir "bin"

# 2. Check for existing installation
$ninjaExePath = Join-Path $ninjaInstallDir "ninja.exe"
if (-not (Test-Path $ninjaExePath)) { $ninjaExePath = Join-Path $ninjaBinPath "ninja.exe" }
$TempNinja = Join-Path (Split-Path $ninjaExePath) "ninja_old.exe"
$versionFile = Join-Path $ninjaInstallDir "version.json"

if (!(Test-Path $ninjaInstallDir)) {
    New-Item -ItemType Directory -Path $ninjaInstallDir -Force -ErrorAction SilentlyContinue | Out-Null
    New-Item -ItemType Directory -Path $ninjaBinPath -Force -ErrorAction SilentlyContinue | Out-Null
}

if (Test-Path $ninjaExePath) {
    if (Test-Path $TempNinja) { Remove-Item $TempNinja -Force -ErrorAction SilentlyContinue }

    # 1. Rename the existing binary (Windows allows this while running)
    Move-Item -Path $ninjaExePath -Destination $TempNinja -Force -ErrorAction SilentlyContinue
    Write-Host "[SWAP] Active ninja.exe -> ninja_old.exe" -ForegroundColor Yellow

    if (Test-Path $TempNinja) {
        Write-Host "Creating global symlink: $TargetLink" -ForegroundColor Cyan

        # Remove existing symlink we are creating a new one
        if (Test-Path $TargetLink) { Remove-Item $TargetLink -Force -ErrorAction SilentlyContinue }
            
        # Create the Symbolic Link
        try {
            New-Item -ItemType SymbolicLink -Path $TargetLink -Value $TempNinja -ErrorAction Stop | Out-Null
            Write-Host "[LINKED] Ninja (Global) -> $TempNinja" -ForegroundColor Green
        }
        catch {
            New-Item -ItemType HardLink -Path $TargetLink -Value $TempNinja | Out-Null
        }
            
        Write-Host "[LINKED] Ninja is now globally available via %BINARIES_PATH%" -ForegroundColor Green
    }
    else {
        Write-Error "CRITICAL: Could not find ninja.exe to symlink at $TempNinja"
        if (Test-Path $TargetLink) { 
            Write-Host "Cleaning up dead symlink at $TargetLink..." -ForegroundColor Yellow
            Remove-Item $TargetLink -Force -ErrorAction SilentlyContinue 
        }
        Pop-Location
        return
    }
}

# Ensure fresh build directory
if (Test-Path $BuildDir) { Remove-Item $BuildDir -Recurse -Force -ErrorAction SilentlyContinue }
New-Item -ItemType Directory -Path $BuildDir -Force -ErrorAction SilentlyContinue | Out-Null

Write-Host "Configuring with Clang/Ninja..." -ForegroundColor Cyan
cmake -G "Ninja" `
    -S "$CMakeSource" `
    -B "$BuildDir" `
    -DCMAKE_POLICY_DEFAULT_CMP0109=NEW `
    -DCMAKE_CXX_COMPILER="clang++" `
    -DCMAKE_INSTALL_PREFIX="$ninjaInstallDir" `
    -DCMAKE_BUILD_TYPE=Release `
    -DBUILD_TESTING=OFF `
    -DCMAKE_CXX_FLAGS="-Wno-deprecated-declarations -D_CRT_SECURE_NO_WARNINGS=1"

if ($LASTEXITCODE -ne 0) { Write-Error "ninja CMake configuration failed."; Pop-Location; return }

Write-Host "Building and Installing to $ninjaInstallDir..." -ForegroundColor Green
cmake --build "$BuildDir" --target install --config Release --parallel

if ($LASTEXITCODE -ne 0) { Write-Error "ninja Build failed with exit code $LASTEXITCODE"; Pop-Location; return }

Write-Host "Successfully built and installed ninja to $ninjaInstallDir!" -ForegroundColor Green

# Cleanup temporary build debris
Remove-Item $BuildDir -Recurse -Force -ErrorAction SilentlyContinue

# Generate Environment Helper with Clean Paths
$ninjaBinPath = $ninjaBinPath.TrimEnd('\')
$ninjaInstallDir = $ninjaInstallDir.TrimEnd('\')

# --- 9. Create Environment Helper ---
Write-Host "Generating environment helper script..." -ForegroundColor Cyan
$ninjaEnvScript = Join-Path $EnvironmentDir "env-ninja.ps1"
$EnvContent = @'
# NINJA Environment Setup
$ninjabin = "VALUE_BIN_PATH"
$ninjaroot = "VALUE_ROOT_PATH"
$env:NINJA_PATH = $ninjaroot
$env:NINJA_ROOT = $ninjaroot
$env:NINJA_BIN = $ninjabin
if ($env:PATH -notlike "*$ninjabin*") { $env:PATH = $ninjabin + ";" + $env:PATH }
Write-Host "NINJA Environment Loaded." -ForegroundColor Green
Write-Host "NINJA_ROOT: $env:NINJA_ROOT" -ForegroundColor Gray
'@ -replace "VALUE_BIN_PATH", $ninjaBinPath -replace "VALUE_ROOT_PATH", $ninjaInstallDir

$EnvContent | Out-File -FilePath $ninjaEnvScript -Encoding utf8
Write-Host "Created: $ninjaEnvScript" -ForegroundColor Gray

# Update Current Session
if (Test-Path $ninjaEnvScript) { . $ninjaEnvScript } else {
    Write-Error "ninja build install finished but $ninjaEnvScript was not created."
    return
}

# --- 10. Symlink to Global Binaries ---
$ninjaExePath = Join-Path $ninjaInstallDir "ninja.exe"
if (-not (Test-Path $ninjaExePath)) { $ninjaExePath = Join-Path $ninjaBinPath "ninja.exe" }

if (Test-Path $ninjaExePath) {
    # Ninja --version usually returns a single string like "1.12.1" or "1.12.1.git"
    $rawVersion = (& $ninjaExePath --version).Trim()
    # We extract only the numeric part (e.g., 1.12.1) so [version] can handle it
    if ($rawVersion -match '^(\d+\.\d+\.\d+)') { $localVersion = $Matches[1] } else { $localVersion = "0.0.0" }

    # Save new version state
    $versionInfo = @{
        url        = $url;
        tag_name   = $tag_name;
        commit     = $tagCommit;
        version    = $localVersion;
        rawversion = $rawVersion;
        date       = (Get-Date).ToString("yyyy-MM-dd");
        updated_at = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssZ");
        type       = "source_build";
    }
    $versionInfo | ConvertTo-Json | Out-File -FilePath $versionFile -Encoding utf8 -Force

    Write-Host "Creating global symlink: $TargetLink" -ForegroundColor Cyan

    # Remove existing symlink we are creating a new one
    if (Test-Path $TargetLink) { Remove-Item $TargetLink -Force -ErrorAction SilentlyContinue }
    
    # Create the Symbolic Link
    try {
        New-Item -ItemType SymbolicLink -Path $TargetLink -Value $ninjaExePath -ErrorAction Stop | Out-Null
        Write-Host "[LINKED] Ninja (Global) -> $ninjaExePath" -ForegroundColor Green
    } catch {
        New-Item -ItemType HardLink -Path $TargetLink -Value $ninjaExePath | Out-Null
    }
    
    Write-Host "[LINKED] Ninja is now globally available via %BINARIES_PATH%" -ForegroundColor Green
} else {
    Write-Error "CRITICAL: Could not find ninja.exe to symlink at $ninjaExePath"
    if (Test-Path $TargetLink) { 
        Write-Host "Cleaning up dead symlink at $TargetLink..." -ForegroundColor Yellow
        Remove-Item $TargetLink -Force -ErrorAction SilentlyContinue 
    }
    Pop-Location
    return
}

# --- 11. Post-Build Cleanup ---
if (Test-Path $TempNinja) {
    Write-Host "Releasing old binary..." -ForegroundColor Gray
    # Give the OS a heartbeat to release file handles
    Start-Sleep -Milliseconds 500
    Remove-Item $TempNinja -Force -ErrorAction SilentlyContinue
}

Write-Host "Ninja Version: $(& $ninjaExePath --version)" -ForegroundColor Gray

# --- Return to Start ---
Pop-Location
Write-Host "Done! and returned to: $(Get-Location)" -ForegroundColor Gray
