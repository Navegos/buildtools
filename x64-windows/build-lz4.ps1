# Copyright 2026 (C) Navegos. DevelVitorF. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
# file:x64-windows/build-lz4.ps1

param (
    [Parameter(HelpMessage = "Base workspace path", Mandatory = $false)]
    [string]$workspacePath = $null,

    [Parameter(HelpMessage = "lz4 git repo url", Mandatory = $false)]
    [string]$gitUrl = "https://github.com/lz4/lz4.git",
    
    [Parameter(HelpMessage = "lz4 git branch to sync from", Mandatory = $false)]
    [string]$gitBranch = "dev",

    [Parameter(HelpMessage = "Path for lz4 library storage", Mandatory = $false)]
    [string]$lz4InstallDir = "$env:LIBRARIES_PATH\lz4",
    
    [Parameter(HelpMessage = "Force a full purge of the local lz4 version before continuing", Mandatory = $false)]
    [switch]$forceCleanup,
    
    [Parameter(HelpMessage = "Add's lz4 Machine Environment Variables. Requires Machine Administrator Rights.", Mandatory = $false)]
    [switch]$withMachineEnvironment
)

# Capture parameters
$lz4WorkspacePath = $workspacePath
$lz4GitUrl = $gitUrl
$lz4GitBranch = $gitBranch
$lz4ForceCleanup = $forceCleanup
$lz4WithMachineEnvironment = $withMachineEnvironment

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

$RootPath = if ([string]::IsNullOrWhitespace($lz4WorkspacePath)) { Get-Location } else { $lz4WorkspacePath }

# --- 6. Path Resolution ---
Push-Location $RootPath

$Source         = Join-Path $RootPath "lz4"
$BuildDirShared = Join-Path $Source "build_shared"
$BuildDirStatic = Join-Path $Source "build_static"
$RepoUrl        = $lz4GitUrl
$Branch         = $lz4GitBranch
$CMakeSource    = Join-Path $Source "build/cmake"
$tag_name       = $Branch
$url            = $RepoUrl

$lz4EnvScript = Join-Path $EnvironmentDir "env-lz4.ps1"
$lz4MachineEnvScript = Join-Path $EnvironmentDir "machine-env-lz4.ps1"

# --- 1. Cleanup Mechanism ---
function Invoke-lz4VersionPurge {
    param ([string]$InstallPath)
    Write-Host "--- Initiating lz4 Purge ---" -ForegroundColor Cyan

    if ($lz4WithMachineEnvironment) {
        $lz4CleanMachineEnvScript = Join-Path $env:TEMP "clean-machine-env-lz4.ps1"

        # Generating Clean Machine Environment wich removes the persist registry machine Environment
        $CleanMachineEnvContent = @'
# lz4 Clean Machine Environment Setup

# --- 0. Self-Elevation Logic ---
$IsAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$ScopeColor = "Cyan"

if (-not $IsAdmin) {
    Write-Host "Elevation required to clean lz4 system variables. Relaunching as Administrator..." -ForegroundColor Yellow
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

$lz4root = "VALUE_ROOT_PATH"

$TargetScope = if ($IsAdmin) { "Machine" } else { "User" }
$RegPath = if ($IsAdmin) { "System\CurrentControlSet\Control\Session Manager\Environment" } else { "Environment" }
$RegRoot = if ($IsAdmin) { "LocalMachine" } else { "CurrentUser" }

# 1. Registry Cleanup (EXTCOMPLIBS_PATH)
$RegKey = [Microsoft.Win32.Registry]::$RegRoot.OpenSubKey($RegPath, $true)

# Open the registry key directly to read the RAW (unexpanded) string
$RawPath = $RegKey.GetValue("EXTCOMPLIBS_PATH", "", [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)

# Cleanup: Remove empty strings, any path containing $lz4root,
$CleanPath = ($RawPath -split ';' | Where-Object { $_ -notlike "*$lz4root*" }) -join ";"

# Save as ExpandString
$RegKey.SetValue("EXTCOMPLIBS_PATH", $CleanPath, [Microsoft.Win32.RegistryValueKind]::ExpandString)
$env:EXTCOMPLIBS_PATH = $CleanPath

$RegKey.Close()

Write-Host "[REMOVED] ($TargetScope) all '*$lz4root*' removed from EXTCOMPLIBS_PATH" -ForegroundColor $ScopeColor
'@  -replace "VALUE_ROOT_PATH", $InstallPath

        $CleanMachineEnvContent | Out-File -FilePath $lz4CleanMachineEnvScript -Encoding utf8
        Write-Host "Created: $lz4CleanMachineEnvScript" -ForegroundColor Gray
        
        # --- Interaction: Prompt to remove persistent changes ---
        Write-Host ""
        $choice = Read-Host "Administrator rights required to Clean Machine Environment lz4 changes? (y/n)"
        if ($choice -eq 'y' -or $choice -eq 'Y') {
            Write-Host "Executing $lz4CleanMachineEnvScript..." -ForegroundColor Yellow
            try {
                # Start the generated script. It handles its own elevation logic.
                & $lz4CleanMachineEnvScript
            }
            catch {
                Write-Error "Failed to execute the Clean Machine Environment script: $($_.Exception.Message)"
                Pop-Location; return
            }
        }
        else {
            Write-Error "Skipped Clean Machine Environment lz4 changes."
            Pop-Location; return
        }

        # Cleanup
        Remove-Item $lz4CleanMachineEnvScript -Recurse -Force -ErrorAction SilentlyContinue
    }

    # 2. Filesystem Clean (Requires checking for locked files)
    # delete everithing we create don't fail later
    if (Test-Path $lz4EnvScript) {
        Write-Host "  [DELETING] $lz4EnvScript" -ForegroundColor Yellow
        Remove-Item $lz4EnvScript -Recurse -Force -ErrorAction SilentlyContinue
    }
    if (Test-Path $lz4MachineEnvScript) {
        Write-Host "  [DELETING] $lz4MachineEnvScript" -ForegroundColor Yellow
        Remove-Item $lz4MachineEnvScript -Recurse -Force -ErrorAction SilentlyContinue
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
    Get-ChildItem Env:\LZ4_PATH* | Remove-Item -ErrorAction SilentlyContinue
    Get-ChildItem Env:\LZ4_ROOT* | Remove-Item -ErrorAction SilentlyContinue
    Get-ChildItem Env:\LZ4_BIN* | Remove-Item -ErrorAction SilentlyContinue
    Get-ChildItem Env:\LZ4_INCLUDE_DIR* | Remove-Item -ErrorAction SilentlyContinue
    Get-ChildItem Env:\LZ4_LIBRARY_DIR* | Remove-Item -ErrorAction SilentlyContinue
    Get-ChildItem Env:\BINARY_LIB_LZ4* | Remove-Item -ErrorAction SilentlyContinue
    Get-ChildItem Env:\SHARED_LIB_LZ4* | Remove-Item -ErrorAction SilentlyContinue
    Get-ChildItem Env:\STATIC_LIB_LZ4* | Remove-Item -ErrorAction SilentlyContinue

    Write-Host "--- LZ4 Purge Complete ---" -ForegroundColor Green
}

if ($lz4ForceCleanup) {
    Invoke-lz4VersionPurge -InstallPath $lz4InstallDir
}

# --- 7. Source Management ---
if (Test-Path $Source) {
    Write-Host "Syncing lz4 ($Branch) at $Source..." -ForegroundColor Cyan
    Set-Location $Source
    git fetch --all
    git reset --hard "origin/$Branch"
    git pull --recurse-submodules --force
    $tagCommit = (& git rev-parse --verify HEAD).Trim()
} else {
    Write-Host "Cloning lz4 ($Branch) into $Source..." -ForegroundColor Cyan
    git clone --recurse-submodules $RepoUrl $Source -b $Branch
    Set-Location $Source
    $tagCommit = (& git rev-parse --verify HEAD).Trim()
}

# --- 8. Clean Final Destination ---
if (Test-Path $lz4InstallDir) {
    Write-Host "Wiping existing installation..." -ForegroundColor Yellow
    Remove-Item $lz4InstallDir -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "[INSTALL] Creating fresh directory: $lz4InstallDir" -ForegroundColor Cyan
New-Item -Path $lz4InstallDir -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null

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
    "-DLZ4_BUILD_CLI=OFF",
    "-DLZ4_BUNDLED_MODE=OFF"
)

# --- 9. STAGE 1: Build Static Libraries ---
Write-Host "Building Static (lz4s.lib)..." -ForegroundColor Cyan
cmake $CommonCmakeArgs `
    -S "$CMakeSource" `
    -B "$BuildDirStatic" `
    -DCMAKE_INSTALL_PREFIX="$lz4InstallDir" `
    -DBUILD_SHARED_LIBS=OFF `
    -DBUILD_STATIC_LIBS=ON `
    -DCMAKE_C_FLAGS="-Wno-deprecated-declarations -D_CRT_SECURE_NO_WARNINGS=1" `
    -DCMAKE_CXX_FLAGS="-Wno-deprecated-declarations -D_CRT_SECURE_NO_WARNINGS=1" `
    --no-warn-unused-cli
    
if ($LASTEXITCODE -ne 0) { Write-Error "lz4 CMake Static (lz4s.lib) configuration failed."; Pop-Location; return }

Write-Host "Building and Installing static lib to $lz4InstallDir..." -ForegroundColor Green
cmake --build "$BuildDirStatic" --target install --config Release --parallel

if ($LASTEXITCODE -ne 0) { Write-Error "lz4 Static Build failed with exit code $LASTEXITCODE"; Pop-Location; return }

# Rename static lib to lz4s.lib to avoid collision
$StaticLibPath = Join-Path $lz4InstallDir "lib/lz4.lib"
$NewStaticName = Join-Path $lz4InstallDir "lib/lz4s.lib"
if (Test-Path $StaticLibPath) {
    Move-Item -Path $StaticLibPath -Destination $NewStaticName -Force -ErrorAction SilentlyContinue
    Write-Host "Static library renamed to lz4s.lib" -ForegroundColor Gray
}

# --- 10. STAGE 2: Build Shared Libraries ---
Write-Host "Building Shared (DLL)..." -ForegroundColor Cyan
cmake $CommonCmakeArgs `
    -S "$CMakeSource" `
    -B "$BuildDirShared" `
    -DCMAKE_INSTALL_PREFIX="$lz4InstallDir" `
    -DBUILD_SHARED_LIBS=ON `
    -DBUILD_STATIC_LIBS=OFF `
    -DCMAKE_C_FLAGS="-Wno-deprecated-declarations -D_CRT_SECURE_NO_WARNINGS=1" `
    -DCMAKE_CXX_FLAGS="-Wno-deprecated-declarations -D_CRT_SECURE_NO_WARNINGS=1" `
    --no-warn-unused-cli
    
if ($LASTEXITCODE -ne 0) { Write-Error "lz4 CMake Shared (DLL) configuration failed."; Pop-Location; return }

Write-Host "Building and Installing dynamic lib to $lz4InstallDir..." -ForegroundColor Green
cmake --build "$BuildDirShared" --target install --config Release --parallel

if ($LASTEXITCODE -ne 0) { Write-Error "lz4 Shared Build failed with exit code $LASTEXITCODE"; Pop-Location; return }

Write-Host "Successfully built and installed lz4 to $lz4InstallDir!" -ForegroundColor Green

# Cleanup temporary build debris
Remove-Item $BuildDirShared -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item $BuildDirStatic -Recurse -Force -ErrorAction SilentlyContinue

# Generate Environment Helper with Clean Paths
$lz4InstallDir = $lz4InstallDir.TrimEnd('\')
$lz4IncludeDir = Join-Path $lz4InstallDir "include"
$lz4LibDir = Join-Path $lz4InstallDir "lib"
$lz4BinPath = Join-Path $lz4InstallDir "bin"
$lz4CMakePath = $lz4InstallDir.Replace('\', '/')

$StaticLib = Join-Path $lz4LibDir "lz4static.lib"
$SharedLib = Join-Path $lz4LibDir "lz4.lib"
$BinaryLib = Join-Path $lz4BinPath "lz4.dll"
$versionFile = Join-Path $lz4InstallDir "version.json"

# Fallback check for "lz4.lib" / "lz4s.lib" naming convention
if (-not (Test-Path $StaticLib)) { $StaticLib = Join-Path $lz4LibDir "lz4s.lib" }
#if (-not (Test-Path $SharedLib)) { $SharedLib = Join-Path $lz4LibDir "lz4.lib" }
#if (-not (Test-Path $BinaryLib)) { $BinaryLib = Join-Path $lz4BinPath "lz4.dll" }

if ((Test-Path $StaticLib) -or (Test-Path $SharedLib) -or (Test-Path $BinaryLib)) {
    $lz4Header = Join-Path $lz4IncludeDir "lz4.h"
    if (-not (Test-Path $lz4Header)) { $lz4Header = Join-Path $Source "lib\lz4.h" }
    $localVersion = "0.0.0"
    $rawVersion = $Branch
    
    if (Test-Path $lz4Header) {
        # Extract version from #define #define LZ4_VERSION_MAJOR  #define LZ4_VERSION_MINOR #define LZ4_VERSION_RELEASE
        $headerContent = Get-Content $lz4Header
        
        # Extract Major, Minor, and Release versions
        $major = ($headerContent | Select-String '#define\s+LZ4_VERSION_MAJOR\s+(\d+)').Matches.Groups[1].Value
        $minor = ($headerContent | Select-String '#define\s+LZ4_VERSION_MINOR\s+(\d+)').Matches.Groups[1].Value
        $rel = ($headerContent | Select-String '#define\s+LZ4_VERSION_RELEASE\s+(\d+)').Matches.Groups[1].Value

        if ($major -and $minor -and $rel) {
            $localVersion = "$major.$minor.$rel"
            $rawVersion = $localVersion
            Write-Host "[VERSION] Detected lz4: $localVersion" -ForegroundColor Cyan
        }
    }
    
    # Save new version state
    $lz4Version = $localVersion
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
# LZ4 Environment Setup
$lz4root = "VALUE_ROOT_PATH"
$lz4include = "VALUE_INCLUDE_PATH"
$lz4library = "VALUE_LIB_PATH"
$lz4bin = "VALUE_BIN_PATH"
$lz4version = "VALUE_VERSION"
$lz4binary = "VALUE_BINARY"
$lz4shared = "VALUE_SHARED"
$lz4static = "VALUE_STATIC"
$lz4cmakepath = "VALUE_CMAKE_PATH"
$env:LZ4_PATH = $lz4root
$env:LZ4_ROOT = $lz4root
$env:LZ4_BIN = $lz4bin
$env:LZ4_INCLUDE_DIR = $lz4include
$env:LZ4_LIBRARY_DIR = $lz4library
$env:BINARY_LIB_LZ4 = $lz4binary
$env:SHARED_LIB_LZ4 = $lz4shared
$env:STATIC_LIB_LZ4 = $lz4static
if ($env:CMAKE_PREFIX_PATH -notlike "*$lz4cmakepath*") { $env:CMAKE_PREFIX_PATH = $lz4cmakepath + ";" + $env:CMAKE_PREFIX_PATH; $env:CMAKE_PREFIX_PATH = ($env:CMAKE_PREFIX_PATH).Replace(";;", ";") }
if ($env:INCLUDE -notlike "*$lz4include*") { $env:INCLUDE = $lz4include + ";" + $env:INCLUDE; $env:INCLUDE = ($env:INCLUDE).Replace(";;", ";") }
if ($env:LIB -notlike "*$lz4library*") { $env:LIB = $lz4library + ";" + $env:LIB; $env:LIB = ($env:LIB).Replace(";;", ";") }
if ($env:PATH -notlike "*$lz4bin*") { $env:PATH = $lz4bin + ";" + $env:PATH; $env:PATH = ($env:PATH).Replace(";;", ";") }
Write-Host "lz4 Environment Loaded (Version: $lz4version) (Bin: $lz4bin)" -ForegroundColor Green
Write-Host "LZ4_ROOT: $env:LZ4_ROOT" -ForegroundColor Gray
'@  -replace "VALUE_ROOT_PATH", $lz4InstallDir `
    -replace "VALUE_INCLUDE_PATH", $lz4IncludeDir `
    -replace "VALUE_LIB_PATH", $lz4LibDir `
    -replace "VALUE_BIN_PATH", $lz4BinPath `
    -replace "VALUE_VERSION", $lz4Version `
    -replace "VALUE_SHARED", $SharedLib `
    -replace "VALUE_BINARY", $BinaryLib `
    -replace "VALUE_STATIC", $StaticLib `
    -replace "VALUE_CMAKE_PATH", $lz4CMakePath

    $EnvContent | Out-File -FilePath $lz4EnvScript -Encoding utf8
    Write-Host "Created: $lz4EnvScript" -ForegroundColor Gray
    
    # Update Current Session
    if (Test-Path $lz4EnvScript) { . $lz4EnvScript } else {
        Write-Error "lz4 build install finished but $lz4EnvScript was not created."
        Pop-Location; return
    }
    
    if ($lz4WithMachineEnvironment)
    {
        # Generating Machine Environment wich add to the persist registry machine Environment
        $MachineEnvContent = @'
# lz4 Machine Environment Setup

# --- 0. Self-Elevation Logic ---
$IsAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$ScopeColor = "Cyan"

if (-not $IsAdmin) {
    Write-Host "Elevation required to set lz4 system variables. Relaunching as Administrator..." -ForegroundColor Yellow
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

$lz4root = "VALUE_ROOT_PATH"
$lz4bin = "VALUE_BIN_PATH"
$lz4version = "VALUE_VERSION"

$TargetScope = if ($IsAdmin) { "Machine" } else { "User" }
$RegPath = if ($IsAdmin) { "System\CurrentControlSet\Control\Session Manager\Environment" } else { "Environment" }
$RegRoot = if ($IsAdmin) { "LocalMachine" } else { "CurrentUser" }

# Open the registry key once
$RegKey = [Microsoft.Win32.Registry]::$RegRoot.OpenSubKey($RegPath, $true)

# Open the registry key directly to read the RAW (unexpanded) string
$CurrentRawPath = $RegKey.GetValue("EXTCOMPLIBS_PATH", "", [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)

# Cleanup: Remove empty strings, any path containing $lz4root, and the current target (to avoid dups)
$CleanedPathList = $CurrentRawPath -split ';' | Where-Object { 
    -not [string]::IsNullOrWhitespace($_) -and 
    $_ -notlike "*$lz4root*"
}

$NewRawPath = ($CleanedPathList -join ";").Replace(";;", ";")

$TargetPath = $lz4bin

# Rebuild
$NewRawPath = ($NewRawPath + ";" + $TargetPath + ";").Replace(";;", ";")
Write-Host "[UPDATED] ($TargetScope) '$lz4bin' synced in EXTCOMPLIBS_PATH" -ForegroundColor $ScopeColor

# Save as ExpandString
$RegKey.SetValue("EXTCOMPLIBS_PATH", $NewRawPath, [Microsoft.Win32.RegistryValueKind]::ExpandString)
$env:EXTCOMPLIBS_PATH = $NewRawPath

$RegKey.Close()

$env:LZ4_ROOT = $lz4root
Write-Host "lz4 Environment Loaded (Version: $lz4version) (Bin: $lz4bin)" -ForegroundColor Green
Write-Host "LZ4_ROOT: $env:LZ4_ROOT" -ForegroundColor Gray
'@  -replace "VALUE_ROOT_PATH", $lz4InstallDir `
    -replace "VALUE_BIN_PATH", $lz4BinPath `
    -replace "VALUE_VERSION", $lz4Version

        $MachineEnvContent | Out-File -FilePath $lz4MachineEnvScript -Encoding utf8
        Write-Host "Created: $lz4MachineEnvScript" -ForegroundColor Gray
        
        # --- Interaction: Prompt to apply persistent changes ---
        Write-Host ""
        $choice = Read-Host "Do you want to run the Machine Environment script now to persist lz4 changes to the Registry? (y/n)"
        if ($choice -eq 'y' -or $choice -eq 'Y') {
            Write-Host "Executing $lz4MachineEnvScript..." -ForegroundColor Yellow
            try {
                # Start the generated script. It handles its own elevation logic.
                & $lz4MachineEnvScript
            }
            catch {
                Write-Error "Failed to execute the Machine Environment script: $($_.Exception.Message)"
            }
        }
        else {
            Write-Host "Skipped persistent registry update. You can run it later at: $lz4MachineEnvScript" -ForegroundColor Gray
        }
    }
    
    # --- Return to Start ---
    Pop-Location
    Write-Host "Successfully Done! and returned to: $(Get-Location)" -ForegroundColor DarkGreen
} else {
    Write-Error "lz4.lib was not found in the $lz4LibDir folder."
    Pop-Location; return
}
