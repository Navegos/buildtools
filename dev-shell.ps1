# Copyright 2026 (C) Navegos. DevelVitorF. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
# file:dev-shell.ps1

param (
    [Parameter(HelpMessage = "Add's developemnt Machine Environment Variables. Requires Machine Administrator Rights.", Mandatory = $false)]
    [switch]$withMachineEnvironment, 

    [Parameter(HelpMessage = "Upgrades developemnt compilers. Requires Machine Administrator Rights.", Mandatory = $false)]
    [switch]$doUpgrade
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
    $targetScript = Join-Path $PSScriptRoot "$($archFolder)-$($platform)\dev-shell.ps1"
}
elseif ($IsLinux) {
    $platform = "linux"
    $targetScript = Join-Path $PSScriptRoot "$($archFolder)-$($platform)/dev-shell.ps1"
}
else {
    Write-Error "Unsupported Operating System."
    return
}

if (Test-Path $targetScript) {
    Write-Host "[OS/ARCH] $platform $currentArch detected. Delegating..." -ForegroundColor Cyan
    
    & $targetScript @PSBoundParameters
}
else {
    Write-Error "Platform/Arch script not found: $targetScript"
}
