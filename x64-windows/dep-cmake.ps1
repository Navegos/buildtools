# Copyright 2026 (C) Navegos. DevelVitorF. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
# file:x64-windows/dep-cmake.ps1

param (
    [Parameter(HelpMessage="Path for cmake storage", Mandatory=$false)]
    [string]$cmakeInstallDir = "$env:LIBRARIES_PATH\cmake"
)

# 1. Bootstrap Environment if variables are missing
if ([string]::IsNullOrWhitespace($env:ENVIRONMENT_PATH) -or -not (Test-Path $env:ENVIRONMENT_PATH) -or [string]::IsNullOrWhitespace($env:BINARIES_PATH) -or -not (Test-Path $env:BINARIES_PATH) -or [string]::IsNullOrWhitespace($env:LIBRARIES_PATH) -or -not (Test-Path $env:LIBRARIES_PATH)) {
    Write-Error "User Environment variables missing. Please run adduserpaths.ps1 -LibrariesDir 'Path\for\Libraries' BinariesDir 'Path\for\Binaries' -EnvironmentDir 'Path\for\Environment'"
    return
}

$EnvironmentDir = "$env:ENVIRONMENT_PATH"

# 1. Define the base CMAke directory
$CMakeProgramFilesRoot = "${env:ProgramFiles}\CMake"

# if Symlink present delete
$GlobalBinDir = "$env:BINARIES_PATH"
$TargetLink = Join-Path $GlobalBinDir "cmake.exe"
# Remove existing we are creating a new one
if (Test-Path $TargetLink) { Remove-Item $TargetLink -Force }
$CurrentCMakeBin = Join-Path $cmakeInstallDir "bin\cmake.exe"
$cmakeBinPath = Join-Path $cmakeInstallDir "bin"
if (-not (Test-Path $CurrentCMakeBin)) {
    $CurrentCMakeBin = Join-Path $CMakeProgramFilesRoot "bin\cmake.exe"
}

if (Test-Path $CurrentCMakeBin) {
    Write-Host "CMake is already installed at: $($CurrentCMakeBin.Source)" -ForegroundColor Green
    Write-Host "CMake Version: $(cmake --version | Select-Object -First 1)" -ForegroundColor Gray

    # 1. Locate the bin folder and the root folder
    $cmakeBinPath = Split-Path -Path $CurrentCMakeBin.Source -Parent
    $cmakeInstallDir = Split-Path -Path $cmakeBinPath -Parent
} else {
    Write-Host "CMake not found. Starting installation..." -ForegroundColor Yellow

    if (!(Test-Path $cmakeInstallDir)) { 
        New-Item -Path $cmakeInstallDir -ItemType Directory -Force | Out-Null 
    }

    # 4. Get latest release from GitHub
    $repo = "Kitware/CMake"
    try {
        $latestRelease = Invoke-RestMethod -Uri "https://api.github.com/repos/$repo/releases/latest"
        $asset = $latestRelease.assets | Where-Object { $_.name -match "windows-x86_64\.zip$" } | Select-Object -First 1
        $zipFile = Join-Path $env:TEMP $asset.name

        Write-Host "Downloading $($asset.name)..." -ForegroundColor Cyan
        Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $zipFile

        # 5. Extract and Flatten Location
        Write-Host "Extracting to temporary location..." -ForegroundColor Cyan
        $tempExtractPath = Join-Path $env:TEMP "cmake_extract_$(Get-Random)"
        Expand-Archive -Path $zipFile -DestinationPath $tempExtractPath -Force

        # Kitware zips usually have a single root folder like 'cmake-3.30.0-windows-x86_64'
        # We find that folder and move its contents to the final destination
        $internalRoot = Get-ChildItem -Path $tempExtractPath -Directory | Select-Object -First 1

        if ($internalRoot) {
            Write-Host "Flattening directory structure..." -ForegroundColor Gray
            Get-ChildItem -Path $internalRoot.FullName | Move-Item -Destination $cmakeInstallDir -Force
        }
        
        # Cleanup extraction debris
        Remove-Item $zipFile -Force
        Remove-Item $tempExtractPath -Recurse -Force
        
        Write-Host "cmake Installation Complete!" -ForegroundColor DarkGreen
    }
    catch {
        Write-Error "Failed to install CMake: $($_.Exception.Message)"
        return # Stop execution on failure
    }
}

# Finalize Environment Helper
if (Test-Path (Join-Path $cmakeBinPath "cmake.exe")) {
    # 6. Create Environment Helper 
    Write-Host "Generating environment helper script..." -ForegroundColor Cyan
    $cmakeEnvScript = Join-Path $EnvironmentDir "env-cmake.ps1"

    # Generate Environment Helper with Clean Paths
    $cmakeBinPath = $cmakeBinPath.TrimEnd('\')
    $cmakeInstallDir = $cmakeInstallDir.TrimEnd('\')

    # Using a literal here-string with -replace to avoid accidental expansion of $env:PATH during creation
    $EnvContent = @'
# CMAKE Environment Setup
$cmakebin = "VALUE_BIN_PATH"
$cmakeroot = "VALUE_ROOT_PATH"
$env:CMAKE_PATH = $cmakeroot
$env:CMAKE_ROOT = $cmakeroot
$env:CMAKE_BIN = $cmakebin
if ($env:PATH -notlike "*$cmakebin*") { $env:PATH = $cmakebin + ";" + $env:PATH }
Write-Host "CMAKE Environment Loaded (Bin: $cmakebin)" -ForegroundColor Green
Write-Host "CMAKE_ROOT: $env:CMAKE_ROOT" -ForegroundColor Gray
'@ -replace "VALUE_BIN_PATH", $cmakeBinPath -replace "VALUE_ROOT_PATH", $cmakeInstallDir

    $EnvContent | Out-File -FilePath $cmakeEnvScript -Encoding utf8
    Write-Host "Created: $cmakeEnvScript" -ForegroundColor Gray

    # Update Current Session
    if (Test-Path $cmakeEnvScript) { . $cmakeEnvScript } else {
        Write-Error "cmake dep install finished but $cmakeEnvScript was not created."
        return
    }
    Write-Host "CMake Version: $(cmake --version | Select-Object -First 1)" -ForegroundColor Gray
} else {
    Write-Error "cmake.exe was not found in the $cmakeBinPath folder."
    return
}
