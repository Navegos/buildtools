# SPDX-FileCopyrightText: Copyright (c) 2026 Navegos. @DevelVitorF. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
# project: buildtools
# file: x64-windows/build-zlib.ps1
# created: 2026-02-28
# lastModified: 2026-04-26

param (
    [Parameter(HelpMessage = "Base workspace path", Mandatory = $false)]
    [string]$workspacePath = $null,

    [Parameter(HelpMessage = "zlib git repo url", Mandatory = $false)]
    [string]$gitUrl = "https://github.com/madler/zlib.git",
    
    [Parameter(HelpMessage = "zlib git branch to sync from", Mandatory = $false)]
    [string]$gitBranch = "develop",

    [Parameter(HelpMessage = "Path for zlib library storage", Mandatory = $false)]
    [string]$zlibInstallDir = "$env:LIBRARIES_PATH\zlib",
    
    [Parameter(HelpMessage = "Lib name, if it's building with a different name (fixit by changing it's default name beforehand)", Mandatory = $false)]
    [string]$zLibName = "z",
    
    [Parameter(HelpMessage = "Force a full purge of the local zlib version before continuing", Mandatory = $false)]
    [switch]$forceCleanup,
    
    [Parameter(HelpMessage = "Add's Zlib Machine Environment Variables. Requires Machine Administrator Rights.", Mandatory = $false)]
    [switch]$withMachineEnvironment
)

# Capture parameters
$zlibWorkspacePath = $workspacePath
$zlibGitUrl = $gitUrl
$zlibGitBranch = $gitBranch
$zlibForceCleanup = $forceCleanup
$zlibWithMachineEnvironment = $withMachineEnvironment

# 1. Bootstrap Environment if variables are missing
if ([string]::IsNullOrWhitespace($env:ENVIRONMENT_PATH) -or -not (Test-Path $env:ENVIRONMENT_PATH) -or [string]::IsNullOrWhitespace($env:BINARIES_PATH) -or -not (Test-Path $env:BINARIES_PATH) -or [string]::IsNullOrWhitespace($env:LIBRARIES_PATH) -or -not (Test-Path $env:LIBRARIES_PATH)) {
    Write-Error "User Environment variables missing. Please run adduserpaths.ps1 -LibrariesDir 'Path\for\Libraries' BinariesDir 'Path\for\Binaries' -EnvironmentDir 'Path\for\Environment'"
    return
}

$EnvironmentDir = "$env:ENVIRONMENT_PATH"

# --- 1. Initialize Visual Studio 2026 Dev Environment ---
$DevShellBootstrapScript = Join-Path $PSScriptRoot "dev-shell.ps1"
if (Test-Path $DevShellBootstrapScript) { . $DevShellBootstrapScript } else {
    Write-Error "Required dependency '$DevShellBootstrapScript' not found!"
    return
}

# --- 2. Initialize git environment if missing ---
if ([string]::IsNullOrWhitespace($env:BINARY_GIT) -or -not (Test-Path $env:BINARY_GIT)) {
    $gitEnvScript = Join-Path $EnvironmentDir "env-git.ps1"
    if (Test-Path $gitEnvScript) { . $gitEnvScript } 
    if ([string]::IsNullOrWhitespace($env:BINARY_GIT) -or -not (Test-Path $env:BINARY_GIT)) {
        $depgitEnvScript = Join-Path $PSScriptRoot "dep-git.ps1"
        if (Test-Path $depgitEnvScript) { . $depgitEnvScript }
        else {
            Write-Error "CRITICAL: Cannot load Git environment. git is missing and $depgitEnvScript was not found."
            return
        }
    }
}

# --- 3. Initialize cmake environment if missing ---
if ([string]::IsNullOrWhitespace($env:BINARY_CMAKE) -or -not (Test-Path $env:BINARY_CMAKE)) {
    $cmakeEnvScript = Join-Path $EnvironmentDir "env-cmake.ps1"
    if (Test-Path $cmakeEnvScript) { . $cmakeEnvScript } 
    if ([string]::IsNullOrWhitespace($env:BINARY_CMAKE) -or -not (Test-Path $env:BINARY_CMAKE)) {
        $depcmakeEnvScript = Join-Path $PSScriptRoot "dep-cmake.ps1"
        if (Test-Path $depcmakeEnvScript) { . $depcmakeEnvScript }
        else {
            Write-Error "CRITICAL: Cannot load CMake environment. cmake is missing and $depcmakeEnvScript was not found."
            return
        }
    }
}

# --- 4. Initialize ninja environment if missing ---
if ([string]::IsNullOrWhitespace($env:BINARY_NINJA) -or -not (Test-Path $env:BINARY_NINJA)) {
    $ninjaEnvScript = Join-Path $EnvironmentDir "env-ninja.ps1"
    if (Test-Path $ninjaEnvScript) { . $ninjaEnvScript }
    if ([string]::IsNullOrWhitespace($env:BINARY_NINJA) -or -not (Test-Path $env:BINARY_NINJA)) {
        $depninjaEnvScript = Join-Path $PSScriptRoot "dep-ninja.ps1"
        if (Test-Path $depninjaEnvScript) { . $depninjaEnvScript }
        else {
            Write-Error "CRITICAL: Cannot load ninja environment. ninja is missing and $depninjaEnvScript was not found."
            return
        }
    }
}

# --- 5. Initialize clang environment if missing ---
if ([string]::IsNullOrWhitespace($env:BINARY_CLANG) -or -not (Test-Path $env:BINARY_CLANG)) {
    $llvmEnvScript = Join-Path $EnvironmentDir "env-llvm.ps1"
    if (Test-Path $llvmEnvScript) { . $llvmEnvScript }
    if ([string]::IsNullOrWhitespace($env:BINARY_CLANG) -or -not (Test-Path $env:BINARY_CLANG)) {
        $depllvmEnvScript = Join-Path $PSScriptRoot "dep-llvm.ps1"
        if (Test-Path $depllvmEnvScript) { . $depllvmEnvScript }
        else {
            Write-Error "CRITICAL: Cannot load clang environment. clang is missing and $depllvmEnvScript was not found."
            return
        }
    }
}

$RootPath = if ([string]::IsNullOrWhitespace($zlibWorkspacePath)) { Get-Location } else { $zlibWorkspacePath }

# --- 6. Path Resolution ---
Push-Location $RootPath

$Source         = Join-Path $RootPath "zlib"
$BuildDir       = Join-Path $Source "build_dir"  # Nested inside source
$RepoUrl        = $zlibGitUrl
$Branch         = $zlibGitBranch
$CMakeSource    = $Source
$tag_name       = $Branch
$url            = $RepoUrl

$zlibEnvScript = Join-Path $EnvironmentDir "env-zlib.ps1"
$zlibMachineEnvScript = Join-Path $EnvironmentDir "machine-env-zlib.ps1"

# --- 1. Cleanup Mechanism ---
function Invoke-zlibVersionPurge {
    param ([string]$InstallPath)
    Write-Host "--- Initiating zlib Purge ---" -ForegroundColor Cyan

    if ($zlibWithMachineEnvironment) {
        $zlibCleanMachineEnvScript = Join-Path $env:TEMP "clean-machine-env-zlib.ps1"

        # Generating Clean Machine Environment wich removes the persist registry machine Environment
        $CleanMachineEnvContent = @'
# zlib Clean Machine Environment Setup

# --- 0. Self-Elevation Logic ---
$IsAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$ScopeColor = "Cyan"

if (-not $IsAdmin) {
    Write-Host "Elevation required to clean zlib system variables. Relaunching as Administrator..." -ForegroundColor Yellow
    # Pass the parameters to the elevated process so they aren't lost
    $Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    foreach ($Parameter in $PSBoundParameters.GetEnumerator()) {
        if ($Parameter.Value -is [switch]) {
            if ($Parameter.Value) { $Arguments += " -$($Parameter.Key)" }
        }
        else {
            # Use escape characters to ensure paths with spaces survive the jump
            $Arguments += " -$($Parameter.Key) `"$($Parameter.Value)`""
        }
    }

    try {
        Start-Process pwsh.exe -ArgumentList $Arguments -Verb RunAs -ErrorAction Stop
    }
    catch {
        Start-Process powershell.exe -ArgumentList $Arguments -Verb RunAs
    }
    exit
}

$zlibroot = "VALUE_ROOT_PATH"

$TargetScope = if ($IsAdmin) { "Machine" } else { "User" }
$RegPath = if ($IsAdmin) { "System\CurrentControlSet\Control\Session Manager\Environment" } else { "Environment" }
$RegRoot = if ($IsAdmin) { "LocalMachine" } else { "CurrentUser" }

# 1. Registry Cleanup (EXTCOMPLIBS_PATH)
$RegKey = [Microsoft.Win32.Registry]::$RegRoot.OpenSubKey($RegPath, $true)

# Open the registry key directly to read the RAW (unexpanded) string
$RawPath = $RegKey.GetValue("EXTCOMPLIBS_PATH", "", [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)

# Cleanup: Remove empty strings, any path containing $zlibroot,
$CleanPath = ($RawPath -split ';' | Where-Object { $_ -notlike "*$zlibroot*" }) -join ";"

# Save as ExpandString
$RegKey.SetValue("EXTCOMPLIBS_PATH", $CleanPath, [Microsoft.Win32.RegistryValueKind]::ExpandString)
$env:EXTCOMPLIBS_PATH = $CleanPath

$RegKey.Close()

Write-Host "[REMOVED] ($TargetScope) all '*$zlibroot*' removed from EXTCOMPLIBS_PATH" -ForegroundColor $ScopeColor
'@  -replace "VALUE_ROOT_PATH", $InstallPath

        $CleanMachineEnvContent | Out-File -FilePath $zlibCleanMachineEnvScript -Encoding utf8
        Write-Host "Created: $zlibCleanMachineEnvScript" -ForegroundColor Gray
        
        # --- Interaction: Prompt to remove persistent changes ---
        Write-Host ""
        $choice = Read-Host "Administrator rights required to Clean Machine Environment zlib changes? (y/n)"
        if ($choice -eq 'y' -or $choice -eq 'Y') {
            Write-Host "Executing $zlibCleanMachineEnvScript..." -ForegroundColor Yellow
            try {
                # Start the generated script. It handles its own elevation logic.
                & $zlibCleanMachineEnvScript
            }
            catch {
                Write-Error "Failed to execute the Clean Machine Environment script: $($_.Exception.Message)"
                Pop-Location; return
            }
        }
        else {
            Write-Error "Skipped Clean Machine Environment zlib changes."
            Pop-Location; return
        }
        
        # Cleanup
        Remove-Item $zlibCleanMachineEnvScript -Recurse -Force -ErrorAction SilentlyContinue
    }

    # 2. Filesystem Clean (Requires checking for locked files)
    # delete everithing we create don't fail later
    if (Test-Path $zlibEnvScript) {
        Write-Host "  [DELETING] $zlibEnvScript" -ForegroundColor Yellow
        Remove-Item $zlibEnvScript -Recurse -Force -ErrorAction SilentlyContinue
    }
    if (Test-Path $zlibMachineEnvScript) {
        Write-Host "  [DELETING] $zlibMachineEnvScript" -ForegroundColor Yellow
        Remove-Item $zlibMachineEnvScript -Recurse -Force -ErrorAction SilentlyContinue
    }
    if (Test-Path $InstallPath) {
        Write-Host "  [DELETING] $InstallPath" -ForegroundColor Yellow
        Remove-Item $InstallPath -Recurse -Force -ErrorAction SilentlyContinue
    }
    if (Test-Path $Source) {
        Write-Host "  [DELETING] $Source" -ForegroundColor Yellow
        Remove-Item $Source -Recurse -Force -ErrorAction SilentlyContinue
    }
    
    # remove local Env variables for current session
    Get-ChildItem Env:\ZLIB_PATH* | Remove-Item -ErrorAction SilentlyContinue
    Get-ChildItem Env:\ZLIB_ROOT* | Remove-Item -ErrorAction SilentlyContinue
    Get-ChildItem Env:\ZLIB_BIN* | Remove-Item -ErrorAction SilentlyContinue
    Get-ChildItem Env:\ZLIB_INCLUDE_DIR* | Remove-Item -ErrorAction SilentlyContinue
    Get-ChildItem Env:\ZLIB_LIBRARY_DIR* | Remove-Item -ErrorAction SilentlyContinue
    Get-ChildItem Env:\BINARY_LIB_ZLIB* | Remove-Item -ErrorAction SilentlyContinue
    Get-ChildItem Env:\SHARED_LIB_ZLIB* | Remove-Item -ErrorAction SilentlyContinue
    Get-ChildItem Env:\STATIC_LIB_ZLIB* | Remove-Item -ErrorAction SilentlyContinue
    Get-ChildItem Env:\ZLIB_LIB_NAME* | Remove-Item -ErrorAction SilentlyContinue
    Get-ChildItem Env:\ZLIB_VERSION* | Remove-Item -ErrorAction SilentlyContinue
    Get-ChildItem Env:\ZLIB_MAJOR* | Remove-Item -ErrorAction SilentlyContinue
    Get-ChildItem Env:\ZLIB_MINOR* | Remove-Item -ErrorAction SilentlyContinue
    Get-ChildItem Env:\ZLIB_PATCH* | Remove-Item -ErrorAction SilentlyContinue
    Get-ChildItem Env:\ZLIB_ABI_VERSION* | Remove-Item -ErrorAction SilentlyContinue
    Get-ChildItem Env:\ZLIB_SO_VERSION* | Remove-Item -ErrorAction SilentlyContinue
    
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
    
    Write-Host "--- ZLIB Purge Complete ---" -ForegroundColor Green
}

if ($zlibForceCleanup) {
    Invoke-zlibVersionPurge -InstallPath $zlibInstallDir
}

# --- 7. Source Management ---
if (Test-Path $Source) {
    Write-Host "Syncing zlib ($Branch) at $Source..." -ForegroundColor Cyan
    Set-Location $Source
    git fetch --all
    git reset --hard "origin/$Branch"
    git pull --recurse-submodules --force
    $tagCommit = (& git rev-parse --verify HEAD).Trim()
} else {
    Write-Host "Cloning zlib ($Branch) into $Source..." -ForegroundColor Cyan
    git clone --recurse-submodules $RepoUrl $Source -b $Branch
    Set-Location $Source
    $tagCommit = (& git rev-parse --verify HEAD).Trim()
}

# --- 8. Clean & Build ---
if (Test-Path $zlibInstallDir) {
    Write-Host "Wiping existing installation at $zlibInstallDir..." -ForegroundColor Yellow
    Remove-Item $zlibInstallDir -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "[INSTALL] Creating fresh directory: $zlibInstallDir" -ForegroundColor Cyan
New-Item -Path $zlibInstallDir -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null

# Ensure fresh build directory
if (Test-Path $BuildDir) { Remove-Item $BuildDir -Recurse -Force -ErrorAction SilentlyContinue }
New-Item -Path $BuildDir -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null

Write-Host "Configuring with Clang/Ninja..." -ForegroundColor Cyan
cmake -G "Ninja" `
    -S "$CMakeSource" `
    -B "$BuildDir" `
    -DCMAKE_POLICY_DEFAULT_CMP0091=NEW `
    -DCMAKE_POLICY_DEFAULT_CMP0109=NEW `
    -DCMAKE_C_COMPILER="clang" `
    -DCMAKE_INSTALL_PREFIX="$zlibInstallDir" `
    -DCMAKE_BUILD_TYPE=Release `
    -DCMAKE_C_FLAGS="-Wno-deprecated-declarations -D_CRT_SECURE_NO_WARNINGS=1" `
    --no-warn-unused-cli

if ($LASTEXITCODE -ne 0) { Write-Error "zlib CMake configuration failed."; Pop-Location; return }

Write-Host "Building and Installing to $zlibInstallDir..." -ForegroundColor Green
cmake --build "$BuildDir" --target install --config Release --parallel

if ($LASTEXITCODE -ne 0) { Write-Error "zlib Build failed with exit code $LASTEXITCODE"; Pop-Location; return }

Write-Host "Successfully built and installed zlib to $zlibInstallDir!" -ForegroundColor Green

# Cleanup temporary build debris
Remove-Item $BuildDir -Recurse -Force -ErrorAction SilentlyContinue

# Generate Environment Helper with Clean Paths
$zlibInstallDir = $zlibInstallDir.TrimEnd('\')
$zlibIncludeDir = Join-Path $zlibInstallDir "include"
$zlibLibDir = Join-Path $zlibInstallDir "lib"
$zlibBinPath = Join-Path $zlibInstallDir "bin"
$zlibCMakePath = $zlibInstallDir.Replace('\', '/')

$StaticLib = Join-Path $zlibLibDir "zlibstatic.lib"
$SharedLib = Join-Path $zlibLibDir "zlib.lib"
$BinaryLib = Join-Path $zlibBinPath "zlib.dll"
$versionFile = Join-Path $zlibInstallDir "version.json"

# Fallback check for "z.lib" / "zs.lib" naming convention
if (-not (Test-Path $StaticLib)) { $StaticLib = Join-Path $zlibLibDir ("$zLibName" + "static.lib") }
if (-not (Test-Path $StaticLib)) { $StaticLib = Join-Path $zlibLibDir ("$zLibName" + "s.lib") }
if (-not (Test-Path $SharedLib)) { $SharedLib = Join-Path $zlibLibDir "$zLibName.lib" }
if (-not (Test-Path $BinaryLib)) { $BinaryLib = Join-Path $zlibBinPath "$zLibName.dll" }

if ((Test-Path $StaticLib) -or (Test-Path $SharedLib) -or (Test-Path $BinaryLib)) {
    $zlibHeader = Join-Path $zlibIncludeDir "zlib.h"
    if (-not (Test-Path $zlibHeader)) { $zlibHeader = Join-Path $Source "zlib.h" }
    $localVersion = "0.0.0"
    $rawVersion = $Branch
    $binaryversion = "0"

    if (Test-Path $zlibHeader) {
        # Extract version from #define ZLIB_VERSION "1.3.2.1-motley"
        $headerLine = Get-Content $zlibHeader | Select-String '#define\s+ZLIB_VERSION\s+"([^"]+)"'
        
        if ($headerLine -and $headerLine.Matches.Groups[1].Value)
        {
            $rawVersion = $headerLine.Matches.Groups[1].Value
            
            # 1. Extract the numeric part for [version] compatibility (1.3.2.1)
            if ($rawVersion -match '^(\d+\.\d+\.\d+(\.\d+)?)') {
                $localVersion = $Matches[1]
            }
            $binaryversion = ([version]$localVersion).Major

            Write-Host "[VERSION] Detected Zlib: $rawVersion (Parsed as: $localVersion)" -ForegroundColor Cyan
        }
    }

    # Save new version state
    $zlibVersion = $localVersion
    $versionInfo = @{
        url        = $url;
        tag_name   = $tag_name;
        commit     = $tagCommit;
        version    = $localVersion;
        rawversion = $rawVersion;
        abiversion = $binaryversion;
        soversion  = $binaryversion;
        date       = (Get-Date).ToString("yyyy-MM-dd");
        updated_at = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssZ");
        type       = "source_build";
    }
    $versionInfo | ConvertTo-Json | Out-File -FilePath $versionFile -Encoding utf8 -Force

    # --- 9. Create Environment Helper ---
    Write-Host "Generating environment helper script..." -ForegroundColor Cyan
    $EnvContent = @'
# ZLIB Environment Setup
$zlibroot = "VALUE_ROOT_PATH"
$zlibinclude = "VALUE_INCLUDE_PATH"
$zliblibrary = "VALUE_LIB_PATH"
$zlibbin = "VALUE_BIN_PATH"
$zlibversion = "VALUE_VERSION"
$zlibabiversion = "VALUE_ABI_VERSION"
$zlibsoversion = "VALUE_SO_VERSION"
$zlibbinary = "VALUE_BINARY"
$zlibshared = "VALUE_SHARED"
$zlibstatic = "VALUE_STATIC"
$zlibname = "VALUE_LIB_NAME"
$zlibcmakepath = "VALUE_CMAKE_PATH"
$env:ZLIB_PATH = $zlibroot
$env:ZLIB_ROOT = $zlibroot
$env:ZLIB_BIN = $zlibbin
$env:ZLIB_INCLUDE_DIR = $zlibinclude
$env:ZLIB_LIBRARY_DIR = $zliblibrary
$env:BINARY_LIB_ZLIB = $zlibbinary
$env:SHARED_LIB_ZLIB = $zlibshared
$env:STATIC_LIB_ZLIB = $zlibstatic
$env:ZLIB_LIB_NAME = $zlibname
$env:ZLIB_VERSION = $zlibversion
$env:ZLIB_MAJOR = ([version]$zlibversion).Major
$env:ZLIB_MINOR = ([version]$zlibversion).Minor
$env:ZLIB_PATCH = ([version]$zlibversion).Patch
$env:ZLIB_ABI_VERSION = $zlibabiversion
$env:ZLIB_SO_VERSION = $zlibsoversion
if ($env:CMAKE_PREFIX_PATH -notlike "*$zlibcmakepath*") { $env:CMAKE_PREFIX_PATH = $zlibcmakepath + ";" + $env:CMAKE_PREFIX_PATH; $env:CMAKE_PREFIX_PATH = ($env:CMAKE_PREFIX_PATH).Replace(";;", ";") }
if ($env:INCLUDE -notlike "*$zlibinclude*") { $env:INCLUDE = $zlibinclude + ";" + $env:INCLUDE; $env:INCLUDE = ($env:INCLUDE).Replace(";;", ";") }
if ($env:LIB -notlike "*$zliblibrary*") { $env:LIB = $zliblibrary + ";" + $env:LIB; $env:LIB = ($env:LIB).Replace(";;", ";") }
if ($env:PATH -notlike "*$zlibbin*") { $env:PATH = $zlibbin + ";" + $env:PATH; $env:PATH = ($env:PATH).Replace(";;", ";") }
Write-Host "Zlib Environment Loaded (Version: $zlibversion) (Bin: $zlibbin)" -ForegroundColor Green
Write-Host "ZLIB_ROOT: $env:ZLIB_ROOT" -ForegroundColor Gray
'@  -replace "VALUE_ROOT_PATH", $zlibInstallDir `
    -replace "VALUE_INCLUDE_PATH", $zlibIncludeDir `
    -replace "VALUE_LIB_PATH", $zlibLibDir `
    -replace "VALUE_BIN_PATH", $zlibBinPath `
    -replace "VALUE_VERSION", $zlibVersion `
    -replace "VALUE_ABI_VERSION", $binaryversion `
    -replace "VALUE_SO_VERSION", $binaryversion `
    -replace "VALUE_SHARED", $SharedLib `
    -replace "VALUE_BINARY", $BinaryLib `
    -replace "VALUE_STATIC", $StaticLib `
    -replace "VALUE_LIB_NAME", $zLibName `
    -replace "VALUE_CMAKE_PATH", $zlibCMakePath

    $EnvContent | Out-File -FilePath $zlibEnvScript -Encoding utf8 -force
    Write-Host "Created: $zlibEnvScript" -ForegroundColor Gray

    # Update Current Session
    if (Test-Path $zlibEnvScript) { . $zlibEnvScript } else {
        Write-Error "zlib build install finished but $zlibEnvScript was not created."
        Pop-Location; return
    }
    
    if ($zlibWithMachineEnvironment)
    {
        # Generating Machine Environment wich add to the persist registry machine Environment
        $MachineEnvContent = @'
# Zlib Machine Environment Setup

# --- 0. Self-Elevation Logic ---
$IsAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$ScopeColor = "Cyan"

if (-not $IsAdmin) {
    Write-Host "Elevation required to set Zlib system variables. Relaunching as Administrator..." -ForegroundColor Yellow
    # Pass the parameters to the elevated process so they aren't lost
    $Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    foreach ($Parameter in $PSBoundParameters.GetEnumerator()) {
        if ($Parameter.Value -is [switch]) {
            if ($Parameter.Value) { $Arguments += " -$($Parameter.Key)" }
        }
        else {
            # Use escape characters to ensure paths with spaces survive the jump
            $Arguments += " -$($Parameter.Key) `"$($Parameter.Value)`""
        }
    }

    try {
        Start-Process pwsh.exe -ArgumentList $Arguments -Verb RunAs -ErrorAction Stop
    }
    catch {
        Start-Process powershell.exe -ArgumentList $Arguments -Verb RunAs
    }
    exit
}

$zlibroot = "VALUE_ROOT_PATH"
$zlibbin = "VALUE_BIN_PATH"
$zlibversion = "VALUE_VERSION"

$TargetScope = if ($IsAdmin) { "Machine" } else { "User" }
$RegPath = if ($IsAdmin) { "System\CurrentControlSet\Control\Session Manager\Environment" } else { "Environment" }
$RegRoot = if ($IsAdmin) { "LocalMachine" } else { "CurrentUser" }

# Open the registry key once
$RegKey = [Microsoft.Win32.Registry]::$RegRoot.OpenSubKey($RegPath, $true)

# Open the registry key directly to read the RAW (unexpanded) string
$CurrentRawPath = $RegKey.GetValue("EXTCOMPLIBS_PATH", "", [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)

# Cleanup: Remove empty strings, any path containing $zlibroot, and the current target (to avoid dups)
$CleanedPathList = $CurrentRawPath -split ';' | Where-Object { 
    -not [string]::IsNullOrWhitespace($_) -and 
    $_ -notlike "*$zlibroot*"
}

$NewRawPath = ($CleanedPathList -join ";").Replace(";;", ";")

$TargetPath = $zlibbin

# Rebuild
$NewRawPath = ($NewRawPath + ";" + $TargetPath + ";").Replace(";;", ";")
Write-Host "[UPDATED] ($TargetScope) '$zlibbin' synced in EXTCOMPLIBS_PATH" -ForegroundColor $ScopeColor

# Save as ExpandString
$RegKey.SetValue("EXTCOMPLIBS_PATH", $NewRawPath, [Microsoft.Win32.RegistryValueKind]::ExpandString)
$env:EXTCOMPLIBS_PATH = $NewRawPath

$RegKey.Close()

$env:ZLIB_ROOT = $zlibroot
Write-Host "Zlib Environment Loaded (Version: $zlibversion) (Bin: $zlibbin)" -ForegroundColor Green
Write-Host "ZLIB_ROOT: $env:ZLIB_ROOT" -ForegroundColor Gray
'@  -replace "VALUE_ROOT_PATH", $zlibInstallDir `
    -replace "VALUE_BIN_PATH", $zlibBinPath `
    -replace "VALUE_VERSION", $zlibVersion

        $MachineEnvContent | Out-File -FilePath $zlibMachineEnvScript -Encoding utf8 -force
        Write-Host "Created: $zlibMachineEnvScript" -ForegroundColor Gray
        
        # --- Interaction: Prompt to apply persistent changes ---
        Write-Host ""
        $choice = Read-Host "Do you want to run the Machine Environment script now to persist Zlib changes to the Registry? (y/n)"
        if ($choice -eq 'y' -or $choice -eq 'Y') {
            Write-Host "Executing $zlibMachineEnvScript..." -ForegroundColor Yellow
            try {
                # Start the generated script. It handles its own elevation logic.
                & $zlibMachineEnvScript
            }
            catch {
                Write-Error "Failed to execute the Machine Environment script: $($_.Exception.Message)"
            }
        }
        else {
            Write-Host "Skipped persistent registry update. You can run it later at: $zlibMachineEnvScript" -ForegroundColor Gray
        }
    }
    
    # --- Return to Start ---
    Pop-Location
    Write-Host "Successfully Done! and returned to: $(Get-Location)" -ForegroundColor DarkGreen
} else {
    Write-Error "z.lib was not found in the $zlibLibDir folder."
    Pop-Location; return
}
