# SPDX-FileCopyrightText: Copyright (c) 2026 Navegos. @DevelVitorF. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
# project: buildtools
# file: add-user-paths.ps1
# created: 2026-03-21
# lastModified: 2026-04-26

param (
    [Parameter(HelpMessage = "Base path for library storage", Mandatory = $false)]
    [string]$LibrariesDir = $null,

    [Parameter(HelpMessage = "Base path for environment-specific configs", Mandatory = $false)]
    [string]$EnvironmentDir = $null,

    [Parameter(HelpMessage = "Base path for binaries", Mandatory = $false)]
    [string]$BinariesDir = $null,
    
    [Parameter(HelpMessage = "Base path for build tools", Mandatory = $false)]
    [string]$BuildToolsDir = $PSScriptRoot # BuildTools root folder
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
    if ([string]::IsNullOrWhitespace($LibrariesDir)) { $LibrariesDir = "C:\libs" }
    if ([string]::IsNullOrWhitespace($EnvironmentDir)) { $EnvironmentDir = "C:\libs\environment" }
    if ([string]::IsNullOrWhitespace($BinariesDir)) { $BinariesDir = "C:\libs\binaries" }
    $targetScript = Join-Path $PSScriptRoot "$($archFolder)-$($platform)\add-user-paths.ps1"
}
elseif ($IsLinux) {
    $platform = "linux"
    if ([string]::IsNullOrWhitespace($LibrariesDir)) { $LibrariesDir = "/opt/libs" }
    if ([string]::IsNullOrWhitespace($EnvironmentDir)) { $EnvironmentDir = "/opt/libs/environment" }
    if ([string]::IsNullOrWhitespace($BinariesDir)) { $BinariesDir = "/opt/libs/binaries" }
    $targetScript = Join-Path $PSScriptRoot "$($archFolder)-$($platform)/add-user-paths.ps1"
}
else {
    Write-Error "Unsupported Operating System."
    return
}

if (Test-Path $targetScript) {
    Write-Host "[OS/ARCH] $platform $currentArch detected. Delegating..." -ForegroundColor Cyan
    
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
