# SPDX-FileCopyrightText: Copyright (c) 2026 Navegos. @DevelVitorF. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
# project: buildtools
# file: dep-python.ps1
# created: 2026-03-29
# lastModified: 2026-05-16

param (
    [Parameter(HelpMessage = "Path for Python storage", Mandatory = $false)]
    [string]$pythonInstallDir = $null,
    
    [Parameter(HelpMessage = "Python Version", Mandatory = $false)]
    [string]$pythonVersion = $null,
    
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
    
    [Parameter(HelpMessage = "Force a full purge of the local Python version before continuing", Mandatory = $false)]
    [switch]$forceCleanup,

    [Parameter(HelpMessage = "Don't Update Python and scripts packages if update has found", Mandatory = $false)]
    [switch]$dontUpdate,
    
    [Parameter(HelpMessage = "Add's Python Machine Environment Variables. Requires Machine Administrator Rights.", Mandatory = $false)]
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

if ([string]::IsNullOrWhitespace($pythonInstallDir)) { $pythonInstallDir = Join-Path $env:LIBRARIES_PATH "$env:HOST_TRIPLET${DirSep}python" }
if ([string]::IsNullOrWhitespace($pythonVersion)) { $pythonVersion = "3.14.4" }
$targetScript = Join-Path $PSScriptRoot "$env:HOST_TRIPLET${DirSep}dep-python.ps1"

if (Test-Path $targetScript) {
    Write-Host "[OS/ARCH] $env:HOST_PLATFORM $env:HOST_ARCH detected. Delegating... $pythonInstallDir" -ForegroundColor Cyan
    
    # 1. Ensure the default path is captured if not explicitly provided by the user
    $targetDirParams = 'pythonInstallDir', 'pythonVersion'
    foreach ($targetParamName in $targetDirParams) {
        if (-not $PSBoundParameters.ContainsKey($targetParamName)) {
            # Dynamically get the value of the local variable with the same name
            $PSBoundParameters[$targetParamName] = Get-Variable -Name $targetParamName -ValueOnly
        }
    }

    & $targetScript @PSBoundParameters
}
else {
    Write-Error "Platform/Arch script not found: $targetScript"
}
