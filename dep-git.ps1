# Copyright 2026 (C) Navegos. DevelVitorF. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
# file:dep-git.ps1

param (
    [Parameter(HelpMessage = "Path for git Installation", Mandatory = $false)]
    [string]$gitInstallDir = $null,
    
    [Parameter(HelpMessage = "Force a full purge of the local GIT version before continuing", Mandatory = $false)]
    [switch]$forceCleanup
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
    if ([string]::IsNullOrWhitespace($gitInstallDir)) { $gitInstallDir = $(Join-Path $env:ProgramFiles "Git") }
    $targetScript = Join-Path $PSScriptRoot "$($archFolder)-$($platform)\dep-git.ps1"
}
elseif ($IsLinux) {
    $platform = "linux"
    if ([string]::IsNullOrWhitespace($gitInstallDir)) { $gitInstallDir = "/usr" }
    $targetScript = Join-Path $PSScriptRoot "$($archFolder)-$($platform)/dep-git.ps1"
}
else {
    Write-Error "Unsupported Operating System."
    return
}

if (Test-Path $targetScript) {
    Write-Host "[OS/ARCH] $platform $currentArch detected. Delegating..." -ForegroundColor Cyan
    
    # 1. Ensure the default path is captured if not explicitly provided by the user
    if (-not $PSBoundParameters.ContainsKey('gitInstallDir')) {
        $PSBoundParameters['gitInstallDir'] = $gitInstallDir
    }
    
    & $targetScript @PSBoundParameters
}
else {
    Write-Error "Platform/Arch script not found: $targetScript"
}
