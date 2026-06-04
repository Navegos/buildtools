# SPDX-FileCopyrightText: Copyright (c) 2026 Navegos. @DevelVitorF. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
# project: buildtools
# file: add-user-paths.ps1
# created: 2026-03-21
# lastModified: 2026-05-15

param (
    [Parameter(HelpMessage = "Base path for library storage", Mandatory = $false)]
    [string]$LibrariesDir = $null,

    [Parameter(HelpMessage = "Base path for environment-specific configs", Mandatory = $false)]
    [string]$EnvironmentDir = $null,

    [Parameter(HelpMessage = "Base path for binaries", Mandatory = $false)]
    [string]$BinariesDir = $null,
    
    [Parameter(HelpMessage = "Base path for build tools", Mandatory = $false)]
    [string]$BuildToolsDir = (Split-Path -Path $PSScriptRoot -Parent),
    
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

    [Parameter(ValueFromRemainingArguments = $true)]
    $RemainingArgs
)

# Get the correct list separator for the current OS (; on Win, : on Linux)
#$Sep = [IO.Path]::PathSeparator

# Get the correct folder separator (\ on Win, / on Linux)
$DirSep = [IO.Path]::DirectorySeparatorChar

# 1. Architecture Detection
if (-not $env:HOST_ARCH -or $isToolchain) {
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
    if ([string]::IsNullOrWhitespace($LibrariesDir)) { $LibrariesDir = "C:${DirSep}libs" }
    if ([string]::IsNullOrWhitespace($EnvironmentDir)) { $EnvironmentDir = "C:${DirSep}libs${DirSep}environment" }
    if ([string]::IsNullOrWhitespace($BinariesDir)) { $BinariesDir = "C:${DirSep}libs${DirSep}binaries" }
}
elseif ($env:HOST_IS_LINUX) {
    if ([string]::IsNullOrWhitespace($LibrariesDir)) { $LibrariesDir = "${DirSep}opt${DirSep}libs" }
    if ([string]::IsNullOrWhitespace($EnvironmentDir)) { $EnvironmentDir = "${DirSep}opt${DirSep}libs${DirSep}environment" }
    if ([string]::IsNullOrWhitespace($BinariesDir)) { $BinariesDir = "${DirSep}opt${DirSep}libs${DirSep}binaries" }
}
else {
    Write-Error "Unsupported Operating System."
    return
}

$targetScript = Join-Path $PSScriptRoot "$env:HOST_TRIPLET${DirSep}add-user-paths.ps1"

if (Test-Path $targetScript) {
    Write-Host "[OS/ARCH] $env:HOST_PLATFORM $env:HOST_ARCH detected. Delegating..." -ForegroundColor Cyan
    
    # 1. Ensure the default path is captured if not explicitly provided by the user
    $DirParams = 'LibrariesDir', 'EnvironmentDir', 'BinariesDir', 'BuildToolsDir'
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
