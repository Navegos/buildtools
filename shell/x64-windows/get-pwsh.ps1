# SPDX-FileCopyrightText: Copyright (c) 2026 Navegos. @DevelVitorF. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
# project: buildtools
# file: x64-windows/get-pwsh.ps1
# created: 2026-03-15
# lastModified: 2026-04-26

param (
    [Parameter(HelpMessage = "Path for PowerShell Installation", Mandatory = $false)]
    [string]$powershellInstallDir = $(Join-Path $env:ProgramFiles "PowerShell")
)

# --- 0. Self-Elevation Logic ---
$IsAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$IsCore = $PSVersionTable.PSEdition -eq 'Core'

if (-not $IsAdmin -or $IsCore) {
    try {
        $msg = if (-not $IsAdmin) { "Elevation required." } else { "In pwsh.exe - switching to powershell.exe." }
        Write-Host "--- $msg Relaunching... ---" -ForegroundColor Yellow
        
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

        # Force use of legacy host to avoid file locks on pwsh.exe
        Start-Process "powershell.exe" -ArgumentList $Arguments -Verb RunAs -ErrorAction Stop
        exit
    }
    catch {
        Write-Error "Failed to relaunch script: $($_.Exception.Message)"
        return
    }
}

# --- 1. Helper Function: Error Reporter ---
function Show-Error {
    param([string]$Message, [int]$ExitCode = 1)
    Write-Host "`n[FATAL ERROR] $Message" -ForegroundColor Red
    Write-Host "Exit Code: $ExitCode" -ForegroundColor Gray
    # We use Write-Error to populate the $error stream for calling scripts
    Write-Error $Message
}

Write-Host "--- PowerShell Management ---" -ForegroundColor Cyan

# --- 1. Detect and Install/Update ---
function Install-Or-Update-Pwsh {
    Write-Host "--- PowerShell 7 Provisioning ---" -ForegroundColor Cyan

    # Define the custom MSI arguments for the standard
    # ADD_EXPLORER_CONTEXT_MENU_OPEN_HERE: Context menu for folders
    # ADD_FILE_CONTEXT_MENU_RUN_POWERSHELL7: Context menu for .ps1 files
    # ENABLE_PSREMOTING: Useful for dev environments
    # REGISTER_MANIFEST: Event logging
    # POWERSHELL_TELEMETRY_OPTOUT: Disables telemetry
    # INSTALLDIR: Sets the specific path
    $msiArgs = @(
        "ADD_EXPLORER_CONTEXT_MENU_OPEN_HERE=1"
        "ADD_FILE_CONTEXT_MENU_RUN_POWERSHELL7=1"
        "ENABLE_PSREMOTING=0"
        "REGISTER_MANIFEST=1"
        "POWERSHELL_TELEMETRY_OPTOUT=1"
        "INSTALLDIR=`"$powershellInstallDir`""
    ) -join " "

    try {
        Write-Host "Fetching latest release from GitHub API..." -ForegroundColor Yellow

        # Dynamically find the x64 MSI URL for the latest stable release
        $apiUri = "https://api.github.com/repos/PowerShell/PowerShell/releases/latest"
        $releaseInfo = Invoke-RestMethod -Uri $apiUri -ErrorAction Stop
        $url = ($releaseInfo.assets | Where-Object { $_.name -match 'win-x64\.msi$' }).browser_download_url

        if (-not $url) { throw "Could not find a valid x64 MSI in the latest GitHub release." }

        $tempMsi = Join-Path $env:TEMP "pwsh_install.msi"
        Write-Host "Downloading: $($url.Split('/')[-1])..." -ForegroundColor Gray
        Invoke-WebRequest -Uri $url -OutFile $tempMsi -ErrorAction Stop

        Write-Host "Installing MSI with parameters..." -ForegroundColor Gray
        # Use REINSTALLMODE=ams to force overwrite if already present, ensuring context menus are set
        $msiProcess = Start-Process msiexec.exe -ArgumentList "/i `"$tempMsi`" /passive /norestart REINSTALLMODE=ams $msiArgs" -Wait -PassThru

        # Exit code 0 is success, 1638 is "already installed"
        if ($msiProcess.ExitCode -eq 0 -or $msiProcess.ExitCode -eq 1638) {
            Write-Host "[SUCCESS] PowerShell 7 provisioned via MSI at $powershellInstallDir\" -ForegroundColor Green
            Write-Host "[CONFIG] Telemetry Disabled, Context Menus Added, PSRemoting Disabled." -ForegroundColor Gray
        } else {
            throw "[ERROR] MSI Installation failed with exit code: $($msiProcess.ExitCode)"
        }
        if (Test-Path $tempMsi) { Remove-Item $tempMsi -Force -ErrorAction SilentlyContinue }

        # --- Path Management: Add to END of Path if not present ---
        $TargetDir = $(Join-Path $powershellInstallDir "7")
        $RegPath = "System\CurrentControlSet\Control\Session Manager\Environment"
        $RegistryKey = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey($RegPath, $true)
        $CurrentRawPath = $RegistryKey.GetValue("Path", "", [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
        
        # Cleanup: Remove empty strings, any path containing $powershellInstallDir, and the current target (to avoid dups)
        $CleanedPathList = $CurrentRawPath -split ';' | Where-Object { 
            -not [string]::IsNullOrWhitespace($_) -and 
            $_ -notlike "*$powershellInstallDir*"
        }
        
        $NewRawPath = ($CleanedPathList -join ";").Replace(";;", ";")

        $NewRawPath = ($NewRawPath + ";" + $TargetDir + ";").Replace(";;", ";")
        
        $RegistryKey.SetValue("Path", $NewRawPath, [Microsoft.Win32.RegistryValueKind]::ExpandString)
        Write-Host "[SUCCESS] Path updated." -ForegroundColor Green

        $RegistryKey.Close()
    }
    catch {
        Show-Error "Installation failed: $($_.Exception.Message)"
        return
    }
}

# --- 3. Run ---
Install-Or-Update-Pwsh

# --- 2. Final Verification ---
$currentVer = $PSVersionTable.PSVersion.Major
Write-Host "Current Session PowerShell Version: $currentVer" -ForegroundColor White

if ($currentVer -lt 7) {
    Write-Host "NOTE: You are in Windows PowerShell 5.1. Restart terminal to use pwsh." -ForegroundColor Yellow
}

Write-Host "--- Setup Complete ---" -ForegroundColor Green
