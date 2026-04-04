# Copyright 2026 (C) Navegos. DevelVitorF. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
# file:build-ninja.ps1

param (
    [Parameter(HelpMessage="Base workspace path", Mandatory=$false)]
    [string]$WorkspacePath = "",

    [Parameter(HelpMessage="ninja git repo url", Mandatory=$false)]
    [string]$GitUrl = "https://github.com/Navegos/ninja.git",
    
    [Parameter(HelpMessage="ninja git branch to sync from", Mandatory=$false)]
    [string]$GitBranch = "master",

    [Parameter(HelpMessage="Path for ninja storage", Mandatory=$false)]
    [string]$ninjaInstallDir = "$env:LIBRARIES_PATH\ninja"
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
if ($IsWindows) { $platform = "windows" }
elseif ($IsLinux) { $platform = "linux" }
else {
    Write-Error "Unsupported Operating System."
    return
}

# 3. Delegation Logic
$targetScript = Join-Path $PSScriptRoot "$($archFolder)-$($platform)\build-ninja.ps1"

if (Test-Path $targetScript) {
    Write-Host "[OS/ARCH] $platform $currentArch detected. Delegating..." -ForegroundColor Cyan
    
    & $targetScript @PSBoundParameters
}
else {
    Write-Error "Platform/Arch script not found: $targetScript"
}
