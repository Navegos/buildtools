# Copyright 2026 (C) Navegos. DevelVitorF. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
# file:dep-cygwin.ps1

param (
    [Parameter(HelpMessage = "Path for Cygwin Installation", Mandatory = $false)]
    [string]$cygwinInstallDir = "$env:LIBRARIES_PATH\cygwin",
    
    [Parameter(HelpMessage = "Force a full uninstallation of the local Cygwin version before continuing", Mandatory = $false)]
    [switch]$forceCleanup,
    
    [Parameter(HelpMessage = "Add's Cygwin Machine Environment Variables. Requires Machine Administrator Rights.", Mandatory = $false)]
    [switch]$withMachineEnvironment
)

# 1. Architecture Detection
$currentArch = [System.Runtime.InteropServices.RuntimeInformation]::ProcessArchitecture.ToString().ToLower()

# Map arch names to folder names
$archMap = @{ "x64" = "x64"; "arm64" = "arm64" }
$archFolder = $archMap[$currentArch]

if (-not $archFolder) {
    Write-Error "Unsupported architecture: $currentArch"
    return
}

# 2. Platform Detection
if ($IsWindows) { $platform = "windows" }
else {
    Write-Error "Unsupported Operating System."
    return
}

# 3. Delegation Logic
$targetScript = Join-Path $PSScriptRoot "$($archFolder)-$($platform)\dep-cygwin.ps1"

if (Test-Path $targetScript) {
    Write-Host "[OS/ARCH] $platform $currentArch detected. Delegating..." -ForegroundColor Cyan
    
    # 1. Ensure the default path is captured if not explicitly provided by the user
    if (-not $PSBoundParameters.ContainsKey('cygwinInstallDir')) {
        $PSBoundParameters['cygwinInstallDir'] = $cygwinInstallDir
    }
    
    & $targetScript @PSBoundParameters
}
else {
    Write-Error "Platform/Arch script not found: $targetScript"
}
