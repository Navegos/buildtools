# SPDX-FileCopyrightText: Copyright (c) 2026 Navegos. @DevelVitorF. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
# project: buildtools
# file: dep-git.ps1
# created: 2026-03-18
# lastModified: 2026-05-16

param (
    [Parameter(HelpMessage = "Path for git Installation", Mandatory = $false)]
    [string]$gitInstallDir = $null,
    
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
    
    [Parameter(HelpMessage = "Force a full purge of the local GIT version before continuing", Mandatory = $false)]
    [switch]$forceCleanup,

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

# 2. Platform Detection
if ($env:HOST_IS_WINDOWS) {
    if ([string]::IsNullOrWhitespace($gitInstallDir)) { $gitInstallDir = Join-Path $env:ProgramFiles "Git" }
}
elseif ($env:HOST_IS_LINUX) {
    if ([string]::IsNullOrWhitespace($gitInstallDir)) { $gitInstallDir = "${DirSep}usr${DirSep}bin" }
}
else {
    Write-Error "Unsupported Operating System."
    return
}

$targetScript = Join-Path $PSScriptRoot "$env:HOST_TRIPLET${DirSep}dep-git.ps1"

if (Test-Path $targetScript) {
    Write-Host "[OS/ARCH] $env:HOST_PLATFORM $env:HOST_ARCH detected. Delegating..." -ForegroundColor Cyan
    
    # 1. Ensure the default path is captured if not explicitly provided by the user
    if (-not $PSBoundParameters.ContainsKey('gitInstallDir')) {
        $PSBoundParameters['gitInstallDir'] = $gitInstallDir
    }
    
    & $targetScript @PSBoundParameters
}
else {
    Write-Error "Platform/Arch script not found: $targetScript"
}
