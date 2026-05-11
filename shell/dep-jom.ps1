# SPDX-FileCopyrightText: Copyright (c) 2026 Navegos. @DevelVitorF. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
# project: buildtools
# file: dep-jom.ps1
# created: 2026-05-03
# lastModified: 2026-05-03

param (
    [Parameter(HelpMessage = "Path for jom storage", Mandatory = $false)]
    [string]$jomInstallDir = $null,
    
    [Parameter(HelpMessage = "Force a full purge of the local jom version before continuing", Mandatory = $false)]
    [switch]$forceCleanup,
    
    [Parameter(HelpMessage = "Add's jom Machine Environment Variables. Requires Machine Administrator Rights.", Mandatory = $false)]
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
    if ([string]::IsNullOrWhitespace($jomInstallDir)) { $jomInstallDir = "$env:LIBRARIES_PATH\jom" }
    $targetScript = Join-Path $PSScriptRoot "$($archFolder)-$($platform)\dep-jom.ps1"
} else {
    Write-Error "Unsupported Operating System."
    return
}

if (Test-Path $targetScript) {
    Write-Host "[OS/ARCH] $platform $currentArch detected. Delegating..." -ForegroundColor Cyan
    if (-not $PSBoundParameters.ContainsKey('jomInstallDir')) { $PSBoundParameters['jomInstallDir'] = $jomInstallDir }
    
    & $targetScript @PSBoundParameters
} else {
    Write-Error "Platform/Arch script not found: $targetScript"
}