# SPDX-FileCopyrightText: Copyright (c) 2026 Navegos. @DevelVitorF. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
# project: buildtools
# file: build-ninja.ps1
# created: 2026-03-16
# lastModified: 2026-04-26

param (
    [Parameter(HelpMessage = "Base workspace path", Mandatory = $false)]
    [string]$workspacePath = $null,

    [Parameter(HelpMessage = "ninja git repo url", Mandatory = $false)]
    [string]$gitUrl = "https://github.com/ninja-build/ninja.git",
    
    [Parameter(HelpMessage = "ninja git branch to sync from", Mandatory = $false)]
    [string]$gitBranch = "master",

    [Parameter(HelpMessage = "Path for ninja storage", Mandatory = $false)]
    [string]$ninjaInstallDir = $null,
    
    [Parameter(HelpMessage = "Force a full purge of the local Ninja version before continuing", Mandatory = $false)]
    [switch]$forceCleanup,
    
    [Parameter(HelpMessage = "Add's Ninja Machine Environment Variables. Requires Machine Administrator Rights.", Mandatory = $false)]
    [switch]$withMachineEnvironment
)

if ([string]::IsNullOrWhitespace($env:ENVIRONMENT_PATH) -or -not (Test-Path $env:ENVIRONMENT_PATH) -or [string]::IsNullOrWhitespace($env:BINARIES_PATH) -or -not (Test-Path $env:BINARIES_PATH) -or [string]::IsNullOrWhitespace($env:LIBRARIES_PATH) -or -not (Test-Path $env:LIBRARIES_PATH)) {
    Write-Error "User Environment variables missing. With administrator privileges run adduserpaths.ps1 -LibrariesDir 'Path\for\Libraries' -BinariesDir 'Path\for\Binaries' -EnvironmentDir 'Path\for\Environment'"
    return
}

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
    if ([string]::IsNullOrWhitespace($ninjaInstallDir)) { $ninjaInstallDir = "$env:LIBRARIES_PATH\ninja" }
    $targetScript = Join-Path $PSScriptRoot "$($archFolder)-$($platform)\build-ninja.ps1"
}
elseif ($IsLinux) {
    $platform = "linux"
    if ([string]::IsNullOrWhitespace($ninjaInstallDir)) { $ninjaInstallDir = "$env:LIBRARIES_PATH/ninja" }
    $targetScript = Join-Path $PSScriptRoot "$($archFolder)-$($platform)/build-ninja.ps1"
}
else {
    Write-Error "Unsupported Operating System."
    return
}

if (Test-Path $targetScript) {
    Write-Host "[OS/ARCH] $platform $currentArch detected. Delegating..." -ForegroundColor Cyan
    
    # 1. Ensure the default path is captured if not explicitly provided by the user
    $DirParams = 'workspacePath', 'gitUrl', 'gitBranch', 'ninjaInstallDir'
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
