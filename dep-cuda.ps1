# SPDX-FileCopyrightText: Copyright (c) 2026 Navegos. @DevelVitorF. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
# project: buildtools
# file: dep-cuda.ps1
# created: 2026-03-23
# lastModified: 2026-04-26

param (
    [Parameter(HelpMessage = "Base path for cuda storage like path\cuda", Mandatory = $false)]
    [string]$cudaInstallDir = $null,

    [Parameter(HelpMessage = "Minimum Fallback CUDA Version", Mandatory = $false)]
    [string]$cudaVersion = "13.2.0",
    
    [Parameter(HelpMessage = "Minimum Fallback CUDSS Version", Mandatory = $false)]
    [string]$cudssVersion = "0.7.1",
    
    [Parameter(HelpMessage = "Minimum Fallback CUTENSOR Version", Mandatory = $false)]
    [string]$cutensorVersion = "2.6.0",
    
    [Parameter(HelpMessage = "Minimum Fallback CUSPARSELT Version", Mandatory = $false)]
    [string]$cusparseltVersion = "0.8.1",
    
    [Parameter(HelpMessage = "Minimum Fallback CUDNN Version", Mandatory = $false)]
    [string]$cudnnVersion = "9.20.0",
    
    [Parameter(HelpMessage = "Requires member of NVIDIA Developer Program and accept the license terms before download the full link for TensorRT package", Mandatory = $false)]
    [string]$tensorrtLink = $null,
    
    [Parameter(HelpMessage = "Force a full purge of the local CUDA version before continuing", Mandatory = $false)]
    [switch]$forceCleanup,

    [Parameter(HelpMessage = "Don't Update CUDA Toolkit and libs if update has found", Mandatory = $false)]
    [switch]$dontUpdate,
    
    [Parameter(HelpMessage = "Add's CUDA Machine Environment Variables. Requires Machine Administrator Rights.", Mandatory = $false)]
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
    if ([string]::IsNullOrWhitespace($cudaInstallDir)) { $cudaInstallDir = "$env:LIBRARIES_PATH\cuda" }
    $targetScript = Join-Path $PSScriptRoot "$($archFolder)-$($platform)\dep-cuda.ps1"
}
elseif ($IsLinux) {
    $platform = "linux"
    if ([string]::IsNullOrWhitespace($cudaInstallDir)) { $cudaInstallDir = "$env:LIBRARIES_PATH/cuda" }
    $targetScript = Join-Path $PSScriptRoot "$($archFolder)-$($platform)/dep-cuda.ps1"
}
else {
    Write-Error "Unsupported Operating System."
    return
}

if (Test-Path $targetScript) {
    Write-Host "[OS/ARCH] $platform $currentArch detected. Delegating..." -ForegroundColor Cyan
    
    # 1. Ensure the default path is captured if not explicitly provided by the user
    $DirParams = 'cudaInstallDir', 'cudaVersion', 'cudssVersion', 'cutensorVersion', 'cusparseltVersion', 'cudnnVersion', 'tensorrtLink'
    foreach ($ParamName in $DirParams) {
        if (-not $PSBoundParameters.ContainsKey($ParamName)) {
            # Dynamically get the value of the local variable with the same name
            $PSBoundParameters[$ParamName] = Get-Variable -Name $ParamName -ValueOnly
        }
    }

    & $targetScript @PSBoundParameters
}
else {
    Write-Error "Platform/Arch script not found: $targetScript"
}
