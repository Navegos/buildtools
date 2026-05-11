# SPDX-FileCopyrightText: Copyright (c) 2026 Navegos. @DevelVitorF. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
# project: buildtools
# file: build-openssl.ps1
# created: 2026-05-02
# lastModified: 2026-05-11

param (
    [Parameter(HelpMessage = "Base workspace path", Mandatory = $false)]
    [string]$workspacePath = $null,
    
    [Parameter(HelpMessage = "OpenSSL git repo url", Mandatory = $false)]
    [string]$gitUrl = "https://github.com/openssl/openssl.git",
    
    [Parameter(HelpMessage = "OpenSSL git branch to sync from", Mandatory = $false)]
    [string]$gitBranch = "master",

    [Parameter(HelpMessage = "Path for OpenSSL installation", Mandatory = $false)]
    [string]$opensslInstallDir = $null,
    
    [Parameter(HelpMessage = "Path for OpenSSL configuration files directory", Mandatory = $false)]
    [string]$opensslConfigDir = $null,

    [Parameter(HelpMessage = "Force a full purge of the local OpenSSL version before continuing", Mandatory = $false)]
    [switch]$forceCleanup,
    
    [Parameter(HelpMessage = "Add's OpenSSL Machine Environment Variables. Requires Machine Administrator Rights.", Mandatory = $false)]
    [switch]$withMachineEnvironment
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
if ($IsWindows) {
    $platform = "windows"
    if ([string]::IsNullOrWhitespace($opensslInstallDir)) { $opensslInstallDir = "$env:LIBRARIES_PATH\openssl" }
    $targetScript = Join-Path $PSScriptRoot "$($archFolder)-$($platform)\build-openssl.ps1"
}
elseif ($IsLinux) {
    $platform = "linux"
    if ([string]::IsNullOrWhitespace($opensslInstallDir)) { $opensslInstallDir = "$env:LIBRARIES_PATH/openssl" }
    $targetScript = Join-Path $PSScriptRoot "$($archFolder)-$($platform)/build-openssl.ps1"
}
else {
    Write-Error "Unsupported Operating System."
    return
}

if (Test-Path $targetScript) {
    Write-Host "[OS/ARCH] $platform $currentArch detected. Delegating..." -ForegroundColor Cyan
    
    # Ensure the default path is captured if not explicitly provided by the user
    $DirParams = 'workspacePath', 'gitUrl', 'gitBranch', 'opensslInstallDir'
    foreach ($ParamName in $DirParams) {
        if (-not $PSBoundParameters.ContainsKey($ParamName)) {
            $PSBoundParameters[$ParamName] = Get-Variable -Name $ParamName -ValueOnly
        }
    }

    & $targetScript @PSBoundParameters
}
else {
    Write-Error "Platform/Arch script not found: $targetScript"
}
