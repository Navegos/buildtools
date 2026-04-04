# Copyright 2026 (C) Navegos. DevelVitorF. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
# file:dep-icu.ps1

param (
    [Parameter(HelpMessage = "Target vcpkg ICU triplet")]
    [string]$Triplet = "x64-windows",
    
    [Parameter(HelpMessage = "Force a full uninstallation of the local ICU version before continuing", Mandatory = $false)]
    [switch]$forceCleanup,
    
    [Parameter(HelpMessage = "Add's ICU Machine Environment Variables. Requires Machine Administatror Rights.", Mandatory = $false)]
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
elseif ($IsLinux) { $platform = "linux" }
else {
    Write-Error "Unsupported Operating System."
    return
}

# 3. Delegation Logic
$targetScript = Join-Path $PSScriptRoot "$($archFolder)-$($platform)\dep-icu.ps1"

if (Test-Path $targetScript) {
    Write-Host "[OS/ARCH] $platform $currentArch detected. Delegating..." -ForegroundColor Cyan
    
    # 1. Ensure the default path is captured if not explicitly provided by the user
    if (-not $PSBoundParameters.ContainsKey('Triplet')) {
        $PSBoundParameters['Triplet'] = $Triplet
    }
    
    & $targetScript @PSBoundParameters
}
else {
    Write-Error "Platform/Arch script not found: $targetScript"
}
