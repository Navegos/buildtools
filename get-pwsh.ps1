# Copyright 2026 (C) Navegos. DevelVitorF. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
# file:get-pwsh.ps1

param (
    [Parameter(HelpMessage = "Path for PowerShell Installation", Mandatory = $false)]
    [string]$powershellInstallDir = $null
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
    if ([string]::IsNullOrWhitespace($powershellInstallDir)) { $powershellInstallDir = $(Join-Path $env:ProgramFiles "PowerShell") }
    $targetScript = Join-Path $PSScriptRoot "$($archFolder)-$($platform)\get-pwsh.ps1"
}
elseif ($IsLinux) {
    $platform = "linux"
    if ([string]::IsNullOrWhitespace($powershellInstallDir)) { $powershellInstallDir = "/opt/microsoft/powershell" }
    $targetScript = Join-Path $PSScriptRoot "$($archFolder)-$($platform)/get-pwsh.ps1"
}
else {
    Write-Error "Unsupported Operating System."
    return
}

if (Test-Path $targetScript) {
    Write-Host "[OS/ARCH] $platform $currentArch detected. Delegating..." -ForegroundColor Cyan
    
    # 1. Ensure the default path is captured if not explicitly provided by the user
    if (-not $PSBoundParameters.ContainsKey('powershellInstallDir')) {
        $PSBoundParameters['powershellInstallDir'] = $powershellInstallDir
    }
    
    & $targetScript @PSBoundParameters
}
else {
    Write-Error "Platform/Arch script not found: $targetScript"
}
