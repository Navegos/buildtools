# Copyright 2026 (C) Navegos. DevelVitorF. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
# file:x64-windows/build-libuv.ps1

param (
    [Parameter(HelpMessage = "Base workspace path", Mandatory = $false)]
    [string]$workspacePath = $null,

    [Parameter(HelpMessage = "libuv git repo url", Mandatory = $false)]
    [string]$gitUrl = "https://github.com/libuv/libuv.git",
    
    [Parameter(HelpMessage = "libuv git branch to sync from", Mandatory = $false)]
    [string]$gitBranch = "v1.x",
    
    [Parameter(HelpMessage = "Path for libuv library storage", Mandatory = $false)]
    [string]$libuvInstallDir = "$env:LIBRARIES_PATH\libuv",
    
    [Parameter(HelpMessage = "Force a full purge of the local libuv version before continuing", Mandatory = $false)]
    [switch]$forceCleanup,
    
    [Parameter(HelpMessage = "Add's libuv Machine Environment Variables. Requires Machine Administrator Rights.", Mandatory = $false)]
    [switch]$withMachineEnvironment
)

# Capture parameters
$libuvWorkspacePath = $workspacePath
$libuvGitUrl = $gitUrl
$libuvGitBranch = $gitBranch
$libuvForceCleanup = $forceCleanup
$libuvWithMachineEnvironment = $withMachineEnvironment

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

$RootPath = if ([string]::IsNullOrWhitespace($libuvWorkspacePath)) { Get-Location } else { $libuvWorkspacePath }

# --- 6. Path Resolution ---
Push-Location $RootPath

$Source         = Join-Path $RootPath "libuv"
$BuildDir       = Join-Path $Source "build_dir"
$RepoUrl        = $libuvGitUrl
$Branch         = $libuvGitBranch
$CMakeSource    = $Source
$tag_name       = $Branch
$url            = $RepoUrl

$libuvEnvScript = Join-Path $EnvironmentDir "env-libuv.ps1"
$libuvMachineEnvScript = Join-Path $EnvironmentDir "machine-env-libuv.ps1"

# --- 1. Cleanup Mechanism ---
function Invoke-libuvVersionPurge {
    param ([string]$InstallPath)
    Write-Host "--- Initiating libuv Purge ---" -ForegroundColor Cyan

    if ($libuvWithMachineEnvironment) {
        $libuvCleanMachineEnvScript = Join-Path $env:TEMP "clean-machine-env-libuv.ps1"

        # Generating Clean Machine Environment wich removes the persist registry machine Environment
        $CleanMachineEnvContent = @'
# libuv Clean Machine Environment Setup

# --- 0. Self-Elevation Logic ---
$IsAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$ScopeColor = "Cyan"

if (-not $IsAdmin) {
    Write-Host "Elevation required to clean libuv system variables. Relaunching as Administrator..." -ForegroundColor Yellow
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

$libuvroot = "VALUE_ROOT_PATH"

$TargetScope = if ($IsAdmin) { "Machine" } else { "User" }
$RegPath = if ($IsAdmin) { "System\CurrentControlSet\Control\Session Manager\Environment" } else { "Environment" }
$RegRoot = if ($IsAdmin) { "LocalMachine" } else { "CurrentUser" }

# 1. Registry Cleanup (EXTCOMPLIBS_PATH)
$RegKey = [Microsoft.Win32.Registry]::$RegRoot.OpenSubKey($RegPath, $true)

# Open the registry key directly to read the RAW (unexpanded) string
$RawPath = $RegKey.GetValue("EXTCOMPLIBS_PATH", "", [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)

# Cleanup: Remove empty strings, any path containing $libuvroot,
$CleanPath = ($RawPath -split ';' | Where-Object { $_ -notlike "*$libuvroot*" }) -join ";"

# Save as ExpandString
$RegKey.SetValue("EXTCOMPLIBS_PATH", $CleanPath, [Microsoft.Win32.RegistryValueKind]::ExpandString)
$env:EXTCOMPLIBS_PATH = $CleanPath

$RegKey.Close()

Write-Host "[REMOVED] ($TargetScope) all '*$libuvroot*' removed from EXTCOMPLIBS_PATH" -ForegroundColor $ScopeColor
'@  -replace "VALUE_ROOT_PATH", $InstallPath

        $CleanMachineEnvContent | Out-File -FilePath $libuvCleanMachineEnvScript -Encoding utf8
        Write-Host "Created: $libuvCleanMachineEnvScript" -ForegroundColor Gray
        
        # --- Interaction: Prompt to remove persistent changes ---
        Write-Host ""
        $choice = Read-Host "Administrator rights required to Clean Machine Environment libuv changes? (y/n)"
        if ($choice -eq 'y' -or $choice -eq 'Y') {
            Write-Host "Executing $libuvCleanMachineEnvScript..." -ForegroundColor Yellow
            try {
                # Start the generated script. It handles its own elevation logic.
                & $libuvCleanMachineEnvScript
            }
            catch {
                Write-Error "Failed to execute the Clean Machine Environment script: $($_.Exception.Message)"
                Pop-Location; return
            }
        }
        else {
            Write-Error "Skipped Clean Machine Environment libuv changes."
            Pop-Location; return
        }
        
        # Cleanup
        Remove-Item $libuvCleanMachineEnvScript -Recurse -Force -ErrorAction SilentlyContinue
    }

    # 2. Filesystem Clean (Requires checking for locked files)
    # delete everithing we create don't fail later
    if (Test-Path $libuvEnvScript) {
        Write-Host "  [DELETING] $libuvEnvScript" -ForegroundColor Yellow
        Remove-Item $libuvEnvScript -Recurse -Force -ErrorAction SilentlyContinue
    }
    if (Test-Path $libuvMachineEnvScript) {
        Write-Host "  [DELETING] $libuvMachineEnvScript" -ForegroundColor Yellow
        Remove-Item $libuvMachineEnvScript -Recurse -Force -ErrorAction SilentlyContinue
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
    Get-ChildItem Env:\LIBUV_PATH* | Remove-Item -ErrorAction SilentlyContinue
    Get-ChildItem Env:\LIBUV_ROOT* | Remove-Item -ErrorAction SilentlyContinue
    Get-ChildItem Env:\LIBUV_BIN* | Remove-Item -ErrorAction SilentlyContinue
    Get-ChildItem Env:\LIBUV_INCLUDE_DIR* | Remove-Item -ErrorAction SilentlyContinue
    Get-ChildItem Env:\LIBUV_LIBRARY_DIR* | Remove-Item -ErrorAction SilentlyContinue
    Get-ChildItem Env:\BINARY_LIB_LIBUV* | Remove-Item -ErrorAction SilentlyContinue
    Get-ChildItem Env:\SHARED_LIB_LIBUV* | Remove-Item -ErrorAction SilentlyContinue
    Get-ChildItem Env:\STATIC_LIB_LIBUV* | Remove-Item -ErrorAction SilentlyContinue

    Write-Host "--- LIBUV Purge Complete ---" -ForegroundColor Green
}

if ($libuvForceCleanup) {
    Invoke-libuvVersionPurge -InstallPath $libuvInstallDir
}

# --- 7. Source Management ---
if (Test-Path $Source) {
    Write-Host "Syncing libuv ($Branch) at $Source..." -ForegroundColor Cyan
    Set-Location $Source
    git fetch --all
    git reset --hard "origin/$Branch"
    git pull --recurse-submodules --force
    $tagCommit = (& git rev-parse --verify HEAD).Trim()
} else {
    Write-Host "Cloning libuv ($Branch) into $Source..." -ForegroundColor Cyan
    git clone --recurse-submodules $RepoUrl $Source -b $Branch
    Set-Location $Source
    $tagCommit = (& git rev-parse --verify HEAD).Trim()
}

# --- 8. Clean Final Destination ---
if (Test-Path $libuvInstallDir) {
    Write-Host "Wiping existing installation..." -ForegroundColor Yellow
    Remove-Item $libuvInstallDir -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "[INSTALL] Creating fresh directory: $libuvInstallDir" -ForegroundColor Cyan
New-Item -Path $libuvInstallDir -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null

# Ensure fresh build directory
if (Test-Path $BuildDir) { Remove-Item $BuildDir -Recurse -Force -ErrorAction SilentlyContinue }
New-Item -Path $BuildDir -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null

# --- 9. STAGE 2: Build Libraries ---
Write-Host "Building Libraries..." -ForegroundColor Cyan
cmake -G "Ninja" `
    -S "$CMakeSource" `
    -B "$BuildDir" `
    -DCMAKE_POLICY_DEFAULT_CMP0091=NEW `
    -DCMAKE_POLICY_DEFAULT_CMP0109=NEW `
    -DCMAKE_C_COMPILER="clang" `
    -DCMAKE_CXX_COMPILER="clang++" `
    -DCMAKE_INSTALL_PREFIX="$libuvInstallDir" `
    -DCMAKE_BUILD_TYPE=Release `
    -DLIBUV_BUILD_SHARED=ON `
    -DBUILD_TESTING=OFF `
    -DLIBUV_BUILD_TESTS=OFF `
    -DLIBUV_BUILD_BENCH=OFF `
    -DCMAKE_C_FLAGS="-Wno-deprecated-declarations -D_CRT_SECURE_NO_WARNINGS=1" `
    -DCMAKE_CXX_FLAGS="-Wno-deprecated-declarations -D_CRT_SECURE_NO_WARNINGS=1" `
    --no-warn-unused-cli
    
if ($LASTEXITCODE -ne 0) { Write-Error "libuv CMake Libraries configuration failed."; Pop-Location; return }

Write-Host "Building and Installing to $libuvInstallDir..." -ForegroundColor Green
cmake --build "$BuildDir" --target install --config Release --parallel

if ($LASTEXITCODE -ne 0) { Write-Error "libuv Build failed with exit code $LASTEXITCODE"; Pop-Location; return }

Write-Host "Successfully built and installed libuv to $libuvInstallDir!" -ForegroundColor Green

# Cleanup temporary build debris
Remove-Item $BuildDir -Recurse -Force -ErrorAction SilentlyContinue

# Generate Environment Helper with Clean Paths
$libuvInstallDir = $libuvInstallDir.TrimEnd('\')
$libuvIncludeDir = Join-Path $libuvInstallDir "include"
$libuvLibDir = Join-Path $libuvInstallDir "lib"
$libuvBinPath = Join-Path $libuvInstallDir "bin"
$libuvCMakePath = $libuvInstallDir.Replace('\', '/')

$StaticLib = Join-Path $libuvLibDir "libuv.lib"
$SharedLib = Join-Path $libuvLibDir "uv.lib"
$BinaryLib = Join-Path $libuvBinPath "uv.dll"
$versionFile = Join-Path $libuvInstallDir "version.json"

# Fallback check for "z.lib" / "zs.lib" naming convention
#if (-not (Test-Path $StaticLib)) { $StaticLib = Join-Path $libuvLibDir "libuvs.lib" }
#if (-not (Test-Path $SharedLib)) { $SharedLib = Join-Path $libuvLibDir "libuv.lib" }
#if (-not (Test-Path $BinaryLib)) { $BinaryLib = Join-Path $libuvBinPath "libuv.dll" }

if ((Test-Path $StaticLib) -or (Test-Path $SharedLib) -or (Test-Path $BinaryLib)) {
    $libuvHeader = Join-Path $libuvIncludeDir "uv\version.h"
    if (-not (Test-Path $libuvHeader)) { $libuvHeader = Join-Path $Source "uv\version.h" }
    $localVersion = "0.0.0"
    $rawVersion = $Branch
    
    if (Test-Path $libuvHeader) {
        # Extract version from #define #define UV_VERSION_MAJOR  #define UV_VERSION_MINOR #define UV_VERSION_RELEASE
        $headerContent = Get-Content $libuvHeader
        
        # Extract Major, Minor, and Release versions
        $major = ($headerContent | Select-String '#define\s+UV_VERSION_MAJOR\s+(\d+)').Matches.Groups[1].Value
        $minor = ($headerContent | Select-String '#define\s+UV_VERSION_MINOR\s+(\d+)').Matches.Groups[1].Value
        $rel = ($headerContent | Select-String '#define\s+UV_VERSION_PATCH\s+(\d+)').Matches.Groups[1].Value

        if ($major -and $minor -and $rel) {
            $localVersion = "$major.$minor.$rel"
            $rawVersion = $localVersion
            Write-Host "[VERSION] Detected libuv: $localVersion" -ForegroundColor Cyan
        }
    }
    
    # Save new version state
    $libuvVersion = $localVersion
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
    
    # --- 10. Create Environment Helper ---
    Write-Host "Generating environment helper script..." -ForegroundColor Cyan
    $EnvContent = @'
# LIBUV Environment Setup
$libuvroot = "VALUE_ROOT_PATH"
$libuvinclude = "VALUE_INCLUDE_PATH"
$libuvlibrary = "VALUE_LIB_PATH"
$libuvbin = "VALUE_BIN_PATH"
$libuvversion = "VALUE_VERSION"
$libuvbinary = "VALUE_BINARY"
$libuvshared = "VALUE_SHARED"
$libuvstatic = "VALUE_STATIC"
$libuvcmakepath = "VALUE_CMAKE_PATH"
$env:LIBUV_PATH = $libuvroot
$env:LIBUV_ROOT = $libuvroot
$env:LIBUV_BIN = $libuvbin
$env:LIBUV_INCLUDE_DIR = $libuvinclude
$env:LIBUV_LIBRARY_DIR = $libuvlibrary
$env:BINARY_LIB_LIBUV = $libuvbinary
$env:SHARED_LIB_LIBUV = $libuvshared
$env:STATIC_LIB_LIBUV = $libuvstatic
if ($env:CMAKE_PREFIX_PATH -notlike "*$libuvcmakepath*") { $env:CMAKE_PREFIX_PATH = $libuvcmakepath + ";" + $env:CMAKE_PREFIX_PATH; $env:CMAKE_PREFIX_PATH = ($env:CMAKE_PREFIX_PATH).Replace(";;", ";") }
if ($env:INCLUDE -notlike "*$libuvinclude*") { $env:INCLUDE = $libuvinclude + ";" + $env:INCLUDE; $env:INCLUDE = ($env:INCLUDE).Replace(";;", ";") }
if ($env:LIB -notlike "*$libuvlibrary*") { $env:LIB = $libuvlibrary + ";" + $env:LIB; $env:LIB = ($env:LIB).Replace(";;", ";") }
if ($env:PATH -notlike "*$libuvbin*") { $env:PATH = $libuvbin + ";" + $env:PATH; $env:PATH = ($env:PATH).Replace(";;", ";") }
Write-Host "libuv Environment Loaded (Version: $libuvversion) (Bin: $libuvbin)" -ForegroundColor Green
Write-Host "LIBUV_ROOT: $env:LIBUV_ROOT" -ForegroundColor Gray
'@  -replace "VALUE_ROOT_PATH", $libuvInstallDir `
    -replace "VALUE_INCLUDE_PATH", $libuvIncludeDir `
    -replace "VALUE_LIB_PATH", $libuvLibDir `
    -replace "VALUE_BIN_PATH", $libuvBinPath `
    -replace "VALUE_VERSION", $libuvVersion `
    -replace "VALUE_SHARED", $SharedLib `
    -replace "VALUE_BINARY", $BinaryLib `
    -replace "VALUE_STATIC", $StaticLib `
    -replace "VALUE_CMAKE_PATH", $libuvCMakePath

    $EnvContent | Out-File -FilePath $libuvEnvScript -Encoding utf8
    Write-Host "Created: $libuvEnvScript" -ForegroundColor Gray
    
    # Update Current Session
    if (Test-Path $libuvEnvScript) { . $libuvEnvScript } else {
        Write-Error "libuv build install finished but $libuvEnvScript was not created."
        Pop-Location; return
    }
    
    if ($libuvWithMachineEnvironment)
    {
        # Generating Machine Environment wich add to the persist registry machine Environment
        $MachineEnvContent = @'
# libuv Machine Environment Setup

# --- 0. Self-Elevation Logic ---
$IsAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$ScopeColor = "Cyan"

if (-not $IsAdmin) {
    Write-Host "Elevation required to set libuv system variables. Relaunching as Administrator..." -ForegroundColor Yellow
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

$libuvroot = "VALUE_ROOT_PATH"
$libuvbin = "VALUE_BIN_PATH"
$libuvversion = "VALUE_VERSION"

$TargetScope = if ($IsAdmin) { "Machine" } else { "User" }
$RegPath = if ($IsAdmin) { "System\CurrentControlSet\Control\Session Manager\Environment" } else { "Environment" }
$RegRoot = if ($IsAdmin) { "LocalMachine" } else { "CurrentUser" }

# Open the registry key once
$RegKey = [Microsoft.Win32.Registry]::$RegRoot.OpenSubKey($RegPath, $true)

# Open the registry key directly to read the RAW (unexpanded) string
$CurrentRawPath = $RegKey.GetValue("EXTCOMPLIBS_PATH", "", [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)

# Cleanup: Remove empty strings, any path containing $libuvroot, and the current target (to avoid dups)
$CleanedPathList = $CurrentRawPath -split ';' | Where-Object { 
    -not [string]::IsNullOrWhitespace($_) -and 
    $_ -notlike "*$libuvroot*"
}

$NewRawPath = ($CleanedPathList -join ";").Replace(";;", ";")

$TargetPath = $libuvbin

# Rebuild
$NewRawPath = ($NewRawPath + ";" + $TargetPath + ";").Replace(";;", ";")
Write-Host "[UPDATED] ($TargetScope) '$libuvbin' synced in EXTCOMPLIBS_PATH" -ForegroundColor $ScopeColor

# Save as ExpandString
$RegKey.SetValue("EXTCOMPLIBS_PATH", $NewRawPath, [Microsoft.Win32.RegistryValueKind]::ExpandString)
$env:EXTCOMPLIBS_PATH = $NewRawPath

$RegKey.Close()

$env:LIBUV_ROOT = $libuvroot
Write-Host "libuv Environment Loaded (Version: $libuvversion) (Bin: $libuvbin)" -ForegroundColor Green
Write-Host "LIBUV_ROOT: $env:LIBUV_ROOT" -ForegroundColor Gray
'@  -replace "VALUE_ROOT_PATH", $libuvInstallDir `
    -replace "VALUE_BIN_PATH", $libuvBinPath `
    -replace "VALUE_VERSION", $libuvVersion

        $MachineEnvContent | Out-File -FilePath $libuvMachineEnvScript -Encoding utf8
        Write-Host "Created: $libuvMachineEnvScript" -ForegroundColor Gray
        
        # --- Interaction: Prompt to apply persistent changes ---
        Write-Host ""
        $choice = Read-Host "Do you want to run the Machine Environment script now to persist libuv changes to the Registry? (y/n)"
        if ($choice -eq 'y' -or $choice -eq 'Y') {
            Write-Host "Executing $libuvMachineEnvScript..." -ForegroundColor Yellow
            try {
                # Start the generated script. It handles its own elevation logic.
                & $libuvMachineEnvScript
            }
            catch {
                Write-Error "Failed to execute the Machine Environment script: $($_.Exception.Message)"
            }
        }
        else {
            Write-Host "Skipped persistent registry update. You can run it later at: $libuvMachineEnvScript" -ForegroundColor Gray
        }
    }
    
    # --- Return to Start ---
    Pop-Location
    Write-Host "Successfully Done! and returned to: $(Get-Location)" -ForegroundColor DarkGreen
} else {
    Write-Error "libuv.lib was not found in the $libuvLibDir folder."
    Pop-Location; return
}
