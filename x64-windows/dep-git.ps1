# Copyright 2026 (C) Navegos. DevelVitorF. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
# file:x64-windows/dep-git.ps1

param (
    [Parameter(HelpMessage="Path for git storage", Mandatory=$false)]
    [string]$gitInstallDir = "$env:LIBRARIES_PATH\git"
)

# 1. Bootstrap Environment if variables are missing
if ([string]::IsNullOrWhitespace($env:ENVIRONMENT_PATH) -or -not (Test-Path $env:ENVIRONMENT_PATH) -or [string]::IsNullOrWhitespace($env:BINARIES_PATH) -or -not (Test-Path $env:BINARIES_PATH) -or [string]::IsNullOrWhitespace($env:LIBRARIES_PATH) -or -not (Test-Path $env:LIBRARIES_PATH)) {
    Write-Error "User Environment variables missing. Please run adduserpaths.ps1 -LibrariesDir 'Path\for\Libraries' BinariesDir 'Path\for\Binaries' -EnvironmentDir 'Path\for\Environment'"
    return
}

$EnvironmentDir = "$env:ENVIRONMENT_PATH"

$gitCheck = Get-Command git -ErrorAction SilentlyContinue
$gitBinPath = Join-Path $gitInstallDir "cmd"

if ($gitCheck) {
    Write-Host "Git is already installed at: $($gitCheck.Source)" -ForegroundColor Green
    Write-Host "Git Version: $(git --version)" -ForegroundColor Gray

    # 1. Locate the bin folder and the root folder
    $gitBinPath = Split-Path -Path $gitCheck.Source -Parent
    $gitInstallDir = Split-Path -Path $gitBinPath -Parent
} else {
    Write-Host "Git not found. Starting installation..." -ForegroundColor Yellow

    if (!(Test-Path $gitInstallDir)) { 
        New-Item -Path $gitInstallDir -ItemType Directory -Force | Out-Null 
    }

    # 4. Get latest Portable Release from GitHub
    $repo = "git-for-windows/git"
    try {
        Write-Host "Fetching latest release data for Git..." -ForegroundColor Gray
        $latestRelease = Invoke-RestMethod -Uri "https://api.github.com/repos/$repo/releases/latest"
        
        # We look for the 64-bit Portable "Thumbdrive" zip
        $asset = $latestRelease.assets | Where-Object { $_.name -match "PortableGit.*64-bit\.zip$" } | Select-Object -First 1
        
        if ($null -eq $asset) { throw "Could not find a valid 64-bit portable zip asset." }

        $zipFile = Join-Path $env:TEMP $asset.name

        Write-Host "Downloading $($asset.name)..." -ForegroundColor Cyan
        Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $zipFile

        # 5. Extract (Git has many files, so we extract directly to destination)
        Write-Host "Extracting Git (this may take a minute)..." -ForegroundColor Cyan
        Expand-Archive -Path $zipFile -DestinationPath $gitInstallDir -Force
        
        Remove-Item $zipFile -Force
        Write-Host "Git Extraction Complete!" -ForegroundColor DarkGreen
    }
    catch {
        Write-Error "Failed to install Git: $($_.Exception.Message)"
        return # Stop execution on failure
    }
}

# --- Finalize Environment Helper ---
# Portable Git uses the \cmd folder for the primary git.exe to avoid path conflicts with its internal \bin (sh.exe)
if (Test-Path (Join-Path $gitBinPath "git.exe")) {
    # Create Environment Helper
    Write-Host "Generating environment helper script..." -ForegroundColor Cyan
    $gitEnvScript = Join-Path $EnvironmentDir "env-git.ps1"
    
    # Generate Environment Helper with Clean Paths
    $gitBinPath = $gitBinPath.TrimEnd('\')
    $gitInstallDir = $gitInstallDir.TrimEnd('\')

    # Using a literal here-string with -replace to avoid accidental expansion of $env:PATH during creation
    $EnvContent = @'
# GIT Environment Setup
$gitbin = "VALUE_BIN_PATH"
$gitroot = "VALUE_ROOT_PATH"
$unixTools = Join-Path $gitroot "usr\bin"
$env:GIT_PATH = $gitroot
$env:GIT_ROOT = $gitroot
$env:GIT_BIN = $gitbin
if ($env:PATH -notlike "*$gitbin*") { $env:PATH = $gitbin + ";" + $env:PATH }
if ($env:PATH -notlike "*$gitroot*") { $env:PATH = $gitroot + ";" + $env:PATH }
if ($env:PATH -notlike "*$unixTools*") { $env:PATH = $env:PATH + ";" + $unixTools }
Write-Host "GIT Environment Loaded (Bin: $gitbin)" -ForegroundColor Green
Write-Host "GIT_ROOT: $env:GIT_ROOT" -ForegroundColor Gray
'@ -replace "VALUE_BIN_PATH", $gitBinPath -replace "VALUE_ROOT_PATH", $gitInstallDir

    $EnvContent | Out-File -FilePath $gitEnvScript -Encoding utf8
    Write-Host "Created: $gitEnvScript" -ForegroundColor Gray
    
    # Update Current Session
    if (Test-Path $gitEnvScript) { . $gitEnvScript } else {
        Write-Error "git dep install finished but $gitEnvScript was not created."
        return
    }
    Write-Host "Git Version: $(git --version)" -ForegroundColor Gray

    # --- Post-Install Configuration ---
    # 1. Check for User Name
    $gitName = git config --global user.name
    if ([string]::IsNullOrWhitespace($gitName)) {
        $newName = Read-Host "Git user.name not set. Please enter your name (e.g., VitorF)"
        if (![string]::IsNullOrWhitespace($newName)) {
            git config --global user.name "$newName"
            Write-Host "  -> user.name set to: $newName" -ForegroundColor Gray
        }
    } else {
        Write-Host "  -> user.name: $gitName" -ForegroundColor DarkGray
    }

    # 2. Check for User Email
    $gitEmail = git config --global user.email
    if ([string]::IsNullOrWhitespace($gitEmail)) {
        $newEmail = Read-Host "Git user.email not set. Please enter your email"
        if (![string]::IsNullOrWhitespace($newEmail)) {
            git config --global user.email "$newEmail"
            Write-Host "  -> user.email set to: $newEmail" -ForegroundColor Gray
        }
    } else {
        Write-Host "  -> user.email: $gitEmail" -ForegroundColor DarkGray
    }
    
    # 3. Optimization: Performance and Compatibility
    Write-Host "Applying Windows-specific Git optimizations..." -ForegroundColor Gray
    
    # Ignore file permission changes (Windows doesn't use standard POSIX bits)
    git config --global core.filemode false
    
    # Convert LF to CRLF on checkout, CRLF to LF on commit (Standard Windows/Unix compatibility)
    git config --global core.autocrlf true
    
    # Enable the file system cache to speed up status checks on large repos
    git config --global core.fscache true
    
    # Allow Git to handle symbolic links (Requires Admin or Developer Mode enabled in Windows)
    git config --global core.symlinks true
    
    # Bypass the 260 character limit for file paths (Essential for deep C++ build trees)
    git config --global core.longpaths true
    
    # Disable built-in file system monitor (Usually safer to leave off unless repo is massive)
    git config --global core.fsmonitor false
    
    # Use standard merge behavior for 'git pull' (instead of automatic rebase)
    git config --global pull.rebase false
    
    # Don't remove remote-tracking branches that no longer exist on remote during every fetch
    git config --global fetch.prune false
    
    # Disable automatic stashing of local changes before a rebase starts
    git config --global rebase.autoStash false

    # 4. Verification of Unix Tools
    $shCheck = Get-Command sh -ErrorAction SilentlyContinue
    if ($shCheck) {
        Write-Host "[OK] Unix shell tools detected at: $($shCheck.Source)" -ForegroundColor Green
    }
} else {
    Write-Error "git.exe was not found in the $gitBinPath folder."
    return
}
