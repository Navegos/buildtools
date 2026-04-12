# Copyright 2026 (C) Navegos. DevelVitorF. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
# file:x64-windows/build-blake3.ps1

param (
    [Parameter(HelpMessage = "Base workspace path", Mandatory = $false)]
    [string]$workspacePath = $null,

    [Parameter(HelpMessage = "BLAKE3 git repo url", Mandatory = $false)]
    [string]$gitUrl = "https://github.com/BLAKE3-team/BLAKE3.git",
    
    [Parameter(HelpMessage = "BLAKE3 branch/tag", Mandatory = $false)]
    [string]$gitBranch = "master",

    [Parameter(HelpMessage = "Path for BLAKE3 library storage", Mandatory = $false)]
    [string]$blake3InstallDir = "$env:LIBRARIES_PATH\blake3",
    
    [Parameter(HelpMessage = "Add's BLAKE3 Machine Environment Variables. Requires Machine Administrator Rights.", Mandatory = $false)]
    [switch]$withMachineEnvironment
)

# Capture parameters
$blake3WorkspacePath = $workspacePath
$blake3GitUrl = $gitUrl
$blake3GitBranch = $gitBranch
$blake3WithMachineEnvironment = $withMachineEnvironment

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
$Rootlibblake3InstallDir = Split-Path -Path $blake3InstallDir -Parent
$Rootblake3WorkspacePath = if ([string]::IsNullOrWhitespace($blake3WorkspacePath)) { Get-Location } else { $blake3WorkspacePath }

#  oneTBB dependencie here etc... preparing this dependencies in other script wait for my update.

$RootPath = $Rootblake3WorkspacePath

# --- 6. Path Resolution ---
Push-Location $RootPath

$Source         = Join-Path $RootPath "blake3"
$BuildDirShared = Join-Path $Source "build_shared"
$BuildDirStatic = Join-Path $Source "build_static"
$RepoUrl        = $blake3GitUrl
$Branch         = $blake3GitBranch
$CMakeSource    = Join-Path $Source "c" # Note: BLAKE3 C implementation uses a 'c' subdirectory for its CMakeLists.txt
$tag_name       = $Branch
$url            = $RepoUrl

$blake3EnvScript = Join-Path $EnvironmentDir "env-blake3.ps1"
$blake3MachineEnvScript = Join-Path $EnvironmentDir "machine-env-blake3.ps1"

# --- 7. Source Management ---
if (Test-Path $Source) {
    Write-Host "Syncing BLAKE3 ($Branch) at $Source..." -ForegroundColor Cyan
    Set-Location $Source
    git fetch --all
    git reset --hard "origin/$Branch"
    git pull --recurse-submodules --force
    $tagCommit = (& git rev-parse --verify HEAD).Trim()
} else {
    Write-Host "Cloning BLAKE3 ($Branch) into $Source..." -ForegroundColor Cyan
    git clone --recurse-submodules $RepoUrl $Source -b $Branch
    Set-Location $Source
    $tagCommit = (& git rev-parse --verify HEAD).Trim()
}

# --- 8. Clean Final Destination ---
if (Test-Path $blake3InstallDir) {
    Write-Host "Wiping existing installation..." -ForegroundColor Yellow
    Remove-Item $blake3InstallDir -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "[INSTALL] Creating fresh directory: $blake3InstallDir" -ForegroundColor Cyan
New-Item -Path $blake3InstallDir -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null

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
    "-DBLAKE3_EXAMPLES=OFF",
    "-DBLAKE3_TESTING=OFF",
    "-DBLAKE3_SIMD_X86_INTRINSICS=ON",
    "-DBLAKE3_NO_SSE2=OFF",
    "-DBLAKE3_NO_SSE41=OFF",
    "-DBLAKE3_NO_AVX2=OFF",
    "-DBLAKE3_USE_TBB=ON"
)

# --- 9. STAGE 1: Build Static Libraries ---
Write-Host "Building BLAKE3 Static..." -ForegroundColor Cyan
cmake $CommonCmakeArgs `
    -S "$CMakeSource" `
    -B "$BuildDirStatic" `
    -DCMAKE_INSTALL_PREFIX="$blake3InstallDir" `
    -DBUILD_SHARED_LIBS=OFF `
    -DCMAKE_C_FLAGS="-Wno-deprecated-declarations -D_CRT_SECURE_NO_WARNINGS=1" `
    -DCMAKE_CXX_FLAGS="-Wno-deprecated-declarations -D_CRT_SECURE_NO_WARNINGS=1" `
    --no-warn-unused-cli

if ($LASTEXITCODE -ne 0) { Write-Error "blake3 CMake Static (blake3s.lib) configuration failed."; Pop-Location; return }

Write-Host "Building and Installing static lib to $blake3InstallDir..." -ForegroundColor Green
cmake --build "$BuildDirStatic" --target install --config Release --parallel

if ($LASTEXITCODE -ne 0) { Write-Error "blake3 Static Build failed with exit code $LASTEXITCODE"; Pop-Location; return }

# --- 9.5. Rename Static Libraries (Suffix 's') ---
Write-Host "Applying 's' suffix to static libs..." -ForegroundColor Gray
Get-ChildItem -Path "$blake3InstallDir\lib\*.lib" | ForEach-Object {
    $newName = $_.BaseName + "s" + $_.Extension
    Move-Item -Path $_.FullName -Destination (Join-Path $_.DirectoryName $newName) -Force -ErrorAction SilentlyContinue
    Write-Host "  -> $newName" -ForegroundColor DarkGray
}

# --- 10. STAGE 2: Build Shared Libraries ---
Write-Host "Building BLAKE3 Shared..." -ForegroundColor Cyan
cmake $CommonCmakeArgs `
    -S "$CMakeSource" `
    -B "$BuildDirShared" `
    -DCMAKE_INSTALL_PREFIX="$blake3InstallDir" `
    -DBUILD_SHARED_LIBS=ON `
    -DCMAKE_C_FLAGS="-Wno-deprecated-declarations -D_CRT_SECURE_NO_WARNINGS=1" `
    -DCMAKE_CXX_FLAGS="-Wno-deprecated-declarations -D_CRT_SECURE_NO_WARNINGS=1" `
    --no-warn-unused-cli

if ($LASTEXITCODE -ne 0) { Write-Error "blake3 CMake Shared (DLL) configuration failed."; Pop-Location; return }

Write-Host "Building and Installing dynamic lib to $blake3InstallDir..." -ForegroundColor Green
cmake --build "$BuildDirShared" --target install --config Release --parallel

if ($LASTEXITCODE -ne 0) { Write-Error "blake3 Shared Build failed with exit code $LASTEXITCODE"; Pop-Location; return }

Write-Host "Successfully built and installed blake3 to $blake3InstallDir!" -ForegroundColor Green

# Cleanup temporary build debris
Remove-Item $BuildDirShared -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item $BuildDirStatic -Recurse -Force -ErrorAction SilentlyContinue

# Generate Environment Helper with Clean Paths
$blake3InstallDir = $blake3InstallDir.TrimEnd('\')
$blake3IncludeDir = Join-Path $blake3InstallDir "include"
$blake3LibDir = Join-Path $blake3InstallDir "lib"
$blake3BinPath = Join-Path $blake3InstallDir "bin"
$blake3CMakePath = $blake3InstallDir.Replace('\', '/')

$StaticLib = Join-Path $blake3LibDir "blake3static.lib"
$SharedLib = Join-Path $blake3LibDir "blake3.lib"
$BinaryLib = Join-Path $blake3BinPath "blake3.dll"
$versionFile = Join-Path $blake3InstallDir "version.json"

# Fallback check for "z.lib" / "zs.lib" naming convention
if (-not (Test-Path $StaticLib)) { $StaticLib = Join-Path $blake3LibDir "blake3s.lib" }
#if (-not (Test-Path $SharedLib)) { $SharedLib = Join-Path $blake3LibDir "blake3.lib" }
#if (-not (Test-Path $BinaryLib)) { $BinaryLib = Join-Path $blake3BinPath "blake3.dll" }

if ((Test-Path $StaticLib) -or (Test-Path $SharedLib) -or (Test-Path $BinaryLib)) {
    $blake3Header = Join-Path $blake3IncludeDir "blake3.h"
    if (-not (Test-Path $blake3Header)) { $blake3Header = Join-Path $Source "c\blake3.h" }
    $localVersion = "0.0.0"
    $rawVersion = $Branch

    if (Test-Path $blake3Header) {
        # Extract version from #define BLAKE3_VERSION_STRING "1.8.4"
        $headerContent = Get-Content $blake3Header
        
        # Regex looks for the define and captures the content inside the quotes
        $versionMatch = ($headerContent | Select-String '#define\s+BLAKE3_VERSION_STRING\s+"([^"]+)"').Matches.Groups[1].Value
    
        if ($versionMatch) {
            $localVersion = $versionMatch
            $rawVersion = $localVersion
            Write-Host "[VERSION] Detected blake3: $localVersion" -ForegroundColor Cyan
        }
    }

    # Save new version state
    $blake3Version = $localVersion
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
# BLAKE3 Environment Setup
$blake3root = "VALUE_ROOT_PATH"
$blake3include = "VALUE_INCLUDE_PATH"
$blake3library = "VALUE_LIB_PATH"
$blake3bin = "VALUE_BIN_PATH"
$blake3version = "VALUE_VERSION"
$blake3binary = "VALUE_BINARY"
$blake3shared = "VALUE_SHARED"
$blake3static = "VALUE_STATIC"
$blake3cmakepath = "VALUE_CMAKE_PATH"
$env:BLAKE3_PATH = $blake3root
$env:BLAKE3_ROOT = $blake3root
$env:BLAKE3_BIN = $blake3bin
$env:BLAKE3_INCLUDE_DIR = $blake3include
$env:BLAKE3_LIBRARY_DIR = $blake3library
$env:BINARY_LIB_BLAKE3 = $blake3binary
$env:SHARED_LIB_BLAKE3 = $blake3shared
$env:STATIC_LIB_BLAKE3 = $blake3static
if ($env:CMAKE_PREFIX_PATH -notlike "*blake3cmakepath*") { $env:CMAKE_PREFIX_PATH = blake3cmakepath + ";" + $env:CMAKE_PREFIX_PATH; $env:CMAKE_PREFIX_PATH = ($env:CMAKE_PREFIX_PATH).Replace(";;", ";") }
if ($env:INCLUDE -notlike "*blake3include*") { $env:INCLUDE = blake3include + ";" + $env:INCLUDE; $env:INCLUDE = ($env:INCLUDE).Replace(";;", ";") }
if ($env:LIB -notlike "*blake3library*") { $env:LIB = blake3library + ";" + $env:LIB; $env:LIB = ($env:LIB).Replace(";;", ";") }
if ($env:PATH -notlike "*blake3bin*") { $env:PATH = blake3bin + ";" + $env:PATH; $env:PATH = ($env:PATH).Replace(";;", ";") }
Write-Host "blake3 Environment Loaded (Version: blake3version) (Bin: blake3bin)" -ForegroundColor Green
Write-Host "BLAKE3_ROOT: $env:BLAKE3_ROOT" -ForegroundColor Gray
'@  -replace "VALUE_ROOT_PATH", $blake3InstallDir `
    -replace "VALUE_INCLUDE_PATH", $blake3IncludeDir `
    -replace "VALUE_LIB_PATH", $blake3LibDir `
    -replace "VALUE_BIN_PATH", $blake3BinPath `
    -replace "VALUE_VERSION", $blake3Version `
    -replace "VALUE_SHARED", $SharedLib `
    -replace "VALUE_BINARY", $BinaryLib `
    -replace "VALUE_STATIC", $StaticLib `
    -replace "VALUE_CMAKE_PATH", $blake3CMakePath

    $EnvContent | Out-File -FilePath $blake3EnvScript -Encoding utf8
    Write-Host "Created: $blake3EnvScript" -ForegroundColor Gray
    
    # Update Current Session
    if (Test-Path $blake3EnvScript) { . $blake3EnvScript } else {
        Write-Error "blake3 build install finished but $blake3EnvScript was not created."
        Pop-Location; return
    }
    
    if ($blake3WithMachineEnvironment)
    {
        # Generating Machine Environment wich add to the persist registry machine Environment
        $MachineEnvContent = @'
# blake3 Machine Environment Setup

# --- 0. Self-Elevation Logic ---
$IsAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$ScopeColor = "Cyan"

if (-not $IsAdmin) {
    Write-Host "Elevation required to set blake3 system variables. Relaunching as Administrator..." -ForegroundColor Yellow
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

$blake3root = "VALUE_ROOT_PATH"
$blake3bin = "VALUE_BIN_PATH"
$blake3version = "VALUE_VERSION"

$TargetScope = if ($IsAdmin) { "Machine" } else { "User" }
$RegPath = if ($IsAdmin) { "System\CurrentControlSet\Control\Session Manager\Environment" } else { "Environment" }
$RegRoot = if ($IsAdmin) { "LocalMachine" } else { "CurrentUser" }

# Open the registry key once
$RegKey = [Microsoft.Win32.Registry]::$RegRoot.OpenSubKey($RegPath, $true)

# Open the registry key directly to read the RAW (unexpanded) string
$CurrentRawPath = $RegKey.GetValue("EXTCOMPLIBS_PATH", "", [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)

# Cleanup: Remove empty strings, any path containing $blake3root, and the current target (to avoid dups)
$CleanedPathList = $CurrentRawPath -split ';' | Where-Object { 
    -not [string]::IsNullOrWhitespace($_) -and 
    $_ -notlike "*$blake3root*"
}

$NewRawPath = ($CleanedPathList -join ";").Replace(";;", ";")

$TargetPath = $blake3bin

# Rebuild
$NewRawPath = ($NewRawPath + ";" + $TargetPath + ";").Replace(";;", ";")
Write-Host "[UPDATED] ($TargetScope) '$blake3bin' synced in EXTCOMPLIBS_PATH" -ForegroundColor $ScopeColor

# Save as ExpandString
$RegKey.SetValue("EXTCOMPLIBS_PATH", $NewRawPath, [Microsoft.Win32.RegistryValueKind]::ExpandString)
$env:EXTCOMPLIBS_PATH = $NewRawPath

$RegKey.Close()

$env:BLAKE3_ROOT = $blake3root
Write-Host "blake3 Environment Loaded (Version: $blake3version) (Bin: $blake3bin)" -ForegroundColor Green
Write-Host "BLAKE3_ROOT: $env:BLAKE3_ROOT" -ForegroundColor Gray
'@  -replace "VALUE_ROOT_PATH", $blake3InstallDir `
    -replace "VALUE_BIN_PATH", $blake3BinPath `
    -replace "VALUE_VERSION", $blake3Version

        $MachineEnvContent | Out-File -FilePath $blake3MachineEnvScript -Encoding utf8
        Write-Host "Created: $blake3MachineEnvScript" -ForegroundColor Gray
        
        # --- Interaction: Prompt to apply persistent changes ---
        Write-Host ""
        $choice = Read-Host "Do you want to run the Machine Environment script now to persist blake3 changes to the Registry? (y/n)"
        if ($choice -eq 'y' -or $choice -eq 'Y') {
            Write-Host "Executing $blake3MachineEnvScript..." -ForegroundColor Yellow
            try {
                # Start the generated script. It handles its own elevation logic.
                & $blake3MachineEnvScript
            }
            catch {
                Write-Error "Failed to execute the Machine Environment script: $($_.Exception.Message)"
            }
        }
        else {
            Write-Host "Skipped persistent registry update. You can run it later at: $blake3MachineEnvScript" -ForegroundColor Gray
        }
    }
    
    # --- Return to Start ---
    Pop-Location
    Write-Host "Successfully Done! and returned to: $(Get-Location)" -ForegroundColor DarkGreen
} else {
    Write-Error "blake3.lib was not found in the $blake3LibDir folder."
    Pop-Location; return
}
