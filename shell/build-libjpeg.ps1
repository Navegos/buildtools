# SPDX-FileCopyrightText: Copyright (c) 2026 Navegos. @DevelVitorF. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
# project: buildtools
# file: build-libjpeg.ps1

param (
    [Parameter(HelpMessage = "Base workspace path", Mandatory = $false)]
    [string]$workspacePath = $null,

    [Parameter(HelpMessage = "libjpeg git repo url", Mandatory = $false)]
    [string]$gitUrl = "https://github.com/libjpeg-turbo/libjpeg-turbo.git",
    
    [Parameter(HelpMessage = "libjpeg git branch to sync from", Mandatory = $false)]
    [string]$gitBranch = "main",

    [Parameter(HelpMessage = "Path for libjpeg library storage", Mandatory = $false)]
    [string]$libjpegInstallDir = $null,
    
    [Parameter(HelpMessage = "Lib name, if it's building with a different name", Mandatory = $false)]
    [string]$libjpegLibName = "jpeg",
    
    [Parameter(HelpMessage = "ABI version, if it's building with a different version", Mandatory = $false)]
    [string]$libjpegABIVersion = "8",
    
    [Parameter(HelpMessage = "turbojpeg Lib name, if it's building with a different name", Mandatory = $false)]
    [string]$turbojpegLibName = "turbojpeg",
    
    [Parameter(HelpMessage = "Force a full purge of the local libjpeg version before continuing", Mandatory = $false)]
    [switch]$forceCleanup,
    
    [Parameter(HelpMessage = "Add's libjpeg Machine Environment Variables", Mandatory = $false)]
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

$archMap = @{ "x64" = "x64"; "arm64" = "arm64" }
$archFolder = $archMap[$currentArch]

if (-not $archFolder) {
    Write-Error "Unsupported architecture: $currentArch"
    return
}

# 2. Platform Detection
if ($env:HOST_IS_WINDOWS) {
    $platform = "windows"
    if ([string]::IsNullOrWhitespace($libjpegInstallDir)) { $libjpegInstallDir = "$env:LIBRARIES_PATH\libjpeg" }
    $targetScript = Join-Path $PSScriptRoot "$($archFolder)-$($platform)\build-libjpeg.ps1"
}
elseif ($env:HOST_IS_LINUX) {
    $platform = "linux"
    if ([string]::IsNullOrWhitespace($libjpegInstallDir)) { $libjpegInstallDir = "$env:LIBRARIES_PATH/libjpeg" }
    $targetScript = Join-Path $PSScriptRoot "$($archFolder)-$($platform)/build-libjpeg.ps1"
}
else {
    Write-Error "Unsupported Operating System."
    return
}

if (Test-Path $targetScript) {
    Write-Host "[OS/ARCH] $platform $currentArch detected. Delegating..." -ForegroundColor Cyan
    
    # 1. Ensure the default path is captured if not explicitly provided by the user
    $DirParams = 'workspacePath', 'gitUrl', 'gitBranch', 'libjpegInstallDir', 'libjpegLibName', 'libjpegABIVersion', 'turbojpegLibName'
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
