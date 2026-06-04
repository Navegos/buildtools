# SPDX-FileCopyrightText: Copyright (c) 2026 Navegos. @DevelVitorF. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
# project: buildtools
# file: shell/arch-triple.ps1
# created: 2026-05-10
# lastModified: 2026-05-16

param (
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

    [Parameter(ValueFromRemainingArguments = $true)]
    $RemainingArgs
)

# 1. Bootstrap Environment if variables are missing
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
$archX86_64 = "x86_64"
$archArm64 = "arm64"
$archAarch64 = "aarch64"
$platformWindows = "windows"
$platformLinux = "linux"

$env:archX64 = $archX64
$env:archX86_64 = $archX86_64
$env:archArm64 = $archArm64
$env:archAarch64 = $archAarch64
$env:platformWindows = $platformWindows
$env:platformLinux = $platformLinux

# Map arch names to folder names
$archMap = @{ "$archX64" = "$archX64"; "$archX86_64" = "$archX86_64"; "$archArm64" = "$archArm64"; "$archAarch64" = "$archAarch64" }
$hostArch = $archMap[$currentArch]

# Host architecture validation.
if (-not $hostArch) {
    Write-Error "Unsupported Host architecture: $currentArch"
    return
}
else {
    if ([string]::IsNullOrWhitespace($targetArch)) { $targetArch = $hostArch }
}

# 2. Platform Detection (v5.1 and v6+ compatible)
$isWindowsOS = $IsWindows -or ($env:OS -like "*Windows*")
$isLinuxOS = $IsLinux -or ($null -ne $IsLinux -and $IsLinux)

$targetArch = $targetArch.ToLower()
$targetPlatform = $targetPlatform.ToLower()

$crossArch = $false
if ($hostArch -ne $targetArch) {
    Write-Host "Cross-compiling from $hostArch to $targetArch" -ForegroundColor Cyan
    $crossArch = $true
}
$env:CROSS_ARCH = $crossArch

# Host platform validation.
if ($isWindowsOS) {
    if ([string]::IsNullOrWhitespace($targetPlatform)) { $targetPlatform = $platformWindows }
    $hostPlatform = $platformWindows
}
elseif ($isLinuxOS) {
    if ([string]::IsNullOrWhitespace($targetPlatform)) { $targetPlatform = $platformLinux }
    $hostPlatform = $platformLinux
}
else {
    Write-Error "Unsupported Host Operating System."
    return
}

$env:HOST_ARCH = $hostArch
$env:HOST_PLATFORM = $hostPlatform

$hostIsX64 = $false
$hostIsArm64 = $false
if ($hostArch -eq $archX64 -or $hostArch -eq $archX86_64) {
    $hostIsX64 = $true
}
elseif ($hostArch -eq $archArm64 -or $hostArch -eq $archAarch64) {
    $hostIsArm64 = $true
}
$env:HOST_IS_X64 = $hostIsX64
$env:HOST_IS_ARM64 = $hostIsArm64

$hostIsWindows = $false
$hostIsLinux = $false
if ($hostPlatform -eq $platformWindows) {
    $hostIsWindows = $true
}
elseif ($hostPlatform -eq $platformLinux) {
    $hostIsLinux = $true
}
$env:HOST_IS_WINDOWS = $hostIsWindows
$env:HOST_IS_LINUX = $hostIsLinux

$hostIsX64Windows = $false
$hostIsX64Linux = $false
$hostIsArm64Windows = $false
$hostIsArm64Linux = $false
if ($hostIsX64 -and $hostIsWindows) {
    $hostIsX64Windows = $true
}
elseif ($hostIsX64 -and $hostIsLinux) {
    $hostIsX64Linux = $true
}
elseif ($hostIsArm64 -and $hostIsWindows) {
    $hostIsArm64Windows = $true
}
elseif ($hostIsArm64 -and $hostIsLinux) {
    $hostIsArm64Linux = $true
}
$env:HOST_IS_X64_WINDOWS = $hostIsX64Windows
$env:HOST_IS_X64_LINUX = $hostIsX64Linux
$env:HOST_IS_ARM64_WINDOWS = $hostIsArm64Windows
$env:HOST_IS_ARM64_LINUX = $hostIsArm64Linux

if ([string]::IsNullOrWhitespace($targetHostArch)) {
    $targetHostArch = $hostArch
}
$env:TARGET_HOST_ARCH = $targetHostArch

if ([string]::IsNullOrWhitespace($targetHostPlatform)) {
    $targetHostPlatform = $hostPlatform
}
$env:TARGET_HOST_PLATFORM = $targetHostPlatform

# we are building a toolchain that runs target binaries on the host, so we need to validate the host and target compatibility
$crossHostArch = $false
if ($targetHostArch -ne $hostArch) {
    $crossHostArch = $true
}
$env:CROSS_HOST_ARCH = $crossHostArch

$crossHostPlatform = $false
if ($targetHostPlatform -ne $hostPlatform) {
    $crossHostPlatform = $true
}
$env:CROSS_HOST_PLATFORM = $crossHostPlatform

# the case we are building a toolchain that runs on a different host architecture or platform than the target architecture or platform is a cross-compilation case, as we are not building for the host we are running on
$crossHost = $false
if ($crossHostArch -or $crossHostPlatform) {
    $crossHost = $true
}
$env:CROSS_HOST = $crossHost

$targetHostIsX64 = $false
$targetHostIsArm64 = $false
if ($targetHostArch -eq $archX64 -or $targetHostArch -eq $archX86_64) {
    $targetHostIsX64 = $true
}
elseif ($targetHostArch -eq $archArm64 -or $targetHostArch -eq $archAarch64) {
    $targetHostIsArm64 = $true
}
$env:TARGET_HOST_IS_X64 = $targetHostIsX64
$env:TARGET_HOST_IS_ARM64 = $targetHostIsArm64

$targetHostIsLinux = $false
$targetHostIsWindows = $false
if ($targetHostPlatform -eq $platformWindows) {
    $targetHostIsWindows = $true
}
elseif ($targetHostPlatform -eq $platformLinux) {
    $targetHostIsLinux = $true
}
$env:TARGET_HOST_IS_WINDOWS = $targetHostIsWindows
$env:TARGET_HOST_IS_LINUX = $targetHostIsLinux

$targetHostIsX64Windows = $false
$targetHostIsX64Linux = $false
$targetHostIsArm64Windows = $false
$targetHostIsArm64Linux = $false
if ($targetHostIsX64 -and $targetHostIsWindows) {
    $targetHostIsX64Windows = $true
}
elseif ($targetHostIsX64 -and $targetHostIsLinux) {
    $targetHostIsX64Linux = $true
}
elseif ($targetHostIsArm64 -and $targetHostIsWindows) {
    $targetHostIsArm64Windows = $true
}
elseif ($targetHostIsArm64 -and $targetHostIsLinux) {
    $targetHostIsArm64Linux = $true
}
$env:TARGET_HOST_IS_X64_WINDOWS = $targetHostIsX64Windows
$env:TARGET_HOST_IS_X64_LINUX = $targetHostIsX64Linux
$env:TARGET_HOST_IS_ARM64_WINDOWS = $targetHostIsArm64Windows
$env:TARGET_HOST_IS_ARM64_LINUX = $targetHostIsArm64Linux

$crossPlatform = $false
if ($hostPlatform -ne $targetPlatform) {
    Write-Host "Cross-compiling from $hostPlatform to $targetPlatform" -ForegroundColor Cyan
    $crossPlatform = $true
}
$env:CROSS_PLATFORM = $crossPlatform

$crossCompile = $false
if ($crossArch -or $crossPlatform) {
    $crossCompile = $true
}

if ($targetArch -ne $archX64 -and $targetArch -ne $archX86_64 -and $targetArch -ne $archArm64 -and $targetArch -ne $archAarch64) {
    Write-Error "Unsupported target architecture: $targetArch. Supported: $archX64, $archX86_64, $archArm64, $archAarch64"
    return
}

if ($targetPlatform -ne $platformWindows -and $targetPlatform -ne $platformLinux) {
    Write-Error "Unsupported target platform: $targetPlatform. Supported: $platformWindows, $platformLinux"
    return
}

if ($crossCompile) {
    Write-Host "Cross-compilation detected. Host: $hostPlatform $hostArch -> Target: $targetPlatform $targetArch" -ForegroundColor Yellow
    $env:TARGET_CROSS_COMPILING = $true
    $env:TARGET_NATIVE_COMPILING = $false
}
else {
    Write-Host "Native compilation detected. Host/Target: $hostPlatform $hostArch" -ForegroundColor Green
    $env:TARGET_CROSS_COMPILING = $false
    $env:TARGET_NATIVE_COMPILING = $true
}

if ($targetArch -eq $archX64 -or $targetArch -eq $archX86_64) {
    $env:TARGET_SYSARCH = "x86_64"
    $env:TARGET_ARCH = "$targetArch"
}
elseif ($targetArch -eq $archArm64 -or $targetArch -eq $archAarch64) {
    $env:TARGET_SYSARCH = "aarch64"
    $env:TARGET_ARCH = "$targetArch"
}

if ($targetPlatform -eq $platformWindows) {
    $env:TARGET_SYSPROG = "Windows"
    $env:TARGET_TRIPLE = if ($targetArch -eq $archArm64 -or $targetArch -eq $archAarch64) { "aarch64-pc-windows-msvc" } else { "x86_64-pc-windows-msvc" }
    $env:TARGET_PLATFORM = "windows"
}
elseif ($targetPlatform -eq $platformLinux) {
    $env:TARGET_SYSPROG = "Linux"
    $env:TARGET_TRIPLE = if ($targetArch -eq $archArm64 -or $targetArch -eq $archAarch64) { "aarch64-unknown-linux-gnueabi" } else { "x86_64-unknown-linux-gnu" }
    $env:TARGET_PLATFORM = "linux"
}

# Build has toolchain if cross-compiling or explicitly set
if ($crossCompile -or $isToolchain) {
    if (-not $isToolchain) { $isToolchain = $true }
}
else {
    if (-not $isToolchain) { $isToolchain = $false }
}
$env:IS_TOOLCHAIN = $isToolchain

if ($isToolchain) {
    if ([string]::IsNullOrWhitespace($toolchainInstallDir)) {
        $toolchainInstallDir = Join-Path $env:LIBRARIES_PATH $env:TARGET_TRIPLE
    }
    elseif ($toolchainInstallDir -notlike "*$env:TARGET_TRIPLE*") {
        $toolchainInstallDir = Join-Path $env:LIBRARIES_PATH $env:TARGET_TRIPLE
    }
    $env:TARGET_SYSROOT = $toolchainInstallDir
    $env:TARGET_USR_SYSROOT = Join-Path $toolchainInstallDir "usr"

    if (-not (Test-Path $toolchainInstallDir)) {
        New-Item -Path $toolchainInstallDir -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null
    }

    #If we are cross-compiling toolchain to run on a Linux host and we are running on a Windows host, we need to enable case-sensitive file system for the toolchain directory.
    if ($targetHostIsLinux -and $hostIsWindows) {
        $fsutilScript = Join-Path $env:TEMP "enable-casesensitive-fs.ps1"
        $fsutilScriptContent = @'
# --- 0. Self-Elevation Logic ---
$IsAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $IsAdmin) {
Write-Host "Elevation required to set case sensitive info. Relaunching as Administrator..." -ForegroundColor Yellow
$Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
try {
    Start-Process pwsh.exe -ArgumentList $Arguments -Verb RunAs -Wait
}
catch {
    Start-Process powershell.exe -ArgumentList $Arguments -Verb RunAs -Wait
}
exit
}

fsutil.exe file setCaseSensitiveInfo "VALUE_TOOLCHAIN_DIR" enable
'@ -replace "VALUE_TOOLCHAIN_DIR", $toolchainInstallDir

        $fsutilScriptContent | Out-File -FilePath $fsutilScript -Encoding utf8
        Write-Host "Executing $fsutilScript..." -ForegroundColor Yellow
        try {
            & $fsutilScript
        }
        catch {
            Write-Error "Failed to execute the fsutil script: $($_.Exception.Message)"
        }
        Remove-Item $fsutilScript -Force -ErrorAction SilentlyContinue
    }
}

# Triplet to be used for folder naming and toolchain detection in build scripts
$env:HOST_TRIPLET = "$env:HOST_ARCH-$env:HOST_PLATFORM"
$env:TARGET_HOST_TRIPLET = "$env:TARGET_HOST_ARCH-$env:TARGET_HOST_PLATFORM"
$env:TARGET_TRIPLET = "$env:TARGET_ARCH-$env:TARGET_PLATFORM"
