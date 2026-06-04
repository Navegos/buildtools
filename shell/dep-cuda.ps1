# SPDX-FileCopyrightText: Copyright (c) 2026 Navegos. @DevelVitorF. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
# project: buildtools
# file: dep-cuda.ps1
# created: 2026-03-23
# lastModified: 2026-05-16

param (
    [Parameter(HelpMessage = "Base path for cuda storage like path\cuda", Mandatory = $false)]
    [string]$cudaInstallDir = $null,

    [Parameter(HelpMessage = "Minimum Fallback CUDA Version", Mandatory = $false)]
    [string]$cudaVersion = $null,
    
    [Parameter(HelpMessage = "Minimum Fallback CUDSS Version", Mandatory = $false)]
    [string]$cudssVersion = $null,
    
    [Parameter(HelpMessage = "Minimum Fallback CUTENSOR Version", Mandatory = $false)]
    [string]$cutensorVersion = $null,
    
    [Parameter(HelpMessage = "Minimum Fallback CUSPARSELT Version", Mandatory = $false)]
    [string]$cusparseltVersion = $null,
    
    [Parameter(HelpMessage = "Minimum Fallback CUDNN Version", Mandatory = $false)]
    [string]$cudnnVersion = $null,
    
    [Parameter(HelpMessage = "Requires member of NVIDIA Developer Program and accept the license terms before download the full link for TensorRT package", Mandatory = $false)]
    [string]$tensorrtLink = $null,
    
    [Parameter(HelpMessage = "Target Architecture to build for", Mandatory = $false)]
    [string]$targetArch = $null,
    
    [Parameter(HelpMessage = "Target Platform to build for", Mandatory = $false)]
    [string]$targetPlatform = $null,
    
    [Parameter(HelpMessage = "Target Host Architecture to build for", Mandatory = $false)]
    [string]$targetHostArch = $null,
    
    [Parameter(HelpMessage = "Target Host Platform to build for", Mandatory = $false)]
    [string]$targetHostPlatform = $null,
    
    [Parameter(HelpMessage = "Path for toolchain installation, expects target triple at the end of path", Mandatory = $false)]
    [string]$toolchainInstallDir = $null,
    
    [Parameter(HelpMessage = "Indicates if the target is part of a toolchain", Mandatory = $false)]
    [switch]$isToolchain,
    
    [Parameter(HelpMessage = "Add TensorRT SDK package to the toolkit installation", Mandatory = $false)]
    [switch]$withTensorRT,

    [Parameter(HelpMessage = "Force a full purge of the local CUDA version before continuing", Mandatory = $false)]
    [switch]$forceCleanup,

    [Parameter(HelpMessage = "Don't Update CUDA Toolkit and libs if update has found", Mandatory = $false)]
    [switch]$dontUpdate,
    
    [Parameter(HelpMessage = "Add's CUDA Machine Environment Variables. Requires Machine Administrator Rights.", Mandatory = $false)]
    [switch]$withMachineEnvironment,

    [Parameter(ValueFromRemainingArguments = $true)]
    $RemainingArgs
)

# Get the correct list separator for the current OS (; on Win, : on Linux)
#$Sep = [IO.Path]::PathSeparator

# Get the correct folder separator (\ on Win, / on Linux)
$DirSep = [IO.Path]::DirectorySeparatorChar

# 1. Architecture Detection
if (-not $env:HOST_ARCH) {
    $archTripleScript = Join-Path $PSScriptRoot "arch-triple.ps1"
    if (Test-Path $archTripleScript) {
        # 1. Ensure the default path is captured if not explicitly provided by the user
        $ArchDirParams = 'targetArch', 'targetPlatform', 'targetHostArch', 'targetHostPlatform', 'toolchainInstallDir'
        foreach ($ArchParamName in $ArchDirParams) {
            if (-not $PSBoundParameters.ContainsKey($ArchParamName)) {
                # Dynamically get the value of the local variable with the same name
                $PSBoundParameters[$ArchParamName] = Get-Variable -Name $ArchParamName -ValueOnly
            }
        }

        & $archTripleScript @PSBoundParameters
    }
    else {
        Write-Error "Arch triple script not found: $archTripleScript"
        return
    }
}

if ([string]::IsNullOrWhitespace($cudaInstallDir)) { $cudaInstallDir = Join-Path $env:LIBRARIES_PATH "$env:HOST_TRIPLET${DirSep}cuda" }
if ([string]::IsNullOrWhitespace($cudaVersion)) { $cudaVersion = "13.2.1" }
if ([string]::IsNullOrWhitespace($cudssVersion)) { $cudssVersion = "0.7.1" }
if ([string]::IsNullOrWhitespace($cutensorVersion)) { $cutensorVersion = "2.6.0" }
if ([string]::IsNullOrWhitespace($cusparseltVersion)) { $cusparseltVersion = "0.9.0" }
if ([string]::IsNullOrWhitespace($cudnnVersion)) { $cudnnVersion = "9.21.1" }

$targetScript = Join-Path $PSScriptRoot "$env:HOST_TRIPLET${DirSep}dep-cuda.ps1"

if (Test-Path $targetScript) {
    Write-Host "[OS/ARCH] $env:HOST_PLATFORM $env:HOST_ARCH detected. Delegating..." -ForegroundColor Cyan
    
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
