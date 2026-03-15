# Copyright 2026 (C) Navegos. DevelVitorF. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
# file:x64-windows/dep-vcpkg.ps1

param (
    [Parameter(HelpMessage="Path for vcpkg storage", Mandatory=$false)]
    [string]$vcpkgInstallDir = "$env:LIBRARIES_PATH\vcpkg"
)

# 1. Bootstrap Environment if variables are missing
if ([string]::IsNullOrWhitespace($env:ENVIRONMENT_PATH) -or -not (Test-Path $env:ENVIRONMENT_PATH) -or [string]::IsNullOrWhitespace($env:BINARIES_PATH) -or -not (Test-Path $env:BINARIES_PATH) -or [string]::IsNullOrWhitespace($env:LIBRARIES_PATH) -or -not (Test-Path $env:LIBRARIES_PATH)) {
    Write-Error "User Environment variables missing. Please run adduserpaths.ps1 -LibrariesDir 'Path\for\Libraries' BinariesDir 'Path\for\Binaries' -EnvironmentDir 'Path\for\Environment'"
    return
}

$EnvironmentDir = "$env:ENVIRONMENT_PATH"

$vcpkgCheck = Get-Command vcpkg -ErrorAction SilentlyContinue
$vcpkgBinPath = $vcpkgInstallDir

if ($vcpkgCheck) {
    Write-Host "vcpkg is already installed at: $($vcpkgCheck.Source)" -ForegroundColor Green
    Write-Host "Version: $(vcpkg version)" -ForegroundColor Gray
    
    # 1. Locate the bin folder and the root folder
    $vcpkgBinPath = Split-Path -Path $vcpkgCheck.Source -Parent
    $vcpkgInstallDir = Split-Path -Path $vcpkgBinPath -Parent
} else {
    Write-Host "vcpkg not found. Starting installation..." -ForegroundColor Yellow

    if (!(Test-Path $vcpkgInstallDir)) { 
        New-Item -Path $vcpkgInstallDir -ItemType Directory -Force | Out-Null 
    }

    # 2. Get latest release from GitHub
    $repo = "microsoft/vcpkg"
    try {
        Write-Host "Fetching latest vcpkg release info..." -ForegroundColor Cyan
        $latestRelease = Invoke-RestMethod -Uri "https://api.github.com/repos/$repo/releases/latest"
        $zipUrl = $latestRelease.zipball_url # Download source zip
        $zipFile = Join-Path $env:TEMP "vcpkg_source.zip"

        Write-Host "Downloading vcpkg source ($($latestRelease.tag_name))..." -ForegroundColor Cyan
        Invoke-WebRequest -Uri $zipUrl -OutFile $zipFile

        # 3. Extract and Refine Location
        Write-Host "Extracting to $vcpkgInstallDir..." -ForegroundColor Cyan
        $tempExtractPath = Join-Path $env:TEMP "vcpkg_extract_$(Get-Random)"
        Expand-Archive -Path $zipFile -DestinationPath $tempExtractPath -Force
        
        # vcpkg zip contains a root folder, move its contents to final dir
        $innerFolder = Get-ChildItem -Path $tempExtractPath -Directory | Select-Object -First 1
        Copy-Item -Path "$($innerFolder.FullName)\*" -Destination $vcpkgInstallDir -Recurse -Force

        # 4. Bootstrap vcpkg
        Write-Host "Bootstrapping vcpkg (compiling executable)..." -ForegroundColor Yellow
        Push-Location $vcpkgInstallDir
        cmd /c ".\bootstrap-vcpkg.bat -disableMetrics"
        Pop-Location

        # Cleanup debris
        Remove-Item $zipFile -Force
        Remove-Item $tempExtractPath -Recurse -Force
        
        Write-Host "vcpkg Installation Complete!" -ForegroundColor DarkGreen
    }
    catch {
        Write-Error "Failed to install vcpkg: $($_.Exception.Message)"
        return # Stop execution on failure
    }
}

# Finalize Environment Helper
if (Test-Path (Join-Path $vcpkgBinPath "vcpkg.exe")) {
    # Create Environment Helper
    Write-Host "Generating environment helper script..." -ForegroundColor Cyan
    
    $vcpkgEnvScript = Join-Path $EnvironmentDir "env-vcpkg.ps1"
    
    # Generate Environment Helper with Clean Paths
    $vcpkgBinPath = $vcpkgBinPath.TrimEnd('\')
    $vcpkgInstallDir = $vcpkgInstallDir.TrimEnd('\')

    # Using a literal here-string with -replace to avoid accidental expansion of $env:PATH during creation
    $EnvContent = @'
# VCPKG Environment Setup
$vcpkgbin = "VALUE_BIN_PATH"
$vcpkgroot = "VALUE_ROOT_PATH"
$env:VCPKG_PATH = $vcpkgroot
$env:VCPKG_ROOT = $vcpkgroot
$env:VCPKG_BIN = $vcpkgbin
if ($env:PATH -notlike "*$vcpkgbin*") { $env:PATH = $vcpkgbin + ";" + $env:PATH }
Write-Host "VCPKG Environment Loaded (Bin: $vcpkgbin)" -ForegroundColor Green
Write-Host "VCPKG_ROOT: $env:VCPKG_ROOT" -ForegroundColor Gray
'@ -replace "VALUE_BIN_PATH", $vcpkgBinPath -replace "VALUE_ROOT_PATH", $vcpkgInstallDir

    $EnvContent | Out-File -FilePath $vcpkgEnvScript -Encoding utf8
    Write-Host "Created: $vcpkgEnvScript" -ForegroundColor Gray
    
    # Update Current Session
    if (Test-Path $vcpkgEnvScript) { . $vcpkgEnvScript } else {
        Write-Error "vcpkg dep install finished but $vcpkgEnvScript was not created."
        return
    }
    Write-Host "vcpkg Version: $(vcpkg version)" -ForegroundColor Gray
} else {
    Write-Error "vcpkg.exe was not found in the $vcpkgBinPath folder."
    return
}
