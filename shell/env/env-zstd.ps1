# SPDX-FileCopyrightText: Copyright (c) 2026 Navegos. @DevelVitorF. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
# project: buildtools
# file: shell/env/env-zstd.ps1
# created: 2026-05-07
# lastModified: 2026-05-13

param (
    [Parameter(HelpMessage = "Target Architecture to build for", Mandatory = $false)]
    [string]$targetArch = $null,
    
    [Parameter(HelpMessage = "Target Platform to build for", Mandatory = $false)]
    [string]$targetPlatform = $null,
    
    [Parameter(HelpMessage = "Path for zstd library storage", Mandatory = $false)]
    [string]$zstdInstallDir = $null,
    
    [Parameter(HelpMessage = "Force a full purge of the local zstd version before continuing", Mandatory = $false)]
    [switch]$forceCleanup,
    
    [Parameter(HelpMessage = "Add's zstd Machine Environment Variables. Requires Machine Administrator Rights.", Mandatory = $false)]
    [switch]$withMachineEnvironment
)

if ([string]::IsNullOrWhitespace($env:ENVIRONMENT_PATH) -or -not (Test-Path $env:ENVIRONMENT_PATH) -or [string]::IsNullOrWhitespace($env:BINARIES_PATH) -or -not (Test-Path $env:BINARIES_PATH) -or [string]::IsNullOrWhitespace($env:LIBRARIES_PATH) -or -not (Test-Path $env:LIBRARIES_PATH) -or [string]::IsNullOrWhitespace($env:BUILDTOOLS_PATH) -or -not (Test-Path $env:BUILDTOOLS_PATH)) {
    Write-Error "User Environment variables missing. Please run add-user-paths.ps1 -LibrariesDir 'Path/for/Libraries' -BinariesDir 'Path/for/Binaries' -EnvironmentDir 'Path/for/Environment' -BuildToolsDir 'Path/for/BuildTools'"
    return
}

# Get the correct list separator for the current OS (; on Win, : on Linux)
#$Sep = [IO.Path]::PathSeparator

# Get the correct folder separator (\ on Win, / on Linux)
#$DirSep = [IO.Path]::DirectorySeparatorChar

# 1. Architecture Detection
$currentArch = [System.Runtime.InteropServices.RuntimeInformation]::ProcessArchitecture.ToString().ToLower()

$archX64 = "x64"
$archArm64 = "arm64"
$platformWindows = "windows"
$platformLinux = "linux"

# Map arch names to folder names
$archMap = @{ "$archX64" = "$archX64"; "$archArm64" = "$archArm64" }
$hostArch = $archMap[$currentArch]

if (-not $archFolder) {
    Write-Error "Unsupported architecture: $currentArch"
    return
}

# Host architecture validation.
if (-not $hostArch) {
    Write-Error "Unsupported Host architecture: $currentArch"
    return
}
else {
    if ([string]::IsNullOrWhitespace($targetArch)) { $targetArch = $hostArch }
}

if ($hostArch -ne $targetArch) {
    Write-Host "Cross-Architecture from $hostArch to $targetArch" -ForegroundColor Cyan
}

# Host platform validation.
if ($env:HOST_IS_WINDOWS) {
    if ([string]::IsNullOrWhitespace($targetPlatform)) { $targetPlatform = $platformWindows }
    $hostPlatform = $platformWindows
}
elseif ($env:HOST_IS_LINUX) {
    if ([string]::IsNullOrWhitespace($targetPlatform)) { $targetPlatform = $platformLinux }
    $hostPlatform = $platformLinux
}
else {
    Write-Error "Unsupported Host Operating System."
    return
}

if ($hostPlatform -ne $targetPlatform) {
    Write-Host "Cross-Platform from $hostPlatform to $targetPlatform" -ForegroundColor Cyan
}

$targetArch = $targetArch.ToLower()
$targetPlatform = $targetPlatform.ToLower()

if ($targetArch -ne $archX64 -and $targetArch -ne $archArm64) {
    Write-Error "Unsupported target architecture: $targetArch. Supported: $archX64, $archArm64"
    return
}

if ($targetPlatform -ne $platformWindows -and $targetPlatform -ne $platformLinux) {
    Write-Error "Unsupported target platform: $targetPlatform. Supported: $platformWindows, $platformLinux"
    return
}

$zstdTarget = "$targetArch-$targetPlatform"

# 2. Platform Detection
if (-not $IsWindows -and -not $IsLinux) {
    Write-Error "Unsupported Operating System."
    return
}

$zstdTargetEnvironmentDir = Join-Path $PSScriptRoot $zstdTarget

$targetScript = Join-Path $zstdTargetEnvironmentDir "env-zstd.ps1"

if (Test-Path $targetScript) {
    Write-Host "[OS/ARCH] $targetPlatform $targetArch detected. Delegating..." -ForegroundColor Cyan
    
    # 1. Ensure the default path is captured if not explicitly provided by the user
    $DirParams = 'workspacePath', 'gitUrl', 'gitBranch', 'zstdInstallDir', 'zstdLibName', 'targetArch', 'targetPlatform', 'targetBuildType'
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
