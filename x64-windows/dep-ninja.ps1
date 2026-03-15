# Copyright 2026 (C) Navegos. DevelVitorF. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
# file:x64-windows/dep-ninja.ps1

param (
    [Parameter(HelpMessage="Path for ninja storage", Mandatory=$false)]
    [string]$ninjaInstallDir = "$env:LIBRARIES_PATH\ninja"
)

# 1. Bootstrap Environment if variables are missing
if ([string]::IsNullOrWhitespace($env:ENVIRONMENT_PATH) -or -not (Test-Path $env:ENVIRONMENT_PATH) -or [string]::IsNullOrWhitespace($env:BINARIES_PATH) -or -not (Test-Path $env:BINARIES_PATH) -or [string]::IsNullOrWhitespace($env:LIBRARIES_PATH) -or -not (Test-Path $env:LIBRARIES_PATH)) {
    Write-Error "User Environment variables missing. Please run adduserpaths.ps1 -LibrariesDir 'Path\for\Libraries' BinariesDir 'Path\for\Binaries' -EnvironmentDir 'Path\for\Environment'"
    return
}

$EnvironmentDir = "$env:ENVIRONMENT_PATH"

# if Symlink present delete
$GlobalBinDir = "$env:BINARIES_PATH"
$TargetLink = Join-Path $GlobalBinDir "ninja.exe"
# Remove existing we are creating a new one
if (Test-Path $TargetLink) { Remove-Item $TargetLink -Force }
$ninjaBinPath = Join-Path $ninjaInstallDir "bin"

# 2. Check for existing installation
$CurrentNinjaBin = Join-Path $ninjaInstallDir "ninja.exe"
if (-not (Test-Path $CurrentNinjaBin)) { $CurrentNinjaBin = Join-Path $ninjaBinPath "ninja.exe" }

if (Test-Path $CurrentNinjaBin) {
    Write-Host "Ninja is already installed at: $CurrentNinjaBin" -ForegroundColor Green 
    Write-Host "Version: $(ninja --version)" -ForegroundColor Gray
    
    # 1. Locate the bin folder and the root folder
    $ninjaBinPath = Split-Path -Path $CurrentNinjaBin -Parent
    $ninjaInstallDir = Split-Path -Path $ninjaBinPath -Parent
} else {
    Write-Host "Ninja not found. Starting installation..." -ForegroundColor Yellow

    if (!(Test-Path $ninjaInstallDir)) { 
        New-Item -Path $ninjaInstallDir -ItemType Directory -Force | Out-Null 
    }

    # 4. Get latest release from GitHub
    $repo = "ninja-build/ninja"
    try {
        $latestRelease = Invoke-RestMethod -Uri "https://api.github.com/repos/$repo/releases/latest"
        $asset = $latestRelease.assets | Where-Object { $_.name -match "win\.zip$" } | Select-Object -First 1
        $zipFile = Join-Path $env:TEMP $asset.name

        Write-Host "Downloading $($asset.name)..." -ForegroundColor Cyan
        Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $zipFile

        # 5. Extract and Refine Location
        Write-Host "Extracting to temporary location..." -ForegroundColor Cyan
        $tempExtractPath = Join-Path $env:TEMP "ninja_extract_$(Get-Random)"
        Expand-Archive -Path $zipFile -DestinationPath $tempExtractPath -Force
        
        # Ensure the \bin folder exists in the final destination
        if (!(Test-Path $ninjaBinPath)) { New-Item -ItemType Directory -Path $ninjaBinPath -Force | Out-Null }

        # Find ninja.exe anywhere in the zip and move it to \bin
        $ninjaExe = Get-ChildItem -Path $tempExtractPath -Filter "ninja.exe" -Recurse | Select-Object -First 1
        if ($ninjaExe) {
            Move-Item -Path $ninjaExe.FullName -Destination (Join-Path $ninjaBinPath "ninja.exe") -Force
            Write-Host "Placed ninja.exe in: $ninjaBinPath" -ForegroundColor Gray
        }

        # Cleanup extraction debris
        Remove-Item $zipFile -Force
        Remove-Item $tempExtractPath -Recurse -Force
        
        Write-Host "ninja Installation Complete!" -ForegroundColor DarkGreen
    }
    catch {
        Write-Error "Failed to install Ninja: $($_.Exception.Message)"
        return # Stop execution on failure
    }
}

# Finalize Environment Helper
if (Test-Path (Join-Path $ninjaBinPath "ninja.exe")) {
    # Create Environment Helper
    Write-Host "Generating environment helper script..." -ForegroundColor Cyan
    
    $ninjaEnvScript = Join-Path $EnvironmentDir "env-ninja.ps1"
    
    # Generate Environment Helper with Clean Paths
    $ninjaBinPath = $ninjaBinPath.TrimEnd('\')
    $ninjaInstallDir = $ninjaInstallDir.TrimEnd('\')

    # Using a literal here-string with -replace to avoid accidental expansion of $env:PATH during creation
    $EnvContent = @'
# NINJA Environment Setup
$ninjabin = "VALUE_BIN_PATH"
$ninjaroot = "VALUE_ROOT_PATH"
$env:NINJA_PATH = $ninjaroot
$env:NINJA_ROOT = $ninjaroot
$env:NINJA_BIN = $ninjabin
if ($env:PATH -notlike "*$ninjabin*") { $env:PATH = $ninjabin + ";" + $env:PATH }
Write-Host "NINJA Environment Loaded (Bin: $ninjabin)" -ForegroundColor Green
Write-Host "NINJA_ROOT: $env:NINJA_ROOT" -ForegroundColor Gray
'@ -replace "VALUE_BIN_PATH", $ninjaBinPath -replace "VALUE_ROOT_PATH", $ninjaInstallDir

    $EnvContent | Out-File -FilePath $ninjaEnvScript -Encoding utf8
    Write-Host "Created: $ninjaEnvScript" -ForegroundColor Gray
    
    # Update Current Session
    if (Test-Path $ninjaEnvScript) { . $ninjaEnvScript } else {
        Write-Error "ninja dep install finished but $ninjaEnvScript was not created."
        return
    }
    
    # --- 10. Symlink to Global Binaries ---
    if (-not (Test-Path $GlobalBinDir)) { New-Item -ItemType Directory -Path $GlobalBinDir -Force | Out-Null }

    $NinjaExeSource = Join-Path $ninjaInstallDir "ninja.exe"
    if (-not (Test-Path $NinjaExeSource)) { $NinjaExeSource = Join-Path $ninjaBinPath "ninja.exe" }

    if (Test-Path $NinjaExeSource) {
        Write-Host "Creating global symlink: $TargetLink" -ForegroundColor Cyan

        # Remove existing to avoid conflict
        if (Test-Path $TargetLink) { Remove-Item $TargetLink -Force }
        
        # Create the Symbolic Link
        try {
            New-Item -ItemType SymbolicLink -Path $TargetLink -Value $NinjaExeSource -ErrorAction Stop | Out-Null
            Write-Host "[LINKED] Ninja (Global) -> $NinjaExeSource" -ForegroundColor Green
        } catch {
            Write-Warning "Failed to create Symlink. Falling back to HardLink..."
            New-Item -ItemType HardLink -Path $TargetLink -Value $NinjaExeSource | Out-Null
        }
        
        Write-Host "[LINKED] Ninja is now globally available via %BINARIES_PATH%" -ForegroundColor Green
    } else {
        Write-Error "Could not find ninja.exe to symlink at $NinjaExeSource"
        return
    }

    Write-Host "Ninja Version: $(ninja --version)" -ForegroundColor Gray
} else {
    Write-Error "ninja.exe was not found in the $ninjaBinPath folder."
    return
}
