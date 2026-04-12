# Copyright 2026 (C) Navegos. DevelVitorF. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
# file:x64-windows/build-zstd.ps1

param (
    [Parameter(HelpMessage = "Base workspace path", Mandatory = $false)]
    [string]$workspacePath = $null,

    [Parameter(HelpMessage = "zstd git repo url", Mandatory = $false)]
    [string]$gitUrl = "https://github.com/facebook/zstd.git",
    
    [Parameter(HelpMessage = "zstd git branch to sync from", Mandatory = $false)]
    [string]$gitBranch = "dev",

    [Parameter(HelpMessage = "Path for zstd library storage", Mandatory = $false)]
    [string]$zstdInstallDir = "$env:LIBRARIES_PATH\zstd",
    
    [Parameter(HelpMessage = "Force a full purge of the local zstd version before continuing", Mandatory = $false)]
    [switch]$forceCleanup,
    
    [Parameter(HelpMessage = "Add's zstd Machine Environment Variables. Requires Machine Administrator Rights.", Mandatory = $false)]
    [switch]$withMachineEnvironment
)

# Capture parameters
$zstdWorkspacePath = $workspacePath
$zstdGitUrl = $gitUrl
$zstdGitBranch = $gitBranch
$zstdForceCleanup = $forceCleanup
$zstdWithMachineEnvironment = $withMachineEnvironment

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
if (-not $env:GIT_PATH) {
    $gitEnvScript = Join-Path $EnvironmentDir "env-git.ps1"
    if (Test-Path $gitEnvScript) { . $gitEnvScript } 
    if (-not $env:GIT_PATH) {
        $depgitEnvScript = Join-Path $PSScriptRoot "dep-git.ps1"
        if (Test-Path $depgitEnvScript) { . $depgitEnvScript }
        else {
            Write-Error "CRITICAL: Cannot load Git environment. git is missing and $depgitEnvScript was not found."
            return
        }
    }
}

# --- 3. Initialize cmake environment if missing ---
if (-not $env:CMAKE_PATH) {
    $cmakeEnvScript = Join-Path $EnvironmentDir "env-cmake.ps1"
    if (Test-Path $cmakeEnvScript) { . $cmakeEnvScript } 
    if (-not $env:CMAKE_PATH) {
        $depcmakeEnvScript = Join-Path $PSScriptRoot "dep-cmake.ps1"
        if (Test-Path $depcmakeEnvScript) { . $depcmakeEnvScript }
        else {
            Write-Error "CRITICAL: Cannot load CMake environment. cmake is missing and $depcmakeEnvScript was not found."
            return
        }
    }
}

# --- 4. Initialize ninja environment if missing ---
if (-not $env:NINJA_PATH) {
    $ninjaEnvScript = Join-Path $EnvironmentDir "env-ninja.ps1"
    if (Test-Path $ninjaEnvScript) { . $ninjaEnvScript }
    if (-not $env:NINJA_PATH) {
        $depninjaEnvScript = Join-Path $PSScriptRoot "dep-ninja.ps1"
        if (Test-Path $depninjaEnvScript) { . $depninjaEnvScript }
        else {
            Write-Error "CRITICAL: Cannot load ninja environment. ninja is missing and $depninjaEnvScript was not found."
            return
        }
    }
}

# --- 5. Initialize clang environment if missing ---
if (-not $env:LLVM_PATH) {
    $llvmEnvScript = Join-Path $EnvironmentDir "env-llvm.ps1"
    if (Test-Path $llvmEnvScript) { . $llvmEnvScript }
    if (-not $env:LLVM_PATH) {
        $depllvmEnvScript = Join-Path $PSScriptRoot "dep-llvm.ps1"
        if (Test-Path $depllvmEnvScript) { . $depllvmEnvScript }
        else {
            Write-Error "CRITICAL: Cannot load clang environment. clang is missing and $depllvmEnvScript was not found."
            return
        }
    }
}

# --- Dependencies: ---
$RootlibzstdInstallDir = Split-Path -Path $zstdInstallDir -Parent
$RootzstdWorkspacePath = if ([string]::IsNullOrWhitespace($zstdWorkspacePath)) { Get-Location } else { $zstdWorkspacePath }

# Load Lzma requirement
if ([string]::IsNullOrWhiteSpace($env:SHARED_LIB_LZMA) -or -not (Test-Path $env:SHARED_LIB_LZMA)) {
    $lzmaEnvScript = Join-Path $EnvironmentDir "env-lzma.ps1"
    if (Test-Path $lzmaEnvScript) { . $lzmaEnvScript }
    if ([string]::IsNullOrWhiteSpace($env:SHARED_LIB_LZMA) -or -not (Test-Path $env:SHARED_LIB_LZMA)) {
        $lzmaBuildScript = Join-Path $PSScriptRoot "build-lzma.ps1"
        if (Test-Path $lzmaBuildScript) {
            $lzmaInstallDir = Join-Path $RootlibzstdInstallDir "lzma"
            & $lzmaBuildScript -workspacePath $RootzstdWorkspacePath -lzmaInstallDir $lzmaInstallDir
        } else {
            Write-Error "CRITICAL: Cannot build lzma. lzma is missing and $lzmaBuildScript was not found."
            return
        }
    }
}

# Load Lz4 requirement
if ([string]::IsNullOrWhiteSpace($env:SHARED_LIB_LZ4) -or -not (Test-Path $env:SHARED_LIB_LZ4)) {
    $lz4EnvScript = Join-Path $EnvironmentDir "env-lz4.ps1"
    if (Test-Path $lz4EnvScript) { . $lz4EnvScript }
    if ([string]::IsNullOrWhiteSpace($env:SHARED_LIB_LZ4) -or -not (Test-Path $env:SHARED_LIB_LZ4)) {
        $lz4BuildScript = Join-Path $PSScriptRoot "build-lz4.ps1"
        if (Test-Path $lz4BuildScript) {
            $lz4InstallDir = Join-Path $RootlibzstdInstallDir "lz4"
            & $lz4BuildScript -workspacePath $RootzstdWorkspacePath -lz4InstallDir $lz4InstallDir
        } else {
            Write-Error "CRITICAL: Cannot build lz4. lz4 is missing and $lz4BuildScript was not found."
            return
        }
    }
}

# Load Zlib requirement
if ([string]::IsNullOrWhiteSpace($env:SHARED_LIB_ZLIB) -or -not (Test-Path $env:SHARED_LIB_ZLIB)) {
    $zlibEnvScript = Join-Path $EnvironmentDir "env-zlib.ps1"
    if (Test-Path $zlibEnvScript) { . $zlibEnvScript }
    if ([string]::IsNullOrWhiteSpace($env:SHARED_LIB_ZLIB) -or -not (Test-Path $env:SHARED_LIB_ZLIB)) {
        $zlibBuildScript = Join-Path $PSScriptRoot "build-zlib.ps1"
        if (Test-Path $zlibBuildScript) {
            $zlibInstallDir = Join-Path $RootlibzstdInstallDir "zlib"
            & $zlibBuildScript -workspacePath $RootzstdWorkspacePath -zlibInstallDir $zlibInstallDir
        } else {
            Write-Error "CRITICAL: Cannot build zlib. zlib is missing and $zlibBuildScript was not found."
            return
        }
    }
}

$RootPath = $RootzstdWorkspacePath

# --- 6. Path Resolution ---
Push-Location $RootPath

$Source         = Join-Path $RootPath "zstd"
$BuildDirShared = Join-Path $Source "build_shared"
$BuildDirStatic = Join-Path $Source "build_static"
$RepoUrl        = $zstdGitUrl
$Branch         = $zstdGitBranch
$CMakeSource    = Join-Path $Source "build/cmake"
$tag_name       = $Branch
$url            = $RepoUrl

$zstdEnvScript = Join-Path $EnvironmentDir "env-zstd.ps1"
$zstdMachineEnvScript = Join-Path $EnvironmentDir "machine-env-zstd.ps1"

# --- 1. Cleanup Mechanism ---
function Invoke-zstdVersionPurge {
    param ([string]$InstallPath)
    Write-Host "--- Initiating zstd Purge ---" -ForegroundColor Cyan

    if ($zstdWithMachineEnvironment)
    {
        $zstdCleanMachineEnvScript = Join-Path $env:TEMP "clean-machine-env-zstd.ps1"

        # Generating Clean Machine Environment wich removes the persist registry machine Environment
        $CleanMachineEnvContent = @'
# zstd Clean Machine Environment Setup

# --- 0. Self-Elevation Logic ---
$IsAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$ScopeColor = "Cyan"

if (-not $IsAdmin) {
    Write-Host "Elevation required to clean zstd system variables. Relaunching as Administrator..." -ForegroundColor Yellow
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

$zstdroot = "VALUE_ROOT_PATH"

$TargetScope = if ($IsAdmin) { "Machine" } else { "User" }
$RegPath = if ($IsAdmin) { "System\CurrentControlSet\Control\Session Manager\Environment" } else { "Environment" }
$RegRoot = if ($IsAdmin) { "LocalMachine" } else { "CurrentUser" }

# 1. Registry Cleanup (EXTCOMPLIBS_PATH)
$RegKey = [Microsoft.Win32.Registry]::$RegRoot.OpenSubKey($RegPath, $true)

# Open the registry key directly to read the RAW (unexpanded) string
$RawPath = $RegKey.GetValue("EXTCOMPLIBS_PATH", "", [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)

# Cleanup: Remove empty strings, any path containing $zstdroot,
$CleanPath = ($RawPath -split ';' | Where-Object { $_ -notlike "*$zstdroot*" }) -join ";"

# Save as ExpandString
$RegKey.SetValue("EXTCOMPLIBS_PATH", $CleanPath, [Microsoft.Win32.RegistryValueKind]::ExpandString)
$env:EXTCOMPLIBS_PATH = $CleanPath

$RegKey.Close()

Write-Host "[REMOVED] ($TargetScope) all '*$zstdroot*' removed from EXTCOMPLIBS_PATH" -ForegroundColor $ScopeColor
'@  -replace "VALUE_ROOT_PATH", $InstallPath

        $CleanMachineEnvContent | Out-File -FilePath $zstdCleanMachineEnvScript -Encoding utf8
        Write-Host "Created: $zstdCleanMachineEnvScript" -ForegroundColor Gray
        
        # --- Interaction: Prompt to remove persistent changes ---
        Write-Host ""
        $choice = Read-Host "Administrator rights required to Clean Machine Environment zstd changes? (y/n)"
        if ($choice -eq 'y' -or $choice -eq 'Y') {
            Write-Host "Executing $zstdCleanMachineEnvScript..." -ForegroundColor Yellow
            try {
                # Start the generated script. It handles its own elevation logic.
                & $zstdCleanMachineEnvScript
            }
            catch {
                Write-Error "Failed to execute the Clean Machine Environment script: $($_.Exception.Message)"
                Pop-Location; return
            }
        }
        else {
            Write-Error "Skipped Clean Machine Environment zstd changes."
            Pop-Location; return
        }

        # Cleanup
        Remove-Item $zstdCleanMachineEnvScript -Recurse -Force -ErrorAction SilentlyContinue
    }

    # 2. Filesystem Clean (Requires checking for locked files)
    # delete everithing we create don't fail later
    if (Test-Path $zstdEnvScript) {
        Write-Host "  [DELETING] $zstdEnvScript" -ForegroundColor Yellow
        Remove-Item $zstdEnvScript -Recurse -Force -ErrorAction SilentlyContinue
    }
    if (Test-Path $zstdMachineEnvScript) {
        Write-Host "  [DELETING] $zstdMachineEnvScript" -ForegroundColor Yellow
        Remove-Item $zstdMachineEnvScript -Recurse -Force -ErrorAction SilentlyContinue
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
    Get-ChildItem Env:\ZSTD_PATH* | Remove-Item -ErrorAction SilentlyContinue
    Get-ChildItem Env:\ZSTD_ROOT* | Remove-Item -ErrorAction SilentlyContinue
    Get-ChildItem Env:\ZSTD_BIN* | Remove-Item -ErrorAction SilentlyContinue
    Get-ChildItem Env:\ZSTD_INCLUDE_DIR* | Remove-Item -ErrorAction SilentlyContinue
    Get-ChildItem Env:\ZSTD_LIBRARY_DIR* | Remove-Item -ErrorAction SilentlyContinue
    Get-ChildItem Env:\BINARY_LIB_ZSTD* | Remove-Item -ErrorAction SilentlyContinue
    Get-ChildItem Env:\SHARED_LIB_ZSTD* | Remove-Item -ErrorAction SilentlyContinue
    Get-ChildItem Env:\STATIC_LIB_ZSTD* | Remove-Item -ErrorAction SilentlyContinue

    Write-Host "--- ZSTD Purge Complete ---" -ForegroundColor Green
}

if ($zstdForceCleanup) {
    Invoke-zstdVersionPurge -InstallPath $zstdInstallDir
}

# --- 7. Source Management ---
if (Test-Path $Source) {
    Write-Host "Syncing zstd ($Branch) at $Source..." -ForegroundColor Cyan
    Set-Location $Source
    git fetch --all
    git reset --hard "origin/$Branch"
    git pull --recurse-submodules --force
    $tagCommit = (& git rev-parse --verify HEAD).Trim()
} else {
    Write-Host "Cloning zstd ($Branch) into $Source..." -ForegroundColor Cyan
    git clone --recurse-submodules $RepoUrl $Source -b $Branch
    Set-Location $Source
    $tagCommit = (& git rev-parse --verify HEAD).Trim()
}

# --- 8. Clean Final Destination ---
if (Test-Path $zstdInstallDir) {
    Write-Host "Wiping existing installation at $zstdInstallDir..." -ForegroundColor Yellow
    Remove-Item $zstdInstallDir -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "[INSTALL] Creating fresh directory: $zstdInstallDir" -ForegroundColor Cyan
New-Item -Path $zstdInstallDir -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null

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
    "-DZSTD_LEGACY_SUPPORT=ON",
    "-DZSTD_MULTITHREAD_SUPPORT=ON",
    "-DZSTD_ENABLE_CXX=ON",
    "-DZSTD_BUILD_PROGRAMS=OFF",
    "-DZSTD_BUILD_TESTS=OFF",
    "-DZSTD_BUILD_TOOLS=OFF",
    "-DZSTD_BUILD_CONTRIB=OFF",
    "-DZSTD_BUILD_EXAMPLES=OFF",
    "-DZSTD_BUILD_DOCS=OFF"
)

# --- 9. STAGE 1: Build Static Libraries ---
Write-Host "Building Static (zstds.lib)..." -ForegroundColor Cyan
cmake $CommonCmakeArgs `
    -S "$CMakeSource" `
    -B "$BuildDirStatic" `
    -DCMAKE_INSTALL_PREFIX="$zstdInstallDir" `
    -DZSTD_BUILD_SHARED=OFF `
    -DZSTD_BUILD_STATIC=ON `
    -DCMAKE_C_FLAGS="-DLZMA_API_STATIC -DLZ4_DLL_IMPORT=0 -DZLIB_STATIC -Wno-deprecated-declarations -D_CRT_SECURE_NO_WARNINGS=1" `
    -DCMAKE_CXX_FLAGS="-DLZMA_API_STATIC -DLZ4_DLL_IMPORT=0 -DZLIB_STATIC -Wno-deprecated-declarations -D_CRT_SECURE_NO_WARNINGS=1" `
    --no-warn-unused-cli

if ($LASTEXITCODE -ne 0) { Write-Error "zstd CMake Static (zstds.lib) configuration failed."; Pop-Location; return }

Write-Host "Building and Installing static lib to $zstdInstallDir..." -ForegroundColor Green
cmake --build "$BuildDirStatic" --target install --config Release --parallel

if ($LASTEXITCODE -ne 0) { Write-Error "zstd Static Build failed with exit code $LASTEXITCODE"; Pop-Location; return }

# Rename static lib to zstds.lib to avoid collision
$StaticLibPath = Join-Path $zstdInstallDir "lib/zstd.lib"
$NewStaticName = Join-Path $zstdInstallDir "lib/zstds.lib"
if (Test-Path $StaticLibPath) {
    Move-Item -Path $StaticLibPath -Destination $NewStaticName -Force -ErrorAction SilentlyContinue
    Write-Host "Static library renamed to zstds.lib" -ForegroundColor Gray
}

# --- 10. STAGE 2: Build Shared Libraries ---
Write-Host "Building Shared (DLL)..." -ForegroundColor Cyan
cmake $CommonCmakeArgs `
    -S "$CMakeSource" `
    -B "$BuildDirShared" `
    -DCMAKE_INSTALL_PREFIX="$zstdInstallDir" `
    -DZSTD_BUILD_SHARED=ON `
    -DZSTD_BUILD_STATIC=OFF `
    -DCMAKE_C_FLAGS="-Wno-deprecated-declarations -D_CRT_SECURE_NO_WARNINGS=1" `
    -DCMAKE_CXX_FLAGS="-Wno-deprecated-declarations -D_CRT_SECURE_NO_WARNINGS=1" `
    --no-warn-unused-cli
    
if ($LASTEXITCODE -ne 0) { Write-Error "zstd CMake Shared (DLL) configuration failed."; Pop-Location; return }

Write-Host "Building and Installing dynamic lib to $zstdInstallDir..." -ForegroundColor Green
cmake --build "$BuildDirShared" --target install --config Release --parallel

if ($LASTEXITCODE -ne 0) { Write-Error "zstd Shared Build failed with exit code $LASTEXITCODE"; Pop-Location; return }

Write-Host "Successfully built and installed zstd to $zstdInstallDir!" -ForegroundColor Green

# Cleanup temporary build debris
Remove-Item $BuildDirShared -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item $BuildDirStatic -Recurse -Force -ErrorAction SilentlyContinue

# Generate Environment Helper with Clean Paths
$zstdInstallDir = $zstdInstallDir.TrimEnd('\')
$zstdIncludeDir = Join-Path $zstdInstallDir "include"
$zstdLibDir = Join-Path $zstdInstallDir "lib"
$zstdBinPath = Join-Path $zstdInstallDir "bin"
$zstdCMakePath = $zstdInstallDir.Replace('\', '/')

$StaticLib = Join-Path $zstdLibDir "zstdstatic.lib"
$SharedLib = Join-Path $zstdLibDir "zstd.lib"
$BinaryLib = Join-Path $zstdBinPath "zstd.dll"
$versionFile = Join-Path $zstdInstallDir "version.json"

# Fallback check for "z.lib" / "zs.lib" naming convention
if (-not (Test-Path $StaticLib)) { $StaticLib = Join-Path $zstdLibDir "zstds.lib" }
#if (-not (Test-Path $SharedLib)) { $SharedLib = Join-Path $zstdLibDir "zstd.lib" }
#if (-not (Test-Path $BinaryLib)) { $BinaryLib = Join-Path $zstdBinPath "zstd.dll" }

if ((Test-Path $StaticLib) -or (Test-Path $SharedLib) -or (Test-Path $BinaryLib)) {
    $zstdHeader = Join-Path $zstdIncludeDir "zstd.h"
    if (-not (Test-Path $zstdHeader)) { $zstdHeader = Join-Path $Source "lib\zstd.h" }
    $localVersion = "0.0.0"
    $rawVersion = $Branch
    
    if (Test-Path $zstdHeader) {
        # Extract version from #define #define ZSTD_VERSION_MAJOR  #define ZSTD_VERSION_MINOR #define ZSTD_VERSION_RELEASE
        $headerContent = Get-Content $zstdHeader
        
        # Extract Major, Minor, and Release versions
        $major = ($headerContent | Select-String '#define\s+ZSTD_VERSION_MAJOR\s+(\d+)').Matches.Groups[1].Value
        $minor = ($headerContent | Select-String '#define\s+ZSTD_VERSION_MINOR\s+(\d+)').Matches.Groups[1].Value
        $rel   = ($headerContent | Select-String '#define\s+ZSTD_VERSION_RELEASE\s+(\d+)').Matches.Groups[1].Value

        if ($major -and $minor -and $rel) {
            $localVersion = "$major.$minor.$rel"
            $rawVersion = $localVersion
            Write-Host "[VERSION] Detected zstd: $localVersion" -ForegroundColor Cyan
        }
    }

    # Save new version state
    $zstdVersion = $localVersion
    $versionInfo = @{
        url        = $url;
        tag_name   = $tag_name;
        commit     = $tagCommit;
        version    = $localVersion;
        rawversion = $rawVersion;
        date       = (Get-Date).ToString("yyyy-MM-dd");
        updated_at = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssZ");
        type       = "source_build";
    }
    $versionInfo | ConvertTo-Json | Out-File -FilePath $versionFile -Encoding utf8 -Force

    # --- 11. Create Environment Helper ---
    Write-Host "Generating environment helper script..." -ForegroundColor Cyan
    $EnvContent = @'
# ZSTD Environment Setup
$zstdroot = "VALUE_ROOT_PATH"
$zstdinclude = "VALUE_INCLUDE_PATH"
$zstdlibrary = "VALUE_LIB_PATH"
$zstdbin = "VALUE_BIN_PATH"
$zstdversion = "VALUE_VERSION"
$zstdbinary = "VALUE_BINARY"
$zstdshared = "VALUE_SHARED"
$zstdstatic = "VALUE_STATIC"
$zstdcmakepath = "VALUE_CMAKE_PATH"
$env:ZSTD_PATH = $zstdroot
$env:ZSTD_ROOT = $zstdroot
$env:ZSTD_BIN = $zstdbin
$env:ZSTD_INCLUDE_DIR = $zstdinclude
$env:ZSTD_LIBRARY_DIR = $zstdlibrary
$env:BINARY_LIB_ZSTD = $zstdbinary
$env:SHARED_LIB_ZSTD = $zstdshared
$env:STATIC_LIB_ZSTD = $zstdstatic
if ($env:CMAKE_PREFIX_PATH -notlike "*$zstdcmakepath*") { $env:CMAKE_PREFIX_PATH = $zstdcmakepath + ";" + $env:CMAKE_PREFIX_PATH; $env:CMAKE_PREFIX_PATH = ($env:CMAKE_PREFIX_PATH).Replace(";;", ";") }
if ($env:INCLUDE -notlike "*$zstdinclude*") { $env:INCLUDE = $zstdinclude + ";" + $env:INCLUDE; $env:INCLUDE = ($env:INCLUDE).Replace(";;", ";") }
if ($env:LIB -notlike "*$zstdlibrary*") { $env:LIB = $zstdlibrary + ";" + $env:LIB; $env:LIB = ($env:LIB).Replace(";;", ";") }
if ($env:PATH -notlike "*$zstdbin*") { $env:PATH = $zstdbin + ";" + $env:PATH; $env:PATH = ($env:PATH).Replace(";;", ";") }
Write-Host "zstd Environment Loaded (Version: $zstdversion) (Bin: $zstdbin)" -ForegroundColor Green
Write-Host "ZSTD_ROOT: $env:ZSTD_ROOT" -ForegroundColor Gray
'@  -replace "VALUE_ROOT_PATH", $zstdInstallDir `
    -replace "VALUE_INCLUDE_PATH", $zstdIncludeDir `
    -replace "VALUE_LIB_PATH", $zstdLibDir `
    -replace "VALUE_BIN_PATH", $zstdBinPath `
    -replace "VALUE_VERSION", $zstdVersion `
    -replace "VALUE_SHARED", $SharedLib `
    -replace "VALUE_BINARY", $BinaryLib `
    -replace "VALUE_STATIC", $StaticLib `
    -replace "VALUE_CMAKE_PATH", $zstdCMakePath

    $EnvContent | Out-File -FilePath $zstdEnvScript -Encoding utf8
    Write-Host "Created: $zstdEnvScript" -ForegroundColor Gray
    
    # Update Current Session
    if (Test-Path $zstdEnvScript) { . $zstdEnvScript } else {
        Write-Error "zstd build install finished but $zstdEnvScript was not created."
        Pop-Location; return
    }
    
    if ($zstdWithMachineEnvironment)
    {
        # Generating Machine Environment wich add to the persist registry machine Environment
        $MachineEnvContent = @'
# zstd Machine Environment Setup

# --- 0. Self-Elevation Logic ---
$IsAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$ScopeColor = "Cyan"

if (-not $IsAdmin) {
    Write-Host "Elevation required to set zstd system variables. Relaunching as Administrator..." -ForegroundColor Yellow
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

$zstdroot = "VALUE_ROOT_PATH"
$zstdbin = "VALUE_BIN_PATH"
$zstdversion = "VALUE_VERSION"

$TargetScope = if ($IsAdmin) { "Machine" } else { "User" }
$RegPath = if ($IsAdmin) { "System\CurrentControlSet\Control\Session Manager\Environment" } else { "Environment" }
$RegRoot = if ($IsAdmin) { "LocalMachine" } else { "CurrentUser" }

# Open the registry key once
$RegKey = [Microsoft.Win32.Registry]::$RegRoot.OpenSubKey($RegPath, $true)

# Open the registry key directly to read the RAW (unexpanded) string
$CurrentRawPath = $RegKey.GetValue("EXTCOMPLIBS_PATH", "", [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)

# Cleanup: Remove empty strings, any path containing $zstdroot, and the current target (to avoid dups)
$CleanedPathList = $CurrentRawPath -split ';' | Where-Object { 
    -not [string]::IsNullOrWhitespace($_) -and 
    $_ -notlike "*$zstdroot*"
}

$NewRawPath = ($CleanedPathList -join ";").Replace(";;", ";")

$TargetPath = $zstdbin

# Rebuild
$NewRawPath = ($NewRawPath + ";" + $TargetPath + ";").Replace(";;", ";")
Write-Host "[UPDATED] ($TargetScope) '$zstdbin' synced in EXTCOMPLIBS_PATH" -ForegroundColor $ScopeColor

# Save as ExpandString
$RegKey.SetValue("EXTCOMPLIBS_PATH", $NewRawPath, [Microsoft.Win32.RegistryValueKind]::ExpandString)
$env:EXTCOMPLIBS_PATH = $NewRawPath

$RegKey.Close()

$env:ZSTD_ROOT = $zstdroot
Write-Host "zstd Environment Loaded (Version: $zstdversion) (Bin: $zstdbin)" -ForegroundColor Green
Write-Host "ZSTD_ROOT: $env:ZSTD_ROOT" -ForegroundColor Gray
'@  -replace "VALUE_ROOT_PATH", $zstdInstallDir `
    -replace "VALUE_BIN_PATH", $zstdBinPath `
    -replace "VALUE_VERSION", $zstdVersion

        $MachineEnvContent | Out-File -FilePath $zstdMachineEnvScript -Encoding utf8
        Write-Host "Created: $zstdMachineEnvScript" -ForegroundColor Gray
        
        # --- Interaction: Prompt to apply persistent changes ---
        Write-Host ""
        $choice = Read-Host "Do you want to run the Machine Environment script now to persist zstd changes to the Registry? (y/n)"
        if ($choice -eq 'y' -or $choice -eq 'Y') {
            Write-Host "Executing $zstdMachineEnvScript..." -ForegroundColor Yellow
            try {
                # Start the generated script. It handles its own elevation logic.
                & $zstdMachineEnvScript
            }
            catch {
                Write-Error "Failed to execute the Machine Environment script: $($_.Exception.Message)"
            }
        }
        else {
            Write-Host "Skipped persistent registry update. You can run it later at: $zstdMachineEnvScript" -ForegroundColor Gray
        }
    }
    
    # --- Return to Start ---
    Pop-Location
    Write-Host "Successfully Done! and returned to: $(Get-Location)" -ForegroundColor DarkGreen
} else {
    Write-Error "zstd.lib was not found in the $zstdLibDir folder."
    Pop-Location; return
}
