# Copyright 2026 (C) Navegos. DevelVitorF. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
# file:x64-windows/devshell.ps1

# --- 1. Initialize Visual Studio 2026 Dev Environment ---
# We check for VCINSTALLDIR to see if the environment is already loaded
if (!$env:VCINSTALLDIR) {
    Write-Host "Visual Studio 2026 environment not detected. Initializing..." -ForegroundColor Yellow

    # --- 1. Detect Existing Installation ---
    $vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
    $VSinstallPath = ""
    
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
        if (!(Test-Path $configFile)) {
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
        if (Test-Path $installerPath) { Remove-Item $installerPath -Force }
        if (Test-Path $logPath) { Remove-Item $logPath -Force }
        
        # Re-detect path now that installation is finished
        if (Test-Path $vswhere) {
            $VSinstallPath = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
        }

        Write-Host "Visual Studio 2026 installed at: $VSinstallPath" -ForegroundColor Green
    } else {
        Write-Host "Visual Studio 2026 installed at: $VSinstallPath" -ForegroundColor Green
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
        $LIB= $env:LIB
        $env:INCLUDE = $INCLUDE.Replace('\\', '\')
        $env:LIB = $LIB.Replace('\\', '\')

        Write-Host "Visual Studio 2026 DevShell initialized (x64)." -ForegroundColor Green
    } else {
        Write-Error "Initialization failed. Could not locate DevShell DLL."
        return
    }
} else {
    Write-Host "Visual Studio 2026 DevShell already initialized (x64)." -ForegroundColor Green
}
