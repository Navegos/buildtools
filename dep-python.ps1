# SPDX-FileCopyrightText: Copyright (c) 2026 Navegos. @DevelVitorF. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
# project: buildtools
# file: dep-python.ps1
# created: 2026-03-29
# lastModified: 2026-04-26

param (
    [Parameter(HelpMessage = "Path for Python storage", Mandatory = $false)]
    [string]$pythonInstallDir = $null,
    
    [Parameter(HelpMessage = "Python Version", Mandatory = $false)]
    [string]$pythonVersion = "3.14.4",

    [Parameter(HelpMessage = "Force a full purge of the local Python version before continuing", Mandatory = $false)]
    [switch]$forceCleanup,

    [Parameter(HelpMessage = "Don't Update Python and scripts packages if update has found", Mandatory = $false)]
    [switch]$dontUpdate,
    
    [Parameter(HelpMessage = "Add's Python Machine Environment Variables. Requires Machine Administrator Rights.", Mandatory = $false)]
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
    if ([string]::IsNullOrWhitespace($pythonInstallDir)) { $pythonInstallDir = "$env:LIBRARIES_PATH\python" }
    $targetScript = Join-Path $PSScriptRoot "$($archFolder)-$($platform)\dep-python.ps1"
}
elseif ($IsLinux) {
    $platform = "linux"
    if ([string]::IsNullOrWhitespace($pythonInstallDir)) { $pythonInstallDir = "$env:LIBRARIES_PATH/python" }
    $targetScript = Join-Path $PSScriptRoot "$($archFolder)-$($platform)/dep-python.ps1"
}
else {
    Write-Error "Unsupported Operating System."
    return
}

if (Test-Path $targetScript) {
    Write-Host "[OS/ARCH] $platform $currentArch detected. Delegating..." -ForegroundColor Cyan
    
    # 1. Ensure the default path is captured if not explicitly provided by the user
    if (-not $PSBoundParameters.ContainsKey('pythonInstallDir')) {
        $PSBoundParameters['pythonInstallDir'] = $pythonInstallDir
    }
    
    & $targetScript @PSBoundParameters
}
else {
    Write-Error "Platform/Arch script not found: $targetScript"
}
