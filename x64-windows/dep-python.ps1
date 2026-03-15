# Copyright 2026 (C) Navegos. DevelVitorF. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
# file:x64-windows/dep-python.ps1

param (
    [Parameter(HelpMessage="Path for python storage", Mandatory=$false)]
    [string]$pythonInstallDir = "$env:LIBRARIES_PATH\python",
    
    [Parameter(HelpMessage="Python Version", Mandatory=$false)]
    [string]$pythonVersion = "3.14.3"
)

# 1. Bootstrap Environment if variables are missing
if ([string]::IsNullOrWhitespace($env:ENVIRONMENT_PATH) -or -not (Test-Path $env:ENVIRONMENT_PATH) -or [string]::IsNullOrWhitespace($env:BINARIES_PATH) -or -not (Test-Path $env:BINARIES_PATH) -or [string]::IsNullOrWhitespace($env:LIBRARIES_PATH) -or -not (Test-Path $env:LIBRARIES_PATH)) {
    Write-Error "User Environment variables missing. Please run adduserpaths.ps1 -LibrariesDir 'Path\for\Libraries' BinariesDir 'Path\for\Binaries' -EnvironmentDir 'Path\for\Environment'"
    return
}

$EnvironmentDir = "$env:ENVIRONMENT_PATH"

$pythonCheck = Get-Command python -ErrorAction SilentlyContinue
$pythonBinPath = $pythonInstallDir
$pythonExe = Join-Path $pythonInstallDir "python.exe"
$pythonScriptsPath = Join-Path $pythonInstallDir "Scripts"

if ($pythonCheck) {
    Write-Host "Python is already installed at: $($pythonCheck.Source)" -ForegroundColor Green
    Write-Host "Python Version: $(python --version)" -ForegroundColor Gray
    
    # 1. Locate the bin folder and the root folder
    $pythonBinPath = Split-Path -Path $pythonCheck.Source -Parent
    $pythonInstallDir = Split-Path -Path $pythonBinPath -Parent
} else {
    Write-Host "Python not found. Starting $pythonVersion (Standard Zip) installation..." -ForegroundColor Yellow

    if (!(Test-Path $pythonInstallDir)) { 
        New-Item -Path $pythonInstallDir -ItemType Directory -Force | Out-Null 
    }

    # 4. Get from the official site
    try {
        $zipName = "python-$pythonVersion-amd64.zip"
        $url = "https://www.python.org/ftp/python/$pythonVersion/$zipName"
        $zipPath = Join-Path $env:TEMP $zipName
        
        Write-Host "Downloading $zipName..." -ForegroundColor Cyan
        Invoke-WebRequest -Uri $url -Outfile $zipPath
    
        Write-Host "Extracting to: $pythonInstallDir..." -ForegroundColor Cyan
        Expand-Archive -Path $zipPath -DestinationPath $pythonInstallDir -Force
    
        Remove-Item $zipPath -Force
        Write-Host "Python Installation Complete!" -ForegroundColor DarkGreen
    }
    catch {
        Write-Error "Failed to install Python: $($_.Exception.Message)"
        return
    }
    
    # --- 3. Pip Bootstrap ---
    # Standard zips often lack pip. We check the \Scripts folder.
    $pipExe = Join-Path $pythonScriptsPath "pip.exe"
    if (!(Test-Path $pipExe)) {
        Write-Host "Pip not found. Bootstrapping Pip..." -ForegroundColor Yellow
        $getPipScript = Join-Path $env:TEMP "get-pip.py"
        try {
            Invoke-WebRequest -Uri "https://bootstrap.pypa.io/get-pip.py" -OutFile $getPipScript
            & $pythonExe $getPipScript --no-warn-script-location
            Write-Host "Pip installed successfully." -ForegroundColor Green
        } catch {
            Write-Warning "Failed to bootstrap Pip: $($_.Exception.Message)"
        } finally {
            if (Test-Path $getPipScript) { Remove-Item $getPipScript -Force }
        }
    }
}

# Finalize Environment Helper
if (Test-Path (Join-Path $pythonBinPath "python.exe")) {
    # Create Environment Helper
    Write-Host "Generating environment helper script..." -ForegroundColor Cyan
    
    $pythonEnvScript = Join-Path $EnvironmentDir "env-python.ps1"

    # Generate Environment Helper with Clean Paths
    $pythonBinPath = $pythonBinPath.TrimEnd('\')
    $pythonInstallDir = $pythonInstallDir.TrimEnd('\')
    $pythonScriptsPath = Join-Path $pythonInstallDir "Scripts"

    # Using a literal here-string with -replace to avoid accidental expansion of $env:PATH during creation
    $EnvContent = @'
# PYTHON Environment Setup
$pythonbin = "VALUE_BIN_PATH"
$pythonroot = "VALUE_ROOT_PATH"
$pythonscripts = "VALUE_SCRIPTS_PATH"
$env:PYTHON_PATH = $pythonroot
$env:PYTHON_ROOT = $pythonroot
$env:PYTHON_BIN = $pythonbin
$env:PYTHON_SCRIPTS = $pythonscripts
if ($env:PATH -notlike "*$pythonbin*") { $env:PATH = $pythonbin + ";" + $env:PATH }
if ($env:PATH -notlike "*$pythonscripts*") { $env:PATH = $pythonscripts + ";" + $env:PATH }
Write-Host "PYTHON Environment Loaded (Bin: $pythonbin)" -ForegroundColor Green
Write-Host "PYTHON_ROOT: $env:PYTHON_ROOT" -ForegroundColor Gray
'@ -replace "VALUE_BIN_PATH", $pythonBinPath -replace "VALUE_ROOT_PATH", $pythonInstallDir -replace "VALUE_SCRIPTS_PATH", $pythonScriptsPath

    $EnvContent | Out-File -FilePath $pythonEnvScript -Encoding utf8
    Write-Host "Created: $pythonEnvScript" -ForegroundColor Gray
    
    # Update Current Session
    if (Test-Path $pythonEnvScript) { . $pythonEnvScript } else {
        Write-Error "python dep install finished but $pythonEnvScript was not created."
        return
    }

    # --- Post-Install: Package Management ---
    Write-Host "Python Version: $(python --version)" -ForegroundColor Gray
    $pipCheck = Get-Command pip -ErrorAction SilentlyContinue
    if ($pipCheck) {
        Write-Host "pip Version: $(pip --version)" -ForegroundColor Gray
        Write-Host "Upgrading pip and installing uv..." -ForegroundColor Cyan
        
        # Using python -m to ensure we use the local instance we just installed
        & python -m pip install -U pip uv --no-warn-script-location
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host "Successfully installed uv (Fast Python Package Manager)." -ForegroundColor Green
        } else {
            Write-Warning "uv installation failed. You may need to install it manually."
        }
    }
    
    # --- 11. Final Verification ---
    Write-Host "Performing final tool verification..." -ForegroundColor Cyan
    
    # Force PowerShell to refresh its command lookup cache
    Get-Command python, pip, uv -ErrorAction SilentlyContinue | Out-Null

    $tools = @("python", "pip", "uv")
    foreach ($tool in $tools) {
        $cmd = Get-Command $tool -ErrorAction SilentlyContinue
        if ($cmd) {
            $version = & $tool --version
            Write-Host "[OK] $tool is available at: $($cmd.Source)" -ForegroundColor Green
            Write-Host "     Version: $version" -ForegroundColor Gray
        } else {
            Write-Warning "[FAIL] $tool was installed but is not found in the current PATH."
        }
    }

    Write-Host "--- Python Sync Complete ---" -ForegroundColor Green
} else {
    Write-Error "python.exe was not found in the $pythonBinPath folder."
    return
}
