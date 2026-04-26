# SPDX-FileCopyrightText: Copyright (c) 2026 Navegos. @DevelVitorF. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
# project: buildtools
# file: x64-windows/build-cares.ps1
# created: 2026-03-06
# lastModified: 2026-04-26

param (
    [Parameter(HelpMessage = "Base workspace path", Mandatory = $false)]
    [string]$workspacePath = $null,

    [Parameter(HelpMessage = "c-ares git repo url", Mandatory = $false)]
    [string]$gitUrl = "https://github.com/c-ares/c-ares.git",
    
    [Parameter(HelpMessage = "c-ares git branch to sync from", Mandatory = $false)]
    [string]$gitBranch = "main",

    [Parameter(HelpMessage = "Path for c-ares library storage", Mandatory = $false)]
    [string]$caresInstallDir = "$env:LIBRARIES_PATH\cares",
    
    [Parameter(HelpMessage = "Lib name, if it's building with a different name (fixit by changing it's default name beforehand)", Mandatory = $false)]
    [string]$caresLibName = "cares",
    
    [Parameter(HelpMessage = "Force a full purge of the local c-ares version before continuing", Mandatory = $false)]
    [switch]$forceCleanup,
    
    [Parameter(HelpMessage = "Add's c-ares Machine Environment Variables. Requires Machine Administrator Rights.", Mandatory = $false)]
    [switch]$withMachineEnvironment
)

# Capture parameters
$caresWorkspacePath = $workspacePath
$caresGitUrl = $gitUrl
$caresGitBranch = $gitBranch
$caresForceCleanup = $forceCleanup
$caresWithMachineEnvironment = $withMachineEnvironment

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

$RootPath = if ([string]::IsNullOrWhitespace($caresWorkspacePath)) { Get-Location } else { $caresWorkspacePath }

# --- 6. Path Resolution ---
Push-Location $RootPath

$Source         = Join-Path $RootPath "cares"
$BuildDirShared = Join-Path $Source "build_shared"
$BuildDirStatic = Join-Path $Source "build_static"
$RepoUrl        = $caresGitUrl
$Branch         = $caresGitBranch
$CMakeSource    = $Source
$tag_name       = $Branch
$url            = $RepoUrl

$caresEnvScript = Join-Path $EnvironmentDir "env-cares.ps1"
$caresMachineEnvScript = Join-Path $EnvironmentDir "machine-env-cares.ps1"

# --- 1. Cleanup Mechanism ---
function Invoke-caresVersionPurge {
    param ([string]$InstallPath)
    Write-Host "--- Initiating cares Purge ---" -ForegroundColor Cyan

    if ($caresWithMachineEnvironment) {
        $caresCleanMachineEnvScript = Join-Path $env:TEMP "clean-machine-env-cares.ps1"

        # Generating Clean Machine Environment wich removes the persist registry machine Environment
        $CleanMachineEnvContent = @'
# cares Clean Machine Environment Setup

# --- 0. Self-Elevation Logic ---
$IsAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$ScopeColor = "Cyan"

if (-not $IsAdmin) {
    Write-Host "Elevation required to clean cares system variables. Relaunching as Administrator..." -ForegroundColor Yellow
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

$caresroot = "VALUE_ROOT_PATH"

$TargetScope = if ($IsAdmin) { "Machine" } else { "User" }
$RegPath = if ($IsAdmin) { "System\CurrentControlSet\Control\Session Manager\Environment" } else { "Environment" }
$RegRoot = if ($IsAdmin) { "LocalMachine" } else { "CurrentUser" }

# 1. Registry Cleanup (EXTCOMPLIBS_PATH)
$RegKey = [Microsoft.Win32.Registry]::$RegRoot.OpenSubKey($RegPath, $true)

# Open the registry key directly to read the RAW (unexpanded) string
$RawPath = $RegKey.GetValue("EXTCOMPLIBS_PATH", "", [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)

# Cleanup: Remove empty strings, any path containing $caresroot,
$CleanPath = ($RawPath -split ';' | Where-Object { $_ -notlike "*$caresroot*" }) -join ";"

# Save as ExpandString
$RegKey.SetValue("EXTCOMPLIBS_PATH", $CleanPath, [Microsoft.Win32.RegistryValueKind]::ExpandString)
$env:EXTCOMPLIBS_PATH = $CleanPath

$RegKey.Close()

Write-Host "[REMOVED] ($TargetScope) all '*$caresroot*' removed from EXTCOMPLIBS_PATH" -ForegroundColor $ScopeColor
'@  -replace "VALUE_ROOT_PATH", $InstallPath

        $CleanMachineEnvContent | Out-File -FilePath $caresCleanMachineEnvScript -Encoding utf8
        Write-Host "Created: $caresCleanMachineEnvScript" -ForegroundColor Gray
        
        # --- Interaction: Prompt to remove persistent changes ---
        Write-Host ""
        $choice = Read-Host "Administrator rights required to Clean Machine Environment cares changes? (y/n)"
        if ($choice -eq 'y' -or $choice -eq 'Y') {
            Write-Host "Executing $caresCleanMachineEnvScript..." -ForegroundColor Yellow
            try {
                # Start the generated script. It handles its own elevation logic.
                & $caresCleanMachineEnvScript
            }
            catch {
                Write-Error "Failed to execute the Clean Machine Environment script: $($_.Exception.Message)"
                Pop-Location; return
            }
        }
        else {
            Write-Error "Skipped Clean Machine Environment cares changes."
            Pop-Location; return
        }
        
        # Cleanup
        Remove-Item $caresCleanMachineEnvScript -Recurse -Force -ErrorAction SilentlyContinue
    }

    # 2. Filesystem Clean (Requires checking for locked files)
    # delete everithing we create don't fail later
    if (Test-Path $caresEnvScript) {
        Write-Host "  [DELETING] $caresEnvScript" -ForegroundColor Yellow
        Remove-Item $caresEnvScript -Recurse -Force -ErrorAction SilentlyContinue
    }
    if (Test-Path $caresMachineEnvScript) {
        Write-Host "  [DELETING] $caresMachineEnvScript" -ForegroundColor Yellow
        Remove-Item $caresMachineEnvScript -Recurse -Force -ErrorAction SilentlyContinue
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
    Get-ChildItem Env:\CARES_PATH* | Remove-Item -ErrorAction SilentlyContinue
    Get-ChildItem Env:\CARES_ROOT* | Remove-Item -ErrorAction SilentlyContinue
    Get-ChildItem Env:\CARES_BIN* | Remove-Item -ErrorAction SilentlyContinue
    Get-ChildItem Env:\CARES_INCLUDE_DIR* | Remove-Item -ErrorAction SilentlyContinue
    Get-ChildItem Env:\CARES_LIBRARY_DIR* | Remove-Item -ErrorAction SilentlyContinue
    Get-ChildItem Env:\BINARY_LIB_CARES* | Remove-Item -ErrorAction SilentlyContinue
    Get-ChildItem Env:\SHARED_LIB_CARES* | Remove-Item -ErrorAction SilentlyContinue
    Get-ChildItem Env:\STATIC_LIB_CARES* | Remove-Item -ErrorAction SilentlyContinue
    Get-ChildItem Env:\CARES_LIB_NAME* | Remove-Item -ErrorAction SilentlyContinue
    Get-ChildItem Env:\CARES_VERSION* | Remove-Item -ErrorAction SilentlyContinue
    Get-ChildItem Env:\CARES_MAJOR* | Remove-Item -ErrorAction SilentlyContinue
    Get-ChildItem Env:\CARES_MINOR* | Remove-Item -ErrorAction SilentlyContinue
    Get-ChildItem Env:\CARES_PATCH* | Remove-Item -ErrorAction SilentlyContinue
    Get-ChildItem Env:\CARES_ABI_VERSION* | Remove-Item -ErrorAction SilentlyContinue
    Get-ChildItem Env:\CARES_SO_VERSION* | Remove-Item -ErrorAction SilentlyContinue
    
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
    
    Write-Host "--- CARES Purge Complete ---" -ForegroundColor Green
}

if ($caresForceCleanup) {
    Invoke-caresVersionPurge -InstallPath $caresInstallDir
}

# --- 7. Source Management ---
if (Test-Path $Source) {
    Write-Host "Syncing cares ($Branch) at $Source..." -ForegroundColor Cyan
    Set-Location $Source
    git fetch --all
    git reset --hard "origin/$Branch"
    git pull --recurse-submodules --force
    $tagCommit = (& git rev-parse --verify HEAD).Trim()
} else {
    Write-Host "Cloning cares ($Branch) into $Source..." -ForegroundColor Cyan
    git clone --recurse-submodules $RepoUrl $Source -b $Branch
    Set-Location $Source
    $tagCommit = (& git rev-parse --verify HEAD).Trim()
}

# --- 8. Clean Final Destination ---
if (Test-Path $caresInstallDir) {
    Write-Host "Wiping existing installation..." -ForegroundColor Yellow
    Remove-Item $caresInstallDir -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "[INSTALL] Creating fresh directory: $caresInstallDir" -ForegroundColor Cyan
New-Item -Path $caresInstallDir -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null

# Ensure fresh build directory
if (Test-Path $BuildDirShared) { Remove-Item $BuildDirShared -Recurse -Force -ErrorAction SilentlyContinue }
if (Test-Path $BuildDirStatic) { Remove-Item $BuildDirStatic -Recurse -Force -ErrorAction SilentlyContinue }
New-Item -Path $BuildDirShared -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null
New-Item -Path $BuildDirStatic -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null

# Common CMake Flags 
$CommonCmakeArgs = @(
    "-G", "Ninja",
    "-DCMAKE_POLICY_DEFAULT_CMP0091=NEW",
    "-DCMAKE_POLICY_DEFAULT_CMP0109=NEW",
    "-DCMAKE_C_COMPILER=clang",
    "-DCMAKE_CXX_COMPILER=clang++",
    "-DCMAKE_BUILD_TYPE=Release",
    "-DCARES_THREADS=ON",
    "-DCARES_BUILD_TESTS=OFF",
    "-DCARES_BUILD_CONTAINER_TESTS=OFF",
    "-DCARES_BUILD_TOOLS=OFF"
)

# --- 9. STAGE 1: Build Static Libraries ---
Write-Host "Building Static (caress.lib)..." -ForegroundColor Cyan
cmake $CommonCmakeArgs `
    -S "$CMakeSource" `
    -B "$BuildDirStatic" `
    -DCMAKE_INSTALL_PREFIX="$caresInstallDir" `
    -DCARES_SHARED=OFF `
    -DCARES_STATIC=ON `
    -DCMAKE_C_FLAGS="-Wno-deprecated-declarations -D_CRT_SECURE_NO_WARNINGS=1" `
    -DCMAKE_CXX_FLAGS="-Wno-deprecated-declarations -D_CRT_SECURE_NO_WARNINGS=1" `
    --no-warn-unused-cli
    
if ($LASTEXITCODE -ne 0) { Write-Error "c-ares CMake Static (caress.lib) configuration failed."; Pop-Location; return }

Write-Host "Building and Installing static lib to $caresInstallDir..." -ForegroundColor Green
cmake --build "$BuildDirStatic" --target install --config Release --parallel

if ($LASTEXITCODE -ne 0) { Write-Error "c-ares Static Build failed with exit code $LASTEXITCODE"; Pop-Location; return }

# Rename static lib to caress.lib to avoid collision
$StaticLibPath = Join-Path $caresInstallDir "lib/cares.lib"
$NewStaticName = Join-Path $caresInstallDir "lib/caress.lib"
if (Test-Path $StaticLibPath) {
    Move-Item -Path $StaticLibPath -Destination $NewStaticName -Force -ErrorAction SilentlyContinue
    Write-Host "Static library renamed to caress.lib" -ForegroundColor Gray
}

# --- 10. STAGE 2: Build Shared Libraries ---
Write-Host "Building Shared (DLL)..." -ForegroundColor Cyan
cmake $CommonCmakeArgs `
    -S "$CMakeSource" `
    -B "$BuildDirShared" `
    -DCMAKE_INSTALL_PREFIX="$caresInstallDir" `
    -DCARES_SHARED=ON `
    -DCARES_STATIC=OFF `
    -DCMAKE_C_FLAGS="-Wno-deprecated-declarations -D_CRT_SECURE_NO_WARNINGS=1" `
    -DCMAKE_CXX_FLAGS="-Wno-deprecated-declarations -D_CRT_SECURE_NO_WARNINGS=1" `
    --no-warn-unused-cli
    
if ($LASTEXITCODE -ne 0) { Write-Error "c-ares CMake Shared (DLL) configuration failed."; Pop-Location; return }

Write-Host "Building and Installing dynamic lib to $caresInstallDir..." -ForegroundColor Green
cmake --build "$BuildDirShared" --target install --config Release --parallel

if ($LASTEXITCODE -ne 0) { Write-Error "c-ares Shared Build failed with exit code $LASTEXITCODE"; Pop-Location; return }

Write-Host "Successfully built and installed c-ares to $caresInstallDir!" -ForegroundColor Green

# Cleanup temporary build debris
Remove-Item $BuildDirShared -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item $BuildDirStatic -Recurse -Force -ErrorAction SilentlyContinue

# Generate Environment Helper with Clean Paths
$caresInstallDir = $caresInstallDir.TrimEnd('\')
$caresIncludeDir = Join-Path $caresInstallDir "include"
$caresLibDir = Join-Path $caresInstallDir "lib"
$caresBinPath = Join-Path $caresInstallDir "bin"
$caresCMakePath = $caresInstallDir.Replace('\', '/')

$StaticLib = Join-Path $caresLibDir ("$caresLibName" + "static.lib")
$SharedLib = Join-Path $caresLibDir "$caresLibName.lib"
$BinaryLib = Join-Path $caresBinPath "$caresLibName.dll"
$versionFile = Join-Path $caresInstallDir "version.json"

# Fallback check for "z.lib" / "zs.lib" naming convention
if (-not (Test-Path $StaticLib)) { $StaticLib = Join-Path $caresLibDir ("$caresLibName" + "s.lib") }
#if (-not (Test-Path $SharedLib)) { $SharedLib = Join-Path $caresLibDir "z.lib" }
#if (-not (Test-Path $BinaryLib)) { $BinaryLib = Join-Path $caresBinPath "z.dll" }

if ((Test-Path $StaticLib) -or (Test-Path $SharedLib) -or (Test-Path $BinaryLib)) {
    $caresHeader = Join-Path $caresIncludeDir "ares_version.h"
    if (-not (Test-Path $caresHeader)) { $caresHeader = Join-Path $Source "include\ares_version.h" }
    $localVersion = "0.0.0"
    $rawVersion = $Branch
    $binaryversion = "0"

    if (Test-Path $caresHeader) {
        # Extract version from #define ARES_VERSION_STR "1.34.5"
        $headerContent = Get-Content $caresHeader
        
        # Regex looks for the define and captures the content inside the quotes
        $versionMatch = ($headerContent | Select-String '#define\s+ARES_VERSION_STR\s+"([^"]+)"').Matches.Groups[1].Value
    
        if ($versionMatch) {
            $localVersion = $versionMatch
            $rawVersion = $localVersion
            $binaryversion = ([version]$localVersion).Major
            Write-Host "[VERSION] Detected cares: $localVersion" -ForegroundColor Cyan
        }
    }

    # Save new version state
    $caresVersion = $localVersion
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

    # --- 11. Create Environment Helper ---
    Write-Host "Generating environment helper script..." -ForegroundColor Cyan
    $EnvContent = @'
# C-ARES Environment Setup
$caresroot = "VALUE_ROOT_PATH"
$caresinclude = "VALUE_INCLUDE_PATH"
$careslibrary = "VALUE_LIB_PATH"
$caresbin = "VALUE_BIN_PATH"
$caresversion = "VALUE_VERSION"
$caresabiversion = "VALUE_ABI_VERSION"
$caressoversion = "VALUE_SO_VERSION"
$caresbinary = "VALUE_BINARY"
$caresshared = "VALUE_SHARED"
$caresstatic = "VALUE_STATIC"
$careslibname = "VALUE_LIB_NAME"
$carescmakepath = "VALUE_CMAKE_PATH"
$env:CARES_PATH = $caresroot
$env:CARES_ROOT = $caresroot
$env:CARES_BIN = $caresbin
$env:CARES_INCLUDE_DIR = $caresinclude
$env:CARES_LIBRARY_DIR = $careslibrary
$env:BINARY_LIB_CARES = $caresbinary
$env:SHARED_LIB_CARES = $caresshared
$env:STATIC_LIB_CARES = $caresstatic
$env:CARES_LIB_NAME = $careslibname
$env:CARES_VERSION = $caresversion
$env:CARES_MAJOR = ([version]$caresversion).Major
$env:CARES_MINOR = ([version]$caresversion).Minor
$env:CARES_PATCH = ([version]$caresversion).Patch
$env:CARES_ABI_VERSION = $caresabiversion
$env:CARES_SO_VERSION = $caressoversion
if ($env:CMAKE_PREFIX_PATH -notlike "*$carescmakepath*") { $env:CMAKE_PREFIX_PATH = $carescmakepath + ";" + $env:CMAKE_PREFIX_PATH; $env:CMAKE_PREFIX_PATH = ($env:CMAKE_PREFIX_PATH).Replace(";;", ";") }
if ($env:INCLUDE -notlike "*$caresinclude*") { $env:INCLUDE = $caresinclude + ";" + $env:INCLUDE; $env:INCLUDE = ($env:INCLUDE).Replace(";;", ";") }
if ($env:LIB -notlike "*$careslibrary*") { $env:LIB = $careslibrary + ";" + $env:LIB; $env:LIB = ($env:LIB).Replace(";;", ";") }
if ($env:PATH -notlike "*$caresbin*") { $env:PATH = $caresbin + ";" + $env:PATH; $env:PATH = ($env:PATH).Replace(";;", ";") }
Write-Host "CARES Environment Loaded (Version: $caresversion) (Bin: $caresbin)" -ForegroundColor Green
Write-Host "CARES_ROOT: $env:CARES_ROOT" -ForegroundColor Gray
'@  -replace "VALUE_ROOT_PATH", $caresInstallDir `
    -replace "VALUE_INCLUDE_PATH", $caresIncludeDir `
    -replace "VALUE_LIB_PATH", $caresLibDir `
    -replace "VALUE_BIN_PATH", $caresBinPath `
    -replace "VALUE_VERSION", $caresVersion `
    -replace "VALUE_ABI_VERSION", $binaryversion `
    -replace "VALUE_SO_VERSION", $binaryversion `
    -replace "VALUE_SHARED", $SharedLib `
    -replace "VALUE_BINARY", $BinaryLib `
    -replace "VALUE_STATIC", $StaticLib `
    -replace "VALUE_LIB_NAME", $caresLibName `
    -replace "VALUE_CMAKE_PATH", $caresCMakePath

    $EnvContent | Out-File -FilePath $caresEnvScript -Encoding utf8
    Write-Host "Created: $caresEnvScript" -ForegroundColor Gray
    
    # Update Current Session
    if (Test-Path $caresEnvScript) { . $caresEnvScript } else {
        Write-Error "cares build install finished but $caresEnvScript was not created."
        Pop-Location; return
    }
    
    if ($caresWithMachineEnvironment)
    {
        # Generating Machine Environment wich add to the persist registry machine Environment
        $MachineEnvContent = @'
# CARES Machine Environment Setup

# --- 0. Self-Elevation Logic ---
$IsAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$ScopeColor = "Cyan"

if (-not $IsAdmin) {
    Write-Host "Elevation required to set CARES system variables. Relaunching as Administrator..." -ForegroundColor Yellow
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

$caresroot = "VALUE_ROOT_PATH"
$caresbin = "VALUE_BIN_PATH"
$caresversion = "VALUE_VERSION"

$TargetScope = if ($IsAdmin) { "Machine" } else { "User" }
$RegPath = if ($IsAdmin) { "System\CurrentControlSet\Control\Session Manager\Environment" } else { "Environment" }
$RegRoot = if ($IsAdmin) { "LocalMachine" } else { "CurrentUser" }

# Open the registry key once
$RegKey = [Microsoft.Win32.Registry]::$RegRoot.OpenSubKey($RegPath, $true)

# Open the registry key directly to read the RAW (unexpanded) string
$CurrentRawPath = $RegKey.GetValue("EXTCOMPLIBS_PATH", "", [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)

# Cleanup: Remove empty strings, any path containing $caresroot, and the current target (to avoid dups)
$CleanedPathList = $CurrentRawPath -split ';' | Where-Object { 
    -not [string]::IsNullOrWhitespace($_) -and 
    $_ -notlike "*$caresroot*"
}

$NewPath = ($CleanedPathList -join ";").Replace(";;", ";")

$TargetPath = $caresbin

# Rebuild
$NewPath = ($NewPath + ";" + $TargetPath + ";").Replace(";;", ";")
Write-Host "[UPDATED] ($TargetScope) '$caresbin' synced in EXTCOMPLIBS_PATH" -ForegroundColor $ScopeColor

# Save as ExpandString
$RegKey.SetValue("EXTCOMPLIBS_PATH", $NewPath, [Microsoft.Win32.RegistryValueKind]::ExpandString)
$env:EXTCOMPLIBS_PATH = $NewPath

$RegKey.Close()

$env:CARES_ROOT = $caresroot
Write-Host "CARES Environment Loaded (Version: $caresversion) (Bin: $caresbin)" -ForegroundColor Green
Write-Host "CARES_ROOT: $env:CARES_ROOT" -ForegroundColor Gray
'@  -replace "VALUE_ROOT_PATH", $caresInstallDir `
    -replace "VALUE_BIN_PATH", $caresBinPath `
    -replace "VALUE_VERSION", $caresVersion

        $MachineEnvContent | Out-File -FilePath $caresMachineEnvScript -Encoding utf8 -force
        Write-Host "Created: $caresMachineEnvScript" -ForegroundColor Gray
        
        # --- Interaction: Prompt to apply persistent changes ---
        Write-Host ""
        $choice = Read-Host "Do you want to run the Machine Environment script now to persist CARES changes to the Registry? (y/n)"
        if ($choice -eq 'y' -or $choice -eq 'Y') {
            Write-Host "Executing $caresMachineEnvScript..." -ForegroundColor Yellow
            try {
                # Start the generated script. It handles its own elevation logic.
                & $caresMachineEnvScript
            }
            catch {
                Write-Error "Failed to execute the Machine Environment script: $($_.Exception.Message)"
            }
        }
        else {
            Write-Host "Skipped persistent registry update. You can run it later at: $caresMachineEnvScript" -ForegroundColor Gray
        }
    }
    
    # --- Return to Start ---
    Pop-Location
    Write-Host "Successfully Done! and returned to: $(Get-Location)" -ForegroundColor DarkGreen
} else {
    Write-Error "cares.lib was not found in the $caresLibDir folder."
    Pop-Location; return
}
