# SPDX-FileCopyrightText: Copyright (c) 2026 Navegos. @DevelVitorF. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
# project: buildtools
# file: dep-bzip2.ps1
# created: 2026-04-11
# lastModified: 2026-04-26

param (
    [Parameter(HelpMessage = "Target vcpkg BZIP2 triplet")]
    [string]$Triplet = $null,
    
    [Parameter(HelpMessage = "Force a full purge of the local BZIP2 version before continuing", Mandatory = $false)]
    [switch]$forceCleanup,
    
    [Parameter(HelpMessage = "Add's BZIP2 Machine Environment Variables. Requires Machine Administatror Rights.", Mandatory = $false)]
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
    if ([string]::IsNullOrWhitespace($Triplet)) { $Triplet = "x64-windows" }
    $targetScript = Join-Path $PSScriptRoot "$($archFolder)-$($platform)\dep-bzip2.ps1"
}
elseif ($IsLinux) {
    $platform = "linux"
    if ([string]::IsNullOrWhitespace($Triplet)) { $Triplet = "x64-linux"}
    $targetScript = Join-Path $PSScriptRoot "$($archFolder)-$($platform)/dep-bzip2.ps1"
}
else {
    Write-Error "Unsupported Operating System."
    return
}

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
