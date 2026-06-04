# SPDX-FileCopyrightText: Copyright (c) 2026 Navegos. @DevelVitorF. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
# project: buildtools
# file: build-pkgconf.ps1
# created: 2026-04-12
# lastModified: 2026-05-16

param (
    [Parameter(HelpMessage = "Base workspace path", Mandatory = $false)]
    [string]$workspacePath = $null,
    
    [Parameter(HelpMessage = "pkgconf git repo url", Mandatory = $false)]
    [string]$gitUrl = $null,
    
    [Parameter(HelpMessage = "pkgconf git branch to sync from", Mandatory = $false)]
    [string]$gitBranch = $null,

    [Parameter(HelpMessage = "Path for pkgconf storage", Mandatory = $false)]
    [string]$pkgconfInstallDir = $null,
    
    [Parameter(HelpMessage = "Lib name, if it's building with a different name (fixit by changing it's default name beforehand)", Mandatory = $false)]
    [string]$pkgconfLibName = $null,
    
    [Parameter(HelpMessage = "Target Build Type to build for", Mandatory = $false)]
    [string]$targetBuildType = $null,
    
    [Parameter(HelpMessage = "Target Architecture to build for", Mandatory = $false)]
    [string]$targetArch = $null,
    
    [Parameter(HelpMessage = "Target Platform to build for", Mandatory = $false)]
    [string]$targetPlatform = $null,
    
    [Parameter(HelpMessage = "Target Host Architecture to build for", Mandatory = $false)]
    [string]$targetHostArch = $null,
    
    [Parameter(HelpMessage = "Target Host Platform to build for", Mandatory = $false)]
    [string]$targetHostPlatform = $null,
    
    [Parameter(HelpMessage = "Path for toolchain installation, expects target triple at the end of path", Mandatory = $false)]
    [string]$toolchainInstallDir = $null,
    
    [Parameter(HelpMessage = "Indicates if the target is part of a toolchain", Mandatory = $false)]
    [switch]$isToolchain,

    [Parameter(HelpMessage = "Force a full purge of the local pkgconf version before continuing", Mandatory = $false)]
    [switch]$forceCleanup,
    
    [Parameter(HelpMessage = "Add's pkgconf Machine Environment Variables. Requires Machine Administrator Rights.", Mandatory = $false)]
    [switch]$withMachineEnvironment,

    [Parameter(ValueFromRemainingArguments = $true)]
    $RemainingArgs
)

if ([string]::IsNullOrWhitespace($env:ENVIRONMENT_PATH) -or -not (Test-Path $env:ENVIRONMENT_PATH) -or [string]::IsNullOrWhitespace($env:BINARIES_PATH) -or -not (Test-Path $env:BINARIES_PATH) -or [string]::IsNullOrWhitespace($env:LIBRARIES_PATH) -or -not (Test-Path $env:LIBRARIES_PATH) -or [string]::IsNullOrWhitespace($env:BUILDTOOLS_PATH) -or -not (Test-Path $env:BUILDTOOLS_PATH)) {
    Write-Error "User Environment variables missing. Please run add-user-paths.ps1 -LibrariesDir 'Path/for/Libraries' -BinariesDir 'Path/for/Binaries' -EnvironmentDir 'Path/for/Environment' -BuildToolsDir 'Path/for/BuildTools'"
    return
}

# Get the correct list separator for the current OS (; on Win, : on Linux)
#$Sep = [IO.Path]::PathSeparator

# Get the correct folder separator (\ on Win, / on Linux)
$DirSep = [IO.Path]::DirectorySeparatorChar

# 1. Architecture Detection
if (-not $env:HOST_ARCH -or $isToolchain) {
    $archTripleScript = Join-Path $PSScriptRoot "arch-triple.ps1"
    if (Test-Path $archTripleScript) {
        # 1. Ensure the default path is captured if not explicitly provided by the user
        $ArchDirParams = 'targetArch', 'targetPlatform', 'targetHostArch', 'targetHostPlatform', 'toolchainInstallDir'
        foreach ($ArchParamName in $ArchDirParams) {
            if (-not $PSBoundParameters.ContainsKey($ArchParamName)) {
                # Dynamically get the value of the local variable with the same name
                $PSBoundParameters[$ArchParamName] = Get-Variable -Name $ArchParamName -ValueOnly
            }
        }

        & $archTripleScript @PSBoundParameters
    }
    else {
        Write-Error "Arch triple script not found: $archTripleScript"
        return
    }
}

if ([string]::IsNullOrWhitespace($gitUrl)) { $gitUrl = "https://github.com/pkgconf/pkgconf.git" }
if ([string]::IsNullOrWhitespace($gitBranch)) { $gitBranch = "master" }
if ([string]::IsNullOrWhitespace($pkgconfLibName)) { $pkgconfLibName = "pkgconf" }
if ($isToolchain) {
    if ([string]::IsNullOrWhitespace($pkgconfInstallDir)) { $pkgconfInstallDir = Join-Path $env:TARGET_USR_SYSROOT $pkgconfLibName }
    $targetScript = Join-Path $PSScriptRoot "$env:HOST_TRIPLET${DirSep}$env:TARGET_HOST_TRIPLE${DirSep}build-pkgconf.ps1"
    $currentArch = $env:TARGET_HOST_ARCH
    $currentPlatform = $env:TARGET_HOST_PLATFORM
}
else {
    if ([string]::IsNullOrWhitespace($pkgconfInstallDir)) { $pkgconfInstallDir = Join-Path $env:LIBRARIES_PATH "$env:HOST_TRIPLET${DirSep}$pkgconfLibName" }
    $targetScript = Join-Path $PSScriptRoot "$env:HOST_TRIPLET${DirSep}build-build-pkgconf.ps1.ps1"
    $currentArch = $env:HOST_ARCH
    $currentPlatform = $env:HOST_PLATFORM
}
if ([string]::IsNullOrWhitespace($targetBuildType)) { $targetBuildType = "Release" }

if (Test-Path $targetScript) {
    Write-Host "[OS/ARCH] $currentPlatform $currentArch detected. Delegating..." -ForegroundColor Cyan
    
    # 1. Ensure the default path is captured if not explicitly provided by the user
    $DirParams = 'workspacePath', 'gitUrl', 'gitBranch', 'pkgconfLibName', 'pkgconfInstallDir', 'targetBuildType'
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
