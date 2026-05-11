# SPDX-FileCopyrightText: Copyright (c) 2026 Navegos. @DevelVitorF. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
# project: buildtools
# file: x64-windows/dev-shell.ps1
# created: 2026-03-01
# lastModified: 2026-04-26

param (
    [Parameter(HelpMessage = "Add's Visual Studio 2026 Machine Environment Variables. Requires Machine Administrator Rights.", Mandatory = $false)]
    [switch]$withMachineEnvironment,

    [Parameter(HelpMessage = "Upgrades Visual Studio 2026 Installation. Requires Machine Administrator Rights.", Mandatory = $false)]
    [switch]$doUpgrade
)

# Capture parameters
$VSWithMachineEnvironment = $withMachineEnvironment
$VSDoUpgrade = $doUpgrade

# --- 1. Initialize Visual Studio 2026 Dev Environment ---
# We check for VCINSTALLDIR to see if the environment is already loaded
if (-not $env:VCINSTALLDIR) {
    Write-Host "Visual Studio 2026 environment not detected. Initializing..." -ForegroundColor Yellow

    # --- 1. Detect Existing Installation ---
    $vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
    $VSinstallPath = $null
    
    if (Test-Path $vswhere) {
        $VSinstallPath = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
    }

    # --- 2. Install if Missing ---
    if ([string]::IsNullOrWhiteSpace($VSinstallPath)) {
        Write-Host "Visual Studio 2026 Tools not found. Preparing for installation..." -ForegroundColor Yellow

        # Define paths
        $configFile = Join-Path $PSScriptRoot "vs_buildtools_2026.vsconfig"
        $bootstrapperUrl = "https://aka.ms/vs/stable/vs_BuildTools.exe"
        $installerPath = "$env:TEMP\vs_buildtools_2026.exe"
        $logPath = "$env:TEMP\vs_install_details.txt"

        # 1. Verification
        if (-not (Test-Path $configFile)) {
            Write-Error "CRITICAL: .vsconfig missing at $configFile. Cannot proceed with automated install."
            return
        }

        # 2. Download
        Write-Host "Downloading VS Bootstrapper..." -ForegroundColor Gray
        Invoke-WebRequest -Uri $bootstrapperUrl -OutFile $installerPath

        Write-Host "Installing components via $configFile. Please wait..." -ForegroundColor Yellow
        
        # 3. Execution
        # Run silent installation
        # --config: Points to your JSON component list
        # --log: writes log to temp file
        # --passive: Shows progress but no interaction
        # --norestart: Prevents sudden reboots
        # --wait: Ensures the script waits for completion
        Write-Host "Starting Passive Installation. This may take 10-20 minutes..." -ForegroundColor Cyan
        $installArgs = @(
            "--config", "`"$configFile`"",
            "--log", "`"$logPath`"",
            "--passive",
            "--norestart",
            "--wait"
        )
        
        # We wrap this in a try-catch to catch "Access Denied" if the user hits 'No' on UAC
        try {
            $process = Start-Process -FilePath $installerPath -ArgumentList $installArgs -Wait -PassThru
            Write-Host "Installer finished with Exit Code: $($process.ExitCode)" -ForegroundColor Cyan
        }
        catch {
            Write-Error "Failed to launch installer: $($_.Exception.Message)"
            return
        }

        # 4. Cleanup & Path Refresh
        if (Test-Path $installerPath) { Remove-Item $installerPath -Force -ErrorAction SilentlyContinue }
        if (Test-Path $logPath) { Remove-Item $logPath -Force -ErrorAction SilentlyContinue }
        
        # Re-detect path now that installation is finished
        if (Test-Path $vswhere) {
            $VSinstallPath = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
        }

        Write-Host "Visual Studio 2026 installed at: $VSinstallPath" -ForegroundColor Green
    } else {
        Write-Host "Visual Studio 2026 installed at: $VSinstallPath" -ForegroundColor Green
        
        $vsExeInstaller = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\setup.exe"
        if ($VSDoUpgrade) {
            Write-Host "[UPGRADE] Checking for Visual Studio updates..." -ForegroundColor Yellow
            $vsExeInstaller = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\setup.exe"
            
            $configFile = Join-Path $PSScriptRoot "vs_buildtools_2026.vsconfig"
            
            # 1. Verification
            if (-not (Test-Path $configFile)) {
                Write-Error "CRITICAL: .vsconfig missing at $configFile. Cannot proceed with automated update install."
                return
            }
    
            if (Test-Path $vsExeInstaller) {
                $upgradeArgs = @(
                    "update",
                    "--installPath", "`"$VSinstallPath`"",
                    "--config", "`"$configFile`"",
                    "--log", "`"$logPath`"",
                    "--passive",
                    "--norestart",
                    "--wait"
                )
                try {
                    Write-Host "Updating Visual Studio instance at $VSinstallPath..." -ForegroundColor Cyan
                    Start-Process -FilePath $vsExeInstaller -ArgumentList $upgradeArgs -Wait -Verb RunAs
                    Write-Host "Update process completed." -ForegroundColor Green
                }
                catch {
                    Write-Error "Failed to run Visual Studio Update: $($_.Exception.Message)"
                }
            }
        }
    }

    # --- 3. Initialize DevShell ---
    if ($VSinstallPath -and (Test-Path (Join-Path $VSinstallPath "Common7\Tools\Microsoft.VisualStudio.DevShell.dll"))) {
        $DevShellPath = Join-Path $VSinstallPath "Common7\Tools\Microsoft.VisualStudio.DevShell.dll"
        Import-Module $DevShellPath
        # Detect InstanceId
        if (Test-Path $vswhere) {
            $InstanceId = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property instanceId
        }
        
        Enter-VsDevShell -InstanceId $InstanceId -SkipAutomaticLocation -DevCmdArguments "-arch=x64 -host_arch=x64"
        
        # Normalize paths... some batchs have the paths polluted
        $INCLUDE= $env:INCLUDE
        $LIB = $env:LIB
        $PATH = $env:PATH
        $env:INCLUDE = $INCLUDE.Replace('\\', '\')
        $env:LIB = $LIB.Replace('\\', '\')
        $env:PATH = $PATH.Replace('\\', '\')

        Write-Host "Visual Studio 2026 DevShell initialized (x64)." -ForegroundColor Green
    } else {
        Write-Error "Initialization failed. Could not locate DevShell DLL."
        return
    }
} else {
    Write-Host "Visual Studio 2026 DevShell already initialized (x64)." -ForegroundColor Green
}

if ($VSWithMachineEnvironment) {
    $clExePath = (where.exe cl.exe | Select-Object -First 1).Trim()

    if (Test-Path $clExePath)
    {
        $VSMachineEnvScript = Join-Path $EnvironmentDir "machine-env-vs.ps1"

        $vsInstallDir = $env:VSINSTALLDIR
        $vcInstallDir = $env:VCINSTALLDIR
        $msvcBinPath = (Split-Path -Path $clExePath -Parent)
        $vswhereDir = (Split-Path -Path $vswhere -Parent)
        
        if (Test-Path $vswhere) {
            $vsVersion = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property catalog_productDisplayVersion
        }
    
        # Generating Machine Environment wich add to the persist registry machine Environment
        $MachineEnvContent = @'
# Visual Studio 2026 Machine Environment Setup

# --- 0. Self-Elevation Logic ---
$IsAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$ScopeColor = "Cyan"

if (-not $IsAdmin) {
Write-Host "Elevation required to set Visual Studio 2026 system variables. Relaunching as Administrator..." -ForegroundColor Yellow
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

$vsroot = "VALUE_ROOT_PATH"
$vcroot = "VALUE_CROOT_PATH"
$vsinstaller = "VALUE_INSTALLER_PATH"
$msvcbin = "VALUE_BIN_PATH"
$vsversion = "VALUE_VERSION"

$TargetScope = if ($IsAdmin) { "Machine" } else { "User" }
$RegPath = if ($IsAdmin) { "System\CurrentControlSet\Control\Session Manager\Environment" } else { "Environment" }
$RegRoot = if ($IsAdmin) { "LocalMachine" } else { "CurrentUser" }

$RegEnvMapping = [ordered]@{
    "MSVC_BIN"          = $msvcbin
    "VS_IDE"            = $vsroot + "Common7\IDE\"
    "MSBUILD_BIN"       = $vsroot + "MSBuild\Current\Bin\"
    "VC_AUXILIARY"      = $vcroot + "Auxiliary\Build\"
    "VS_INSTALLER"      = $vsinstaller
}

# Open the registry key once
$RegKey = [Microsoft.Win32.Registry]::$RegRoot.OpenSubKey($RegPath, $true)

# Open the registry key directly to read the RAW (unexpanded) string
$CurrentRawPath = $RegKey.GetValue("VSTOOLS_PATH", "", [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)

# Cleanup: Remove empty strings, any path containing Microsoft Visual Studio, and the current target (to avoid dups)
$CleanedPathList = $CurrentRawPath -split ';' | Where-Object { 
    -not [string]::IsNullOrWhitespace($_) -and 
    $_ -notlike "*\Program Files (x86)\Microsoft Visual Studio*"
}

$NewRawPath = ($CleanedPathList -join ";").Replace(";;", ";")

foreach ($Entry in $RegEnvMapping.GetEnumerator())
{
    $VarName = $Entry.Key
    $TargetPath = $Entry.Value
    
    # Update Current Process
    Set-Item -Path "Env:\$VarName" -Value $TargetPath
    
    # Rebuild
    $NewRawPath = ($TargetPath + ";" + $NewRawPath + ";").Replace(";;", ";")
    
    Write-Host "[UPDATED] ($TargetScope) '$VarName' synced in VSTOOLS_PATH" -ForegroundColor $ScopeColor
}

# Save as ExpandString
$RegKey.SetValue("VSTOOLS_PATH", $NewRawPath, [Microsoft.Win32.RegistryValueKind]::ExpandString)
$env:VSTOOLS_PATH = $NewRawPath

$RegKey.Close()

$env:VS_ROOT = $vsroot
Write-Host "Visual Studio 2026 Environment Loaded (Version: $vsversion) (Bin: $msvcbin)" -ForegroundColor Green
Write-Host "VS_ROOT: $env:VS_ROOT" -ForegroundColor Gray
'@  -replace "VALUE_ROOT_PATH", $vsInstallDir `
    -replace "VALUE_CROOT_PATH", $vcInstallDir `
    -replace "VALUE_INSTALLER_PATH", $vswhereDir `
    -replace "VALUE_BIN_PATH", $msvcBinPath `
    -replace "VALUE_VERSION", $vsVersion

        $MachineEnvContent | Out-File -FilePath $vsMachineEnvScript -Encoding utf8
        Write-Host "Created: $vsMachineEnvScript" -ForegroundColor Gray
        
        # --- Interaction: Prompt to apply persistent changes ---
        Write-Host ""
        $choice = Read-Host "Do you want to run the Machine Environment script now to persist Visual Studio 2026 changes to the Registry? (y/n)"
        if ($choice -eq 'y' -or $choice -eq 'Y') {
            Write-Host "Executing $vsMachineEnvScript..." -ForegroundColor Yellow
            try {
                # Start the generated script. It handles its own elevation logic.
                & $vsMachineEnvScript
            }
            catch {
                Write-Error "Failed to execute the Machine Environment script: $($_.Exception.Message)"
            }
        }
        else {
            Write-Host "Skipped persistent registry update. You can run it later at: $vsMachineEnvScript" -ForegroundColor Gray
        }
    }
}
