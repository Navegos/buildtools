# Copyright 2026 (C) Navegos. DevelVitorF. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
# file:x64-windows/get-pwsh.ps1

param (
    [Parameter(HelpMessage = "Path for PowerShell Installation", Mandatory = $false)]
    [string]$powershellInstallDir = $(Join-Path $env:ProgramFiles "PowerShell")
)

# --- 0. Self-Elevation Logic ---
$IsAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $IsAdmin) {
    Write-Host "Elevation required to install/update PowerShell. Relaunching as Administrator..." -ForegroundColor Yellow
    # Pass the parameters to the elevated process so they aren't lost
    $Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    foreach ($Parameter in $PSBoundParameters.GetEnumerator()) {
        if ($Parameter.Value -is [switch]) {
            if ($Parameter.Value) { $Arguments += " -$($Parameter.Key)" }
        }
        else {
            # Use escape characters to ensure paths with spaces survive the jump
            $Arguments += " -$($Parameter.Key) `"$($Parameter.Value)`""
        }
    }
    
    try {
        Start-Process pwsh.exe -ArgumentList $Arguments -Verb RunAs -ErrorAction Stop
    }
    catch {
        Start-Process powershell.exe -ArgumentList $Arguments -Verb RunAs
    }
    exit
}

Write-Host "--- Navegos PowerShell Management ---" -ForegroundColor Cyan

# --- 1. Detect and Install/Update via WinGet ---
function Install-Or-Update-Pwsh {
    Write-Host "--- Navegos PowerShell 7 Provisioning ---" -ForegroundColor Cyan

    # Define the custom MSI arguments for the Navegos standard
    # ADD_EXPLORER_CONTEXT_MENU_OPEN_HERE: Context menu for folders
    # ADD_FILE_CONTEXT_MENU_RUN_POWERSHELL7: Context menu for .ps1 files
    # ENABLE_PSREMOTING: Useful for dev environments
    # REGISTER_MANIFEST: Event logging
    # POWERSHELL_TELEMETRY_OPTOUT: Disables telemetry
    # INSTALLDIR: Sets the specific path
    $msiArgs =  "ADD_EXPLORER_CONTEXT_MENU_OPEN_HERE=1 " +
                "ADD_FILE_CONTEXT_MENU_RUN_POWERSHELL7=1 " +
                "ENABLE_PSREMOTING=0 " +
                "REGISTER_MANIFEST=1 " +
                "POWERSHELL_TELEMETRY_OPTOUT=1 " +
                "INSTALLDIR=`"$powershellInstallDir\`""

    if (Get-Command winget -ErrorAction SilentlyContinue) {
        Write-Host "Processing via WinGet..." -ForegroundColor Gray
        # Capture both standard output and errors
        # We use 'install' with --override to force our specific parameters
        # If already installed, winget will handle the configuration update
        $installOutput = winget install --id Microsoft.PowerShell --source winget --silent `
                         --accept-package-agreements --accept-source-agreements `
                         --override "/passive /norestart $msiArgs" 2>&1

        $exitCode = $LASTEXITCODE

        # Handle WinGet Result States
        if ($exitCode -eq 0 -or $exitCode -eq -1978335178-or $exitCode -eq -1978335189) {
            Write-Host "[SUCCESS] PowerShell 7 is up to date at $powershellInstallDir\" -ForegroundColor Green
            Write-Host "[CONFIG] Telemetry Disabled, Context Menus Added, PSRemoting Disabled." -ForegroundColor Gray
            
            # Use the variable to check if a reboot/restart is suggested in the text
            if ($installOutput -match "restart") {
                Write-Host "[NOTE] A system restart is recommended to finalize the update." -ForegroundColor Yellow
            }
        }else {
            Write-Host "[ERROR] WinGet operation failed. Exit Code: $exitCode" -ForegroundColor Red
            Write-Host "Details: $installOutput" -ForegroundColor Gray
        }
    } else {
        # Fallback for older systems without WinGet
        Write-Host "WinGet not found. Fetching latest release from GitHub API..." -ForegroundColor Yellow

        try {
            # Dynamically find the x64 MSI URL for the latest stable release
            $apiUri = "https://api.github.com/repos/PowerShell/PowerShell/releases/latest"
            $releaseInfo = Invoke-RestMethod -Uri $apiUri
            $url = ($releaseInfo.assets | Where-Object { $_.name -match 'win-x64\.msi$' }).browser_download_url

            if (-not $url) { throw "Could not find a valid x64 MSI in the latest GitHub release." }

            $output = Join-Path $env:TEMP "pwsh_install.msi"
            Write-Host "Downloading: $($url.Split('/')[-1])..." -ForegroundColor Gray
            Invoke-WebRequest -Uri $url -OutFile $output

            Write-Host "Installing MSI with Navegos parameters..." -ForegroundColor Gray
            # Use REINSTALLMODE=ams to force overwrite if already present, ensuring context menus are set
            $process = Start-Process msiexec.exe -ArgumentList "/i `"$output`" /passive /norestart REINSTALLMODE=ams $msiArgs" -Wait -PassThru

            # Exit code 0 is success, 1638 is "already installed"
            if ($process.ExitCode -eq 0 -or $process.ExitCode -eq 1638) {
                Write-Host "[SUCCESS] PowerShell 7 provisioned via MSI at $powershellInstallDir\" -ForegroundColor Green
                Write-Host "[CONFIG] Telemetry Disabled, Context Menus Added, PSRemoting Disabled." -ForegroundColor Gray
            } else {
                Write-Host "[ERROR] MSI failed with exit code: $($process.ExitCode)" -ForegroundColor Red
            }
        } catch {
            Write-Error "Fallback installation failed: $($_.Exception.Message)"
        } finally {
            if (Test-Path $output) { Remove-Item $output -Force -ErrorAction SilentlyContinue }
        }
    }
    # --- Path Management: Add to END of Path if not present ---
    $TargetDir = $(Join-Path $powershellInstallDir "7")
    $RegPath = "System\CurrentControlSet\Control\Session Manager\Environment"
    $RegistryKey = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey($RegPath, $true)
    $CurrentRawPath = $RegistryKey.GetValue("Path", "", [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)

    if ($CurrentRawPath -notlike "*$TargetDir*") {
        Write-Host "[PATH] Appending PowerShell 7 to the end of System Path..." -ForegroundColor Cyan
        
        # Ensure we don't start with a semicolon if the path was somehow empty
        $NewRawPath = ($CurrentRawPath + ";$TargetTag").Replace(";;;", ";;").Replace(";;", ";")

        $RegistryKey.SetValue("Path", $NewRawPath, [Microsoft.Win32.RegistryValueKind]::ExpandString)
    }
    $RegistryKey.Close()
}

Install-Or-Update-Pwsh

# --- 2. Final Verification ---
$currentVer = $PSVersionTable.PSVersion.Major
Write-Host "Current Session PowerShell Version: $currentVer" -ForegroundColor White

if ($currentVer -lt 7) {
    Write-Host "NOTE: You are in Windows PowerShell 5.1. Restart terminal to use pwsh." -ForegroundColor Yellow
}

Write-Host "--- Setup Complete ---" -ForegroundColor Green
