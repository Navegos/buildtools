# SPDX-FileCopyrightText: Copyright (c) 2026 Navegos. @DevelVitorF. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
# project: buildtools
# file: dep-ninja.ps1
# created: 2026-03-15
# lastModified: 2026-04-26

param (
    [Parameter(HelpMessage = "Path for ninja storage", Mandatory = $false)]
    [string]$ninjaInstallDir = $null,

    [Parameter(HelpMessage = "Force a full purge of the local Ninja version before continuing", Mandatory = $false)]
    [switch]$forceCleanup,
    
    [Parameter(HelpMessage = "Add's Ninja Machine Environment Variables. Requires Machine Administrator Rights.", Mandatory = $false)]
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
if ($IsWindows) {
    $platform = "windows"
    if ([string]::IsNullOrWhitespace($ninjaInstallDir)) { $ninjaInstallDir = "$env:LIBRARIES_PATH\ninja" }
    $targetScript = Join-Path $PSScriptRoot "$($archFolder)-$($platform)\dep-ninja.ps1"
}
elseif ($IsLinux) {
    $platform = "linux"
    if ([string]::IsNullOrWhitespace($ninjaInstallDir)) { $ninjaInstallDir = "$env:LIBRARIES_PATH/ninja" }
    $targetScript = Join-Path $PSScriptRoot "$($archFolder)-$($platform)/dep-ninja.ps1"
}
else {
    Write-Error "Unsupported Operating System."
    return
}

if (Test-Path $targetScript) {
    Write-Host "[OS/ARCH] $platform $currentArch detected. Delegating..." -ForegroundColor Cyan
    
    # 1. Ensure the default path is captured if not explicitly provided by the user
    if (-not $PSBoundParameters.ContainsKey('ninjaInstallDir')) {
        $PSBoundParameters['ninjaInstallDir'] = $ninjaInstallDir
    }
    
    & $targetScript @PSBoundParameters
}
else {
    Write-Error "Platform/Arch script not found: $targetScript"
}
