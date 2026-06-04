# SPDX-FileCopyrightText: Copyright (c) 2026 Navegos. @DevelVitorF. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
# project: buildtools
# file: get-pwsh.ps1
# created: 2026-03-20
# lastModified: 2026-05-14

param (
    [Parameter(HelpMessage = "Path for PowerShell Installation", Mandatory = $false)]
    [string]$powershellInstallDir = $null,
    
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
    if ([string]::IsNullOrWhitespace($powershellInstallDir)) { $powershellInstallDir = $(Join-Path $env:ProgramFiles "PowerShell") }
}
elseif ($env:HOST_IS_LINUX) {
    if ([string]::IsNullOrWhitespace($powershellInstallDir)) { $powershellInstallDir = "${DirSep}opt${DirSep}microsoft${DirSep}powershell" }
}
else {
    Write-Error "Unsupported Operating System."
    return
}

$targetScript = Join-Path $PSScriptRoot "$env:HOST_TRIPLET${DirSep}get-pwsh.ps1"

if (Test-Path $targetScript) {
    Write-Host "[OS/ARCH] $env:HOST_PLATFORM $env:HOST_ARCH detected. Delegating..." -ForegroundColor Cyan
    
    # 1. Ensure the default path is captured if not explicitly provided by the user
    if (-not $PSBoundParameters.ContainsKey('powershellInstallDir')) {
        $PSBoundParameters['powershellInstallDir'] = $powershellInstallDir
    }
    
    & $targetScript @PSBoundParameters
}
else {
    Write-Error "Platform/Arch script not found: $targetScript"
}
