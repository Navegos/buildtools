# Copyright 2026 (C) Navegos. DevelVitorF. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
# file:adduserpaths.ps1

param (
    [Parameter(HelpMessage = "Base path for library storage", Mandatory = $false)]
    [string]$LibrariesDir = "C:\libs",

    [Parameter(HelpMessage = "Base path for environment-specific configs", Mandatory = $false)]
    [string]$EnvironmentDir = "C:\libs\environment",

    [Parameter(HelpMessage = "Base path for binaries", Mandatory = $false)]
    [string]$BinariesDir = "C:\libs\binaries",
    
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
if ($IsWindows) { $platform = "windows" }
elseif ($IsLinux) { $platform = "linux" }
else {
    Write-Error "Unsupported Operating System."
    return
}

# 3. Delegation Logic
$targetScript = Join-Path $PSScriptRoot "$($archFolder)-$($platform)\add-user-paths.ps1"

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
