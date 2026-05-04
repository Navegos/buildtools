# SPDX-FileCopyrightText: Copyright (c) 2026 Navegos. @DevelVitorF. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
# project: buildtools
# file: x64-windows/dep-qt.ps1
# created: 2026-05-03
# lastModified: 2026-05-03

param (
    [Parameter(HelpMessage = "Path for Qt storage", Mandatory = $false)]
    [string]$qtInstallDir = "$env:LIBRARIES_PATH\Qt",
    
    [Parameter(HelpMessage = "Qt Version", Mandatory = $false)]
    [string]$qtVersion = "6.11.0",
    
    [Parameter(HelpMessage = "Force a full purge of the local Qt version before continuing", Mandatory = $false)]
    [switch]$forceCleanup,
    
    [Parameter(HelpMessage = "Add's Qt Machine Environment Variables. Requires Machine Administrator Rights.", Mandatory = $false)]
    [switch]$withMachineEnvironment,
    
    [Parameter(HelpMessage = "Install all architectures and targets (default true)", Mandatory = $false)]
    [bool]$installAll = $true
)

# Capture parameters
$QtWithMachineEnvironment = $withMachineEnvironment
$QtForceCleanup = $forceCleanup

if ([string]::IsNullOrWhitespace($env:ENVIRONMENT_PATH) -or -not (Test-Path $env:ENVIRONMENT_PATH) -or [string]::IsNullOrWhitespace($env:BINARIES_PATH) -or -not (Test-Path $env:BINARIES_PATH) -or [string]::IsNullOrWhitespace($env:LIBRARIES_PATH) -or -not (Test-Path $env:LIBRARIES_PATH)) {
    Write-Error "User Environment variables missing. With administrator privileges run adduserpaths.ps1 -LibrariesDir 'Path\for\Libraries' -BinariesDir 'Path\for\Binaries' -EnvironmentDir 'Path\for\Environment'"
    return
}

$EnvironmentDir = "$env:ENVIRONMENT_PATH"

# --- Initialize Python environment if missing (required for aqtinstall fallback) ---
if ([string]::IsNullOrWhitespace($env:BINARY_PYTHON) -or -not (Test-Path $env:BINARY_PYTHON)) {
    $pythonEnvScript = Join-Path $EnvironmentDir "env-python.ps1"
    if (Test-Path $pythonEnvScript) { . $pythonEnvScript } 
    if ([string]::IsNullOrWhitespace($env:BINARY_PYTHON) -or -not (Test-Path $env:BINARY_PYTHON)) {
        $deppythonEnvScript = Join-Path $PSScriptRoot "dep-python.ps1"
        if (Test-Path $deppythonEnvScript) { . $deppythonEnvScript }
        else {
            Write-Error "CRITICAL: Cannot load Python environment. python is missing and $deppythonEnvScript was not found."
            return
        }
    }
}

$GlobalBinDir = "$env:BINARIES_PATH"
$qttools = @("qmake.exe", "windeployqt.exe", "moc.exe", "uic.exe", "rcc.exe")

foreach ($qttool in $qttools) {
    $target = Join-Path $GlobalBinDir $qttool
    if (Test-Path $target) { Remove-Item $target -Force -ErrorAction SilentlyContinue }
}

$qtEnvScript = Join-Path $EnvironmentDir "env-qt.ps1"
$qtMachineEnvScript = Join-Path $EnvironmentDir "machine-env-qt.ps1"

# Check for existing official installer footprint
$maintenanceExe = Join-Path $qtInstallDir "MaintenanceTool.exe"
$maintenanceBat = Join-Path $qtInstallDir "MaintenanceTool.bat"
$maintenanceDat = Join-Path $qtInstallDir "MaintenanceTool.dat"
$hasMaintenanceTool = (Test-Path $maintenanceExe) -or (Test-Path $maintenanceBat) -or (Test-Path $maintenanceDat)

$qtVersionPath = Join-Path $qtInstallDir $qtVersion
$qtArchPath = $null

if (Test-Path $qtVersionPath) {
    # Locate MSVC architecture folder like msvc2019_64
    $qtArchDir = Get-ChildItem -Path $qtVersionPath -Directory | Where-Object { $_.Name -like "msvc*_64" } | Select-Object -First 1
    if ($qtArchDir) {
        $qtArchPath = $qtArchDir.FullName
    }
}

# --- 1. Cleanup Mechanism ---
function Invoke-QtVersionPurge {
    param ([string]$InstallPath)
    Write-Host "--- Initiating Qt Purge ---" -ForegroundColor Cyan

    if ($QtWithMachineEnvironment) {
        $qtCleanMachineEnvScript = Join-Path $env:TEMP "clean-machine-env-qt.ps1"

        $CleanMachineEnvContent = @'
# Qt Clean Machine Environment Setup

# --- 0. Self-Elevation Logic ---
$IsAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$ScopeColor = "Cyan"

if (-not $IsAdmin) {
    Write-Host "Elevation required to clean Qt system variables. Relaunching as Administrator..." -ForegroundColor Yellow
    $Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    foreach ($Parameter in $PSBoundParameters.GetEnumerator()) {
        if ($Parameter.Value -is [switch]) {
            if ($Parameter.Value) { $Arguments += " -$($Parameter.Key)" }
        }
        else {
            $Arguments += " -$($Parameter.Key) `"$($Parameter.Value)`""
        }
    }

    try { Start-Process pwsh.exe -ArgumentList $Arguments -Verb RunAs -ErrorAction Stop }
    catch { Start-Process powershell.exe -ArgumentList $Arguments -Verb RunAs }
    exit
}

$qtroot = "VALUE_ROOT_PATH"

$TargetScope = if ($IsAdmin) { "Machine" } else { "User" }
$RegPath = if ($IsAdmin) { "System\CurrentControlSet\Control\Session Manager\Environment" } else { "Environment" }
$RegRoot = if ($IsAdmin) { "LocalMachine" } else { "CurrentUser" }

# 1. Registry Cleanup (EXTCOMPLIBS_PATH)
$RegKey = [Microsoft.Win32.Registry]::$RegRoot.OpenSubKey($RegPath, $true)
$RawPath = $RegKey.GetValue("EXTCOMPLIBS_PATH", "", [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)

# Cleanup: Remove empty strings, any path containing $qtroot
$CleanPath = ($RawPath -split ';' | Where-Object { $_ -notlike "*$qtroot*" }) -join ";"
$RegKey.SetValue("EXTCOMPLIBS_PATH", $CleanPath, [Microsoft.Win32.RegistryValueKind]::ExpandString)
$env:EXTCOMPLIBS_PATH = $CleanPath
$RegKey.Close()

Write-Host "[REMOVED] ($TargetScope) all '*$qtroot*' removed from EXTCOMPLIBS_PATH" -ForegroundColor $ScopeColor
'@  -replace "VALUE_ROOT_PATH", $InstallPath

        $CleanMachineEnvContent | Out-File -FilePath $qtCleanMachineEnvScript -Encoding utf8
        Write-Host "Created: $qtCleanMachineEnvScript" -ForegroundColor Gray
        
        Write-Host ""
        $choice = Read-Host "Administrator rights required to Clean Machine Environment Qt changes? (y/n)"
        if ($choice -eq 'y' -or $choice -eq 'Y') {
            Write-Host "Executing $qtCleanMachineEnvScript..." -ForegroundColor Yellow
            try { & $qtCleanMachineEnvScript }
            catch { Write-Error "Failed to execute the Clean Machine Environment script: $($_.Exception.Message)"; return }
        } else {
            Write-Error "Skipped Clean Machine Environment Qt changes."
            return
        }
        Remove-Item $qtCleanMachineEnvScript -Recurse -Force -ErrorAction SilentlyContinue
    }

    if (Test-Path $qtEnvScript) { Write-Host "  [DELETING] $qtEnvScript" -ForegroundColor Yellow; Remove-Item $qtEnvScript -Recurse -Force -ErrorAction SilentlyContinue }
    if (Test-Path $qtMachineEnvScript) { Write-Host "  [DELETING] $qtMachineEnvScript" -ForegroundColor Yellow; Remove-Item $qtMachineEnvScript -Recurse -Force -ErrorAction SilentlyContinue }
    
    if (Test-Path $InstallPath) {
        if ($hasMaintenanceTool -and (Test-Path $qtVersionPath)) {
            Write-Host "  [DELETING] Official Qt version folder: $qtVersionPath" -ForegroundColor Yellow
            Remove-Item $qtVersionPath -Recurse -Force -ErrorAction SilentlyContinue
        } elseif (-not $hasMaintenanceTool) {
            Write-Host "  [DELETING] Base Install Path: $InstallPath" -ForegroundColor Yellow
            Remove-Item $InstallPath -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    
    foreach ($qttool in $qttools) {
        $target = Join-Path $GlobalBinDir $qttool
        if (Test-Path $target) { Remove-Item $target -Force -ErrorAction SilentlyContinue; Write-Host "  [REMOVED] Link: $qttool" -ForegroundColor Gray }
    }
    
    Get-ChildItem Env:\QT_* | ForEach-Object { Remove-Item Env:\$($_.Name) -ErrorAction SilentlyContinue }
    Get-ChildItem Env:\QML2_* | ForEach-Object { Remove-Item Env:\$($_.Name) -ErrorAction SilentlyContinue }
    
    $CurrentCMakePrefixPath = $env:CMAKE_PREFIX_PATH
    $CleanedCMakePrefixPathList = $CurrentCMakePrefixPath -split ';' | Where-Object { 
        -not [string]::IsNullOrWhitespace($_) -and 
        $_ -notlike "*$InstallPath*"
    }
    $NewCMakePrefixPath = ($CleanedCMakePrefixPathList -join ";").Replace(";;", ";")
    $NewCMakePrefixPath = ($NewCMakePrefixPath + ";").Replace(";;", ";")
    $env:CMAKE_PREFIX_PATH = $NewCMakePrefixPath
    
    $CurrentIncludePath = $env:INCLUDE
    $CleanedIncludePathList = $CurrentIncludePath -split ';' | Where-Object { 
        -not [string]::IsNullOrWhitespace($_) -and 
        $_ -notlike "*$InstallPath*"
    }
    $NewIncludePath = ($CleanedIncludePathList -join ";").Replace(";;", ";")
    $NewIncludePath = ($NewIncludePath + ";").Replace(";;", ";")
    $env:INCLUDE = $NewIncludePath
    
    $CurrentLibPath = $env:LIB
    $CleanedLibPathList = $CurrentLibPath -split ';' | Where-Object { 
        -not [string]::IsNullOrWhitespace($_) -and 
        $_ -notlike "*$InstallPath*"
    }
    $NewLibPath = ($CleanedLibPathList -join ";").Replace(";;", ";")
    $NewLibPath = ($NewLibPath + ";").Replace(";;", ";")
    $env:LIB = $NewLibPath
    
    $CurrentPath = $env:PATH
    $CleanedPathList = $CurrentPath -split ';' | Where-Object { 
        -not [string]::IsNullOrWhitespace($_) -and 
        $_ -notlike "*$InstallPath*"
    }
    $NewPath = ($CleanedPathList -join ";").Replace(";;", ";")
    $NewPath = ($NewPath + ";").Replace(";;", ";")
    $env:PATH = $NewPath
    
    Write-Host "--- Qt Purge Complete ---" -ForegroundColor Green
}

if ($QtForceCleanup) {
    Invoke-QtVersionPurge -InstallPath $qtInstallDir
    $qtArchPath = $null
}

# --- 2. Install or Skip ---
if (-not $qtArchPath) {
    Write-Host "Qt $qtVersion for MSVC not found at $qtInstallDir." -ForegroundColor Yellow
    
    $packageList = @'
    aqtinstall
'@

    # 2. Parse the string into a clean array
    $packages = $packageList -split '\s+' | Where-Object { $_ -match '\S' }

    # Install via aqtinstall headlessly
    $uvExe = Join-Path $env:PYTHON_SCRIPTS "uv.exe"
    Write-Host "Fetching aqtinstall..." -ForegroundColor Cyan
    if (Test-Path $uvExe) {
        & $env:BINARY_PYTHON -m uv pip install -U $packages --no-warn-script-location | Out-Null
    } else {
        & $env:BINARY_PYTHON -m pip install -U $packages --no-warn-script-location | Out-Null
    }
    
    if ($installAll) {
        $qtInstallList = @(
            @{ Target = "desktop"; Arch = "win64_msvc2022_64" },
            @{ Target = "desktop"; Arch = "win64_msvc2022_arm64" },
            @{ Target = "desktop"; Arch = "win64_mingw" },
            @{ Target = "desktop"; Arch = "win64_llvm_mingw" },
            @{ Target = "android"; Arch = "android_arm64_v8a" },
            @{ Target = "android"; Arch = "android_armv7" },
            @{ Target = "android"; Arch = "android_x86" },
            @{ Target = "android"; Arch = "android_x86_64" },
            @{ Target = "wasm"; Arch = "wasm_multithread" },
            @{ Target = "wasm"; Arch = "wasm_singlethread" }
        )
    } else {
        $qtInstallList = @(
            @{ Target = "desktop"; Arch = "win64_msvc2022_64" }
        )
    }

    Write-Host "Downloading Qt $qtVersion via aqtinstall..." -ForegroundColor Cyan
    
    foreach ($item in $qtInstallList) {
        Write-Host " -> Installing $($item.Target) / $($item.Arch)..." -ForegroundColor Cyan
        & $env:BINARY_PYTHON -m aqt install-qt windows $($item.Target) $qtVersion $($item.Arch) --outputdir $qtInstallDir -m all
        if ($LASTEXITCODE -ne 0) { Write-Warning "aqtinstall failed to install Qt $qtVersion for $($item.Arch). Skipping..." }
    }

    if ($installAll) {
        Write-Host " -> Installing Source (Src)..." -ForegroundColor Cyan
        & $env:BINARY_PYTHON -m aqt install-src windows $qtVersion --outputdir $qtInstallDir
        if ($LASTEXITCODE -ne 0) { Write-Warning "aqtinstall failed to install Qt $qtVersion Source. Skipping..." }
    }

    Write-Host "Qt $qtVersion installed successfully!" -ForegroundColor DarkGreen

    # Re-evaluate path
    if (Test-Path $qtVersionPath) {
        $qtArchDir = Get-ChildItem -Path $qtVersionPath -Directory | Where-Object { $_.Name -like "msvc2022_64" } | Select-Object -First 1
        if ($qtArchDir) {
            $qtArchPath = $qtArchDir.FullName
        }
    }
} else {
    Write-Host "[SKIP] Qt $qtVersion is already installed at: $qtArchPath" -ForegroundColor Green
}

# Validation Check
if (-not $qtArchPath -or -not (Test-Path $qtArchPath)) {
    Write-Error "CRITICAL: Qt arch path resolution failed. Target missing at $qtArchPath"
    return
}

$versionFile = Join-Path $qtArchPath "version.json"

if (-not (Test-Path $versionFile)) {
    $versionInfo = @{
        version    = $qtVersion;
        arch       = "msvc_x64";
        date       = (Get-Date).ToString("yyyy-MM-dd");
        type       = if ($hasMaintenanceTool) { "official_installer" } else { "aqtinstall" };
    }
    $versionInfo | ConvertTo-Json | Out-File -FilePath $versionFile -Encoding utf8 -Force
}

# --- 3. Finalize Helpers & Symlinks ---
$qtBinPath = Join-Path $qtArchPath "bin"
$qtLibPath = Join-Path $qtArchPath "lib"
$qtIncludePath = Join-Path $qtArchPath "include"
$qtCMakePath = Join-Path $qtLibPath "cmake"
$qtPluginsPath = Join-Path $qtArchPath "plugins"
$qtQmlPath = Join-Path $qtArchPath "qml"

$qmakeExePath = Join-Path $qtBinPath "qmake.exe"

if (Test-Path $qmakeExePath) {
    Write-Host "Generating environment helper script..." -ForegroundColor Cyan

    $qtArchPath = $qtArchPath.TrimEnd('\')
    $qtBinPath = $qtBinPath.TrimEnd('\')

    $EnvContent = @'
# Qt Environment Setup
$qtroot = "VALUE_ROOT_PATH"
$qtbin = "VALUE_BIN_PATH"
$qtinclude = "VALUE_INCLUDE_PATH"
$qtlibrary = "VALUE_LIB_PATH"
$qtcmake = "VALUE_CMAKE_PATH"
$qtplugins = "VALUE_PLUGINS_PATH"
$qtqml = "VALUE_QML_PATH"
$qtversion = "VALUE_VERSION"
$env:QT_PATH = $qtroot
$env:QT_ROOT = $qtroot
$env:QT_BIN = $qtbin
$env:QT_INCLUDE_DIR = $qtinclude
$env:QT_LIBRARY_DIR = $qtlibrary
$env:QT_PLUGIN_PATH = $qtplugins
$env:QML2_IMPORT_PATH = $qtqml
if ($env:CMAKE_PREFIX_PATH -notlike "*$qtcmake*") { $env:CMAKE_PREFIX_PATH = $qtcmake + ";" + $env:CMAKE_PREFIX_PATH; $env:CMAKE_PREFIX_PATH = ($env:CMAKE_PREFIX_PATH).Replace(";;", ";") }
if ($env:INCLUDE -notlike "*$qtinclude*") { $env:INCLUDE = $qtinclude + ";" + $env:INCLUDE; $env:INCLUDE = ($env:INCLUDE).Replace(";;", ";") }
if ($env:LIB -notlike "*$qtlibrary*") { $env:LIB = $qtlibrary + ";" + $env:LIB; $env:LIB = ($env:LIB).Replace(";;", ";") }
"$qtbin", "$qtroot" | ForEach-Object { if ($env:PATH -notlike "*$_*") { $env:PATH = $_ + ";" + $env:PATH; $env:PATH = ($env:PATH).Replace(";;", ";") } }
Write-Host "Qt Environment Loaded (Version: $qtversion) (Bin: $qtbin)" -ForegroundColor Green
Write-Host "QT_ROOT: $env:QT_ROOT" -ForegroundColor Gray
'@  -replace "VALUE_BIN_PATH", $qtBinPath `
    -replace "VALUE_ROOT_PATH", $qtInstallDir `
    -replace "VALUE_INCLUDE_PATH", $qtIncludePath `
    -replace "VALUE_LIB_PATH", $qtLibPath `
    -replace "VALUE_CMAKE_PATH", $qtCMakePath `
    -replace "VALUE_PLUGINS_PATH", $qtPluginsPath `
    -replace "VALUE_QML_PATH", $qtQmlPath `
    -replace "VALUE_VERSION", $qtVersion

    $EnvContent | Out-File -FilePath $qtEnvScript -Encoding utf8
    Write-Host "Created: $qtEnvScript" -ForegroundColor Gray

    if (Test-Path $qtEnvScript) { . $qtEnvScript } else { Write-Error "Qt dep install failed."; return }
    
    Write-Host "Creating global symlinks to: $GlobalBinDir..." -ForegroundColor Cyan
    foreach ($qttool in $qttools) {
        $source = Join-Path $qtBinPath $qttool
        $target = Join-Path $GlobalBinDir $qttool
        if (Test-Path $source) {
            if (Test-Path $target) { Remove-Item $target -Force -ErrorAction SilentlyContinue }
            try { New-Item -Path $target -ItemType SymbolicLink -Value $source -ErrorAction Stop | Out-Null; Write-Host "[LINKED] $qttool" -ForegroundColor Gray } 
            catch { New-Item -Path $target -ItemType HardLink -Value $source | Out-Null; Write-Host "[HARDLINKED] $qttool (Global) -> $source" -ForegroundColor Gray }
        }
    }

    Write-Host "[LINKED] Qt is now globally available via %BINARIES_PATH%" -ForegroundColor Green
    Write-Host "QMake Version: $(& $qmakeExePath -v | Select-Object -First 2)" -ForegroundColor Gray
    
    if ($QtWithMachineEnvironment) {
        $MachineEnvContent = @'
# Qt Machine Environment Setup

# --- 0. Self-Elevation Logic ---
$IsAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$ScopeColor = "Cyan"

if (-not $IsAdmin) {
    Write-Host "Elevation required to set Qt system variables. Relaunching as Administrator..." -ForegroundColor Yellow
    $Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    foreach ($Parameter in $PSBoundParameters.GetEnumerator()) {
        if ($Parameter.Value -is [switch]) {
            if ($Parameter.Value) { $Arguments += " -$($Parameter.Key)" }
        }
        else {
            $Arguments += " -$($Parameter.Key) `"$($Parameter.Value)`""
        }
    }
    try { Start-Process pwsh.exe -ArgumentList $Arguments -Verb RunAs -ErrorAction Stop }
    catch { Start-Process powershell.exe -ArgumentList $Arguments -Verb RunAs }
    exit
}

$qtroot = "VALUE_ROOT_PATH"
$qtbin = "VALUE_BIN_PATH"
$qtversion = "VALUE_VERSION"

$TargetScope = if ($IsAdmin) { "Machine" } else { "User" }
$RegPath = if ($IsAdmin) { "System\CurrentControlSet\Control\Session Manager\Environment" } else { "Environment" }
$RegRoot = if ($IsAdmin) { "LocalMachine" } else { "CurrentUser" }

$RegKey = [Microsoft.Win32.Registry]::$RegRoot.OpenSubKey($RegPath, $true)
$CurrentRawPath = $RegKey.GetValue("EXTCOMPLIBS_PATH", "", [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)

$CleanedPathList = $CurrentRawPath -split ';' | Where-Object { -not [string]::IsNullOrWhitespace($_) -and $_ -notlike "*$qtroot*" }
$NewRawPath = ($CleanedPathList -join ";").Replace(";;", ";")
$NewRawPath = ($NewRawPath + ";" + $qtbin + ";" + $qtroot + ";").Replace(";;", ";")
$RegKey.SetValue("EXTCOMPLIBS_PATH", $NewRawPath, [Microsoft.Win32.RegistryValueKind]::ExpandString)
$RegKey.Close()

$env:QT_ROOT = $qtroot
Write-Host "Qt Environment Loaded (Version: $qtversion) (Bin: $qtbin)" -ForegroundColor Green
Write-Host "QT_ROOT: $env:QT_ROOT" -ForegroundColor Gray
'@  -replace "VALUE_ROOT_PATH", $qtInstallDir `
    -replace "VALUE_BIN_PATH", $qtBinPath `
    -replace "VALUE_VERSION", $qtVersion

        $MachineEnvContent | Out-File -FilePath $qtMachineEnvScript -Encoding utf8 -force
        Write-Host "Created: $qtMachineEnvScript" -ForegroundColor Gray
        
        Write-Host ""
        $choice = Read-Host "Do you want to run the Machine Environment script now to persist Qt changes to the Registry? (y/n)"
        if ($choice -eq 'y' -or $choice -eq 'Y') {
            try { & $qtMachineEnvScript } catch { Write-Error "Failed to execute: $($_.Exception.Message)" }
        }
    }
} else {
    Write-Error "qmake.exe was not found in the $qtBinPath folder."
    return
}
