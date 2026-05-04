# SPDX-FileCopyrightText: Copyright (c) 2026 Navegos. @DevelVitorF. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
# project: buildtools
# file: dep-qt.ps1
# created: 2026-05-03
# lastModified: 2026-05-03

param (
    [Parameter(HelpMessage = "Path for Qt storage", Mandatory = $false)]
    [string]$qtInstallDir = $null,
    
    [Parameter(HelpMessage = "Qt Version", Mandatory = $false)]
    [string]$qtVersion = "5.15.2",
    
    [Parameter(HelpMessage = "Force a full purge of the local Qt version before continuing", Mandatory = $false)]
    [switch]$forceCleanup,
    
    [Parameter(HelpMessage = "Add's Qt Machine Environment Variables. Requires Machine Administrator Rights.", Mandatory = $false)]
    [switch]$withMachineEnvironment,

    [Parameter(HelpMessage = "Install all architectures and targets (default true)", Mandatory = $false)]
    [bool]$installAll = $true
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
    if ([string]::IsNullOrWhitespace($qtInstallDir)) { $qtInstallDir = "$env:LIBRARIES_PATH\Qt" }
    $targetScript = Join-Path $PSScriptRoot "$($archFolder)-$($platform)\dep-qt.ps1"
}
else {
    Write-Error "Unsupported Operating System."
    return
}

if (Test-Path $targetScript) {
    Write-Host "[OS/ARCH] $platform $currentArch detected. Delegating..." -ForegroundColor Cyan
    if (-not $PSBoundParameters.ContainsKey('qtInstallDir')) { $PSBoundParameters['qtInstallDir'] = $qtInstallDir }
    & $targetScript @PSBoundParameters
}
else {
    Write-Error "Platform/Arch script not found: $targetScript"
}