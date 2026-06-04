# SPDX-FileCopyrightText: Copyright (c) 2026 Navegos. @DevelVitorF. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
# project: buildtools
# file: build-libxml2.ps1
# created: 2026-04-11
# lastModified: 2026-05-13

param (
    [Parameter(HelpMessage = "Base workspace path", Mandatory = $false)]
    [string]$workspacePath = $null,
    
    [Parameter(HelpMessage = "libxml2 git repo url", Mandatory = $false)]
    [string]$gitUrl = "https://github.com/GNOME/libxml2.git",
    
    [Parameter(HelpMessage = "libxml2 git branch to sync from", Mandatory = $false)]
    [string]$gitBranch = "master",
    
    [Parameter(HelpMessage = "Path for libxml2 library storage", Mandatory = $false)]
    [string]$libxml2InstallDir = $null,
    
    [Parameter(HelpMessage = "Lib name, if it's building with a different name (fixit by changing it's default name beforehand)", Mandatory = $false)]
    [string]$libxml2LibName = "libxml2",
    
    [Parameter(HelpMessage = "Force a full purge of the local libxml2 version before continuing", Mandatory = $false)]
    [switch]$forceCleanup,
    
    [Parameter(HelpMessage = "Add's libxml2 Machine Environment Variables. Requires Machine Administrator Rights.", Mandatory = $false)]
    [switch]$withMachineEnvironment,

    [Parameter(ValueFromRemainingArguments = $true)]
    $RemainingArgs
)

if ([string]::IsNullOrWhitespace($env:ENVIRONMENT_PATH) -or -not (Test-Path $env:ENVIRONMENT_PATH) -or [string]::IsNullOrWhitespace($env:BINARIES_PATH) -or -not (Test-Path $env:BINARIES_PATH) -or [string]::IsNullOrWhitespace($env:LIBRARIES_PATH) -or -not (Test-Path $env:LIBRARIES_PATH) -or [string]::IsNullOrWhitespace($env:BUILDTOOLS_PATH) -or -not (Test-Path $env:BUILDTOOLS_PATH)) {
    Write-Error "User Environment variables missing. Please run add-user-paths.ps1 -LibrariesDir 'Path/for/Libraries' -BinariesDir 'Path/for/Binaries' -EnvironmentDir 'Path/for/Environment' -BuildToolsDir 'Path/for/BuildTools'"
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
if ($env:HOST_IS_WINDOWS) {
    $platform = "windows"
    if ([string]::IsNullOrWhitespace($libxml2InstallDir)) { $libxml2InstallDir = "$env:LIBRARIES_PATH\libxml2" }
    $targetScript = Join-Path $PSScriptRoot "$($archFolder)-$($platform)\build-libxml2.ps1"
}
elseif ($env:HOST_IS_LINUX) {
    $platform = "linux"
    if ([string]::IsNullOrWhitespace($libxml2InstallDir)) { $libxml2InstallDir = "$env:LIBRARIES_PATH/libxml2" }
    $targetScript = Join-Path $PSScriptRoot "$($archFolder)-$($platform)/build-libxml2.ps1"
}
else {
    Write-Error "Unsupported Operating System."
    return
}

if (Test-Path $targetScript) {
    Write-Host "[OS/ARCH] $platform $currentArch detected. Delegating..." -ForegroundColor Cyan
    
    # 1. Ensure the default path is captured if not explicitly provided by the user
    $DirParams = 'workspacePath', 'gitUrl', 'gitBranch', 'libxml2InstallDir', 'libxml2LibName'
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
