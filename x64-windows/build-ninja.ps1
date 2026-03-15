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

# --- 7. Source Management ---
if (Test-Path $Source) {
    Write-Host "Syncing ninja ($Branch) at $Source..." -ForegroundColor Cyan
    Set-Location $Source
    git fetch --all
    git reset --hard "origin/$Branch"
    git pull --recurse-submodules --force
} else {
    Write-Host "Cloning ninja ($Branch) into $Source..." -ForegroundColor Cyan
    git clone --recurse-submodules $RepoUrl $Source -b $Branch
    Set-Location $Source
}

# --- 8. Clean & Build (Shadow Swap Logic) ---
# We use .exe extension so it remains 'executable' and detectable
$GlobalBinDir = "$env:BINARIES_PATH"
if (-not (Test-Path $GlobalBinDir)) { New-Item -ItemType Directory -Path $GlobalBinDir -Force | Out-Null }
$TargetLink = Join-Path $GlobalBinDir "ninja.exe"
$CurrentNinjaBin = Join-Path $ninjaInstallDir "ninja.exe"
$ninjaBinPath = Join-Path $ninjaInstallDir "bin"
if (-not (Test-Path $CurrentNinjaBin)) { $CurrentNinjaBin = Join-Path $ninjaBinPath "ninja.exe" }
$TempNinja = Join-Path (Split-Path $CurrentNinjaBin) "ninja_old.exe"

if (!(Test-Path $ninjaInstallDir)) {
    New-Item -ItemType Directory -Path $ninjaInstallDir -Force | Out-Null
} else {
    if (Test-Path $CurrentNinjaBin) {
        if (Test-Path $TempNinja) { Remove-Item $TempNinja -Force }
        
        # 1. Rename the existing binary (Windows allows this while running)
        Move-Item -Path $CurrentNinjaBin -Destination $TempNinja -Force
        Write-Host "[SWAP] Active ninja.exe -> ninja_old.exe" -ForegroundColor Yellow

        if (Test-Path $TempNinja) {
            Write-Host "Creating global symlink: $TargetLink" -ForegroundColor Cyan

            # Remove existing to avoid conflict
            if (Test-Path $TargetLink) { Remove-Item $TargetLink -Force }
            
            # Create the Symbolic Link
            try {
                New-Item -ItemType SymbolicLink -Path $TargetLink -Value $TempNinja -ErrorAction Stop | Out-Null
                Write-Host "[LINKED] Ninja (Global) -> $TempNinja" -ForegroundColor Green
            } catch {
                Write-Warning "Failed to create Symlink. Falling back to HardLink..."
                New-Item -ItemType HardLink -Path $TargetLink -Value $TempNinja | Out-Null
            }
            
            Write-Host "[LINKED] Ninja is now globally available via %BINARIES_PATH%" -ForegroundColor Green
        } else {
            Write-Error "CRITICAL: Could not find ninja.exe to symlink at $TempNinja"
            if (Test-Path $TargetLink) { 
                Write-Host "Cleaning up dead symlink at $TargetLink..." -ForegroundColor Yellow
                Remove-Item $TargetLink -Force 
            }
            Pop-Location
            return
        }
    }
}

# Ensure fresh build directory
if (Test-Path $BuildDir) { Remove-Item -Recurse -Force $BuildDir }
New-Item -ItemType Directory -Path $BuildDir -Force | Out-Null

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
Remove-Item -Recurse -Force $BuildDir

# Generate Environment Helper with Clean Paths
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
$NewNinjaBin = Join-Path $ninjaInstallDir "ninja.exe"
if (-not (Test-Path $NewNinjaBin)) { $NewNinjaBin = Join-Path $ninjaBinPath "ninja.exe" }

if (Test-Path $NewNinjaBin) {
    Write-Host "Creating global symlink: $TargetLink" -ForegroundColor Cyan

    # Remove existing to avoid conflict
    if (Test-Path $TargetLink) { Remove-Item $TargetLink -Force }
    
    # Create the Symbolic Link
    try {
        New-Item -ItemType SymbolicLink -Path $TargetLink -Value $NewNinjaBin -ErrorAction Stop | Out-Null
        Write-Host "[LINKED] Ninja (Global) -> $NewNinjaBin" -ForegroundColor Green
    } catch {
        Write-Warning "Failed to create Symlink. Falling back to HardLink..."
        New-Item -ItemType HardLink -Path $TargetLink -Value $NewNinjaBin | Out-Null
    }
    
    Write-Host "[LINKED] Ninja is now globally available via %BINARIES_PATH%" -ForegroundColor Green
} else {
    Write-Error "CRITICAL: Could not find ninja.exe to symlink at $NewNinjaBin"
    if (Test-Path $TargetLink) { 
        Write-Host "Cleaning up dead symlink at $TargetLink..." -ForegroundColor Yellow
        Remove-Item $TargetLink -Force 
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

Write-Host "Ninja Version: $(ninja --version)" -ForegroundColor Gray

# --- Return to Start ---
Pop-Location
Write-Host "Done! and returned to: $(Get-Location)" -ForegroundColor Gray
