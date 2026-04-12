# Copyright 2026 (C) Navegos. DevelVitorF. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
# file:x64-windows/build-lzma.ps1

param (
    [Parameter(HelpMessage = "Base workspace path", Mandatory = $false)]
    [string]$workspacePath = $null,

    [Parameter(HelpMessage = "lzma (xz) git repo url", Mandatory = $false)]
    [string]$gitUrl = "https://github.com/tukaani-project/xz.git",
    
    [Parameter(HelpMessage = "lzma git branch to sync from", Mandatory = $false)]
    [string]$gitBranch = "master",

    [Parameter(HelpMessage = "Path for lzma library storage", Mandatory = $false)]
    [string]$lzmaInstallDir = "$env:LIBRARIES_PATH\lzma",
    
    [Parameter(HelpMessage = "Force a full purge of the local lzma version before continuing", Mandatory = $false)]
    [switch]$forceCleanup,
    
    [Parameter(HelpMessage = "Add's lzma Machine Environment Variables. Requires Machine Administrator Rights.", Mandatory = $false)]
    [switch]$withMachineEnvironment
)

# Capture parameters
$lzmaWorkspacePath = $workspacePath
$lzmaGitUrl = $gitUrl
$lzmaGitBranch = $gitBranch
$lzmaForceCleanup = $forceCleanup
$lzmaWithMachineEnvironment = $withMachineEnvironment

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

$RootPath = if ([string]::IsNullOrWhitespace($lzmaWorkspacePath)) { Get-Location } else { $lzmaWorkspacePath }

# --- 6. Path Resolution ---
Push-Location $RootPath

$Source         = Join-Path $RootPath "lzma"
$BuildDirShared = Join-Path $Source "build_shared"
$BuildDirStatic = Join-Path $Source "build_static"
$RepoUrl        = $lzmaGitUrl
$Branch         = $lzmaGitBranch
$CMakeSource    = $Source
$tag_name       = $Branch
$url            = $RepoUrl

$lzmaMachineEnvScript = Join-Path $EnvironmentDir "machine-env-lzma.ps1"
$lzmaEnvScript = Join-Path $EnvironmentDir "env-lzma.ps1"

# --- 1. Cleanup Mechanism ---
function Invoke-lzmaVersionPurge {
    param ([string]$InstallPath)
    Write-Host "--- Initiating lzma Purge ---" -ForegroundColor Cyan

    if ($lzmaWithMachineEnvironment)
    {
        $lzmaCleanMachineEnvScript = Join-Path $env:TEMP "clean-machine-env-lzma.ps1"

        # Generating Clean Machine Environment wich removes the persist registry machine Environment
        $CleanMachineEnvContent = @'
# lzma Clean Machine Environment Setup

# --- 0. Self-Elevation Logic ---
$IsAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$ScopeColor = "Cyan"

if (-not $IsAdmin) {
    Write-Host "Elevation required to clean lzma system variables. Relaunching as Administrator..." -ForegroundColor Yellow
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

$lzmaroot = "VALUE_ROOT_PATH"

$TargetScope = if ($IsAdmin) { "Machine" } else { "User" }
$RegPath = if ($IsAdmin) { "System\CurrentControlSet\Control\Session Manager\Environment" } else { "Environment" }
$RegRoot = if ($IsAdmin) { "LocalMachine" } else { "CurrentUser" }

# 1. Registry Cleanup (EXTCOMPLIBS_PATH)
$RegKey = [Microsoft.Win32.Registry]::$RegRoot.OpenSubKey($RegPath, $true)

# Open the registry key directly to read the RAW (unexpanded) string
$RawPath = $RegKey.GetValue("EXTCOMPLIBS_PATH", "", [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)

# Cleanup: Remove empty strings, any path containing $lzmaroot,
$CleanPath = ($RawPath -split ';' | Where-Object { $_ -notlike "*$lzmaroot*" }) -join ";"

# Save as ExpandString
$RegKey.SetValue("EXTCOMPLIBS_PATH", $CleanPath, [Microsoft.Win32.RegistryValueKind]::ExpandString)
$env:EXTCOMPLIBS_PATH = $CleanPath

$RegKey.Close()

Write-Host "[REMOVED] ($TargetScope) all '*$lzmaroot*' removed from EXTCOMPLIBS_PATH" -ForegroundColor $ScopeColor
'@  -replace "VALUE_ROOT_PATH", $InstallPath

        $CleanMachineEnvContent | Out-File -FilePath $lzmaCleanMachineEnvScript -Encoding utf8
        Write-Host "Created: $lzmaCleanMachineEnvScript" -ForegroundColor Gray
        
        # --- Interaction: Prompt to remove persistent changes ---
        Write-Host ""
        $choice = Read-Host "Administrator rights required to Clean Machine Environment lzma changes? (y/n)"
        if ($choice -eq 'y' -or $choice -eq 'Y') {
            Write-Host "Executing $lzmaCleanMachineEnvScript..." -ForegroundColor Yellow
            try {
                # Start the generated script. It handles its own elevation logic.
                & $lzmaCleanMachineEnvScript
            }
            catch {
                Write-Error "Failed to execute the Clean Machine Environment script: $($_.Exception.Message)"
                Pop-Location; return
            }
        }
        else {
            Write-Error "Skipped Clean Machine Environment lzma changes."
            Pop-Location; return
        }

        # Cleanup
        Remove-Item $lzmaCleanMachineEnvScript -Recurse -Force -ErrorAction SilentlyContinue
    }

    # 2. Filesystem Clean (Requires checking for locked files)
    # delete everithing we create don't fail later
    if (Test-Path $lzmaEnvScript) {
        Write-Host "  [DELETING] $lzmaEnvScript" -ForegroundColor Yellow
        Remove-Item $lzmaEnvScript -Recurse -Force -ErrorAction SilentlyContinue
    }
    if (Test-Path $lzmaMachineEnvScript) {
        Write-Host "  [DELETING] $lzmaMachineEnvScript" -ForegroundColor Yellow
        Remove-Item $lzmaMachineEnvScript -Recurse -Force -ErrorAction SilentlyContinue
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
    Get-ChildItem Env:\LZMA_PATH* | Remove-Item -ErrorAction SilentlyContinue
    Get-ChildItem Env:\LZMA_ROOT* | Remove-Item -ErrorAction SilentlyContinue
    Get-ChildItem Env:\LZMA_BIN* | Remove-Item -ErrorAction SilentlyContinue
    Get-ChildItem Env:\LZMA_INCLUDE_DIR* | Remove-Item -ErrorAction SilentlyContinue
    Get-ChildItem Env:\LZMA_LIBRARY_DIR* | Remove-Item -ErrorAction SilentlyContinue
    Get-ChildItem Env:\BINARY_LIB_LZMA* | Remove-Item -ErrorAction SilentlyContinue
    Get-ChildItem Env:\SHARED_LIB_LZMA* | Remove-Item -ErrorAction SilentlyContinue
    Get-ChildItem Env:\STATIC_LIB_LZMA* | Remove-Item -ErrorAction SilentlyContinue

    Write-Host "--- LZMA Purge Complete ---" -ForegroundColor Green
}

if ($lzmaForceCleanup) {
    Invoke-lzmaVersionPurge -InstallPath $lzmaInstallDir
}

# --- 7. Source Management ---
if (Test-Path $Source) {
    Write-Host "Syncing LZMA ($Branch) at $Source..." -ForegroundColor Cyan
    Set-Location $Source
    git fetch --all
    git reset --hard "origin/$Branch"
    git pull --recurse-submodules --force
    $tagCommit = (& git rev-parse --verify HEAD).Trim()
} else {
    Write-Host "Cloning LZMA ($Branch) into $Source..." -ForegroundColor Cyan
    git clone --recurse-submodules $RepoUrl $Source -b $Branch
    Set-Location $Source
    $tagCommit = (& git rev-parse --verify HEAD).Trim()
}

# --- Apply Patch some symbols are not exported and build fails linking shared lib ---
$PatchFile = Join-Path $PSScriptRoot "patch\lzma_cmake.patch"
if (Test-Path $PatchFile) {
    Write-Host "[PATCH] Verifying custom CMake modifications..." -ForegroundColor Cyan
    
    # 1. Perform a Dry-Run (--check)
    # --ignore-space-change handles the Windows/Linux line-ending (CRLF/LF) headaches
    git apply --check --ignore-space-change "$PatchFile"
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "[PATCH] Verification successful. Applying patch..." -ForegroundColor Green
        
        # 2. Actually apply the patch
        git apply --ignore-space-change --verbose "$PatchFile"
        
        if ($LASTEXITCODE -ne 0) {
            Write-Error "CRITICAL: Patch verification passed but application failed!"
            Pop-Location; return
        }
    } else {
        # The check failed, which usually means the repo has changed 
        # or the patch was already partially applied (unlikely after git reset --hard)
        Write-Warning "[PATCH] Patch verification failed. The source may have changed upstream."
        Write-Host "Check the patch file for conflicts or update the patch." -ForegroundColor Yellow
        
        # In a strict build-chain, you might want to stop here:
        Pop-Location; return
    }
}

# --- 8. Clean Final Destination ---
if (Test-Path $lzmaInstallDir) {
    Write-Host "Wiping existing installation..." -ForegroundColor Yellow
    Remove-Item $lzmaInstallDir -Recurse -Force -ErrorAction SilentlyContinue
}
New-Item -Path $lzmaInstallDir -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null

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
    "-DXZ_DOC=OFF",
    "-DXZ_TOOL_XZDEC=OFF",
    "-DXZ_TOOL_LZMADEC=OFF",
    "-DXZ_TOOL_LZMAINFO=OFF",
    "-DXZ_TOOL_XZ=OFF",
    "-DBUILD_TESTING=OFF"
)

# --- 9. STAGE 1: Build Static Libraries ---
Write-Host "Building LZMA Static (lzmas.lib)..." -ForegroundColor Cyan
cmake $CommonCmakeArgs `
    -S "$CMakeSource" `
    -B "$BuildDirStatic" `
    -DCMAKE_INSTALL_PREFIX="$lzmaInstallDir" `
    -DBUILD_SHARED_LIBS=OFF `
    -DXZ_THREADS="vista" `
    -DCMAKE_C_FLAGS="-Wno-deprecated-declarations -D_CRT_SECURE_NO_WARNINGS=1" `
    -DCMAKE_CXX_FLAGS="-Wno-deprecated-declarations -D_CRT_SECURE_NO_WARNINGS=1" `
    --no-warn-unused-cli

if ($LASTEXITCODE -ne 0) { Write-Error "lzma CMake Static (lzmas.lib) configuration failed."; Pop-Location; return }

Write-Host "Building and Installing static lib to $lzmaInstallDir..." -ForegroundColor Green
cmake --build "$BuildDirStatic" --target install --config Release --parallel

if ($LASTEXITCODE -ne 0) { Write-Error "lzma Static Build failed with exit code $LASTEXITCODE"; Pop-Location; return }

# Rename static lib to lzmas.lib to avoid collision
$StaticLibPath = Join-Path $lzmaInstallDir "lib/lzma.lib"
$NewStaticName = Join-Path $lzmaInstallDir "lib/lzmas.lib"
if (Test-Path $StaticLibPath) {
    Move-Item -Path $StaticLibPath -Destination $NewStaticName -Force -ErrorAction SilentlyContinue
    Write-Host "Static library renamed to lzmas.lib" -ForegroundColor Gray
}

# --- 10. STAGE 2: Build Shared Libraries ---
Write-Host "Building LZMA Shared (DLL)..." -ForegroundColor Cyan
cmake $CommonCmakeArgs `
    -S "$CMakeSource" `
    -B "$BuildDirShared" `
    -DCMAKE_INSTALL_PREFIX="$lzmaInstallDir" `
    -DBUILD_SHARED_LIBS=ON `
    -DXZ_THREADS="vista" `
    -DCMAKE_C_FLAGS="-Wno-deprecated-declarations -D_CRT_SECURE_NO_WARNINGS=1" `
    -DCMAKE_CXX_FLAGS="-Wno-deprecated-declarations -D_CRT_SECURE_NO_WARNINGS=1" `
    --no-warn-unused-cli

if ($LASTEXITCODE -ne 0) { Write-Error "lzma CMake Shared (DLL) configuration failed."; Pop-Location; return }

Write-Host "Building and Installing dynamic lib to $lzmaInstallDir..." -ForegroundColor Green
cmake --build "$BuildDirShared" --target install --config Release --parallel

if ($LASTEXITCODE -ne 0) { Write-Error "lzma Shared Build failed with exit code $LASTEXITCODE"; Pop-Location; return }

Write-Host "Successfully built and installed lzma to $lzmaInstallDir!" -ForegroundColor Green

# Cleanup temporary build debris
Remove-Item $BuildDirShared -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item $BuildDirStatic -Recurse -Force -ErrorAction SilentlyContinue

# Generate Environment Helper with Clean Paths
$lzmaInstallDir = $lzmaInstallDir.TrimEnd('\')
$lzmaIncludeDir = Join-Path $lzmaInstallDir "include"
$lzmaLibDir = Join-Path $lzmaInstallDir "lib"
$lzmaBinPath = Join-Path $lzmaInstallDir "bin"
$lzmaCMakePath = $lzmaInstallDir.Replace('\', '/')

$StaticLib = Join-Path $lzmaLibDir "lzmastatic.lib"
$SharedLib = Join-Path $lzmaLibDir "lzma.lib"
$BinaryLib = Join-Path $lzmaBinPath "lzma.dll"
$versionFile = Join-Path $lzmaInstallDir "version.json"

# Fallback check for "z.lib" / "zs.lib" naming convention
if (-not (Test-Path $StaticLib)) { $StaticLib = Join-Path $lzmaLibDir "lzmas.lib" }
#if (-not (Test-Path $SharedLib)) { $SharedLib = Join-Path $lzmaLibDir "lzma.lib" }
if (-not (Test-Path $BinaryLib)) { $BinaryLib = Join-Path $lzmaBinPath "liblzma.dll" }

if ((Test-Path $StaticLib) -or (Test-Path $SharedLib) -or (Test-Path $BinaryLib)) {
    $lzmaHeader = Join-Path $lzmaIncludeDir "lzma\version.h"
    if (-not (Test-Path $lzmaHeader)) { $lzmaHeader = Join-Path $Source "src\liblzma\api\lzma\version.h" }
    $localVersion = "0.0.0"
    $rawVersion = $Branch
    
    if (Test-Path $lzmaHeader) {
        # Extract version from #define #define LZMA_VERSION_MAJOR  #define LZMA_VERSION_MINOR #define LZMA_VERSION_PATCH
        $headerContent = Get-Content $lzmaHeader
        
        # Extract Major, Minor, and Release versions
        $major = ($headerContent | Select-String '#define\s+LZMA_VERSION_MAJOR\s+(\d+)').Matches.Groups[1].Value
        $minor = ($headerContent | Select-String '#define\s+LZMA_VERSION_MINOR\s+(\d+)').Matches.Groups[1].Value
        $rel = ($headerContent | Select-String '#define\s+LZMA_VERSION_PATCH\s+(\d+)').Matches.Groups[1].Value

        if ($major -and $minor -and $rel) {
            $localVersion = "$major.$minor.$rel"
            $rawVersion = $localVersion
            Write-Host "[VERSION] Detected lzma: $localVersion" -ForegroundColor Cyan
        }
    }
    
    # Save new version state
    $lzmaVersion = $localVersion
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
# LZMA Environment Setup
$lzmaroot = "VALUE_ROOT_PATH"
$lzmainclude = "VALUE_INCLUDE_PATH"
$lzmalibrary = "VALUE_LIB_PATH"
$lzmabin = "VALUE_BIN_PATH"
$lzmaversion = "VALUE_VERSION"
$lzmabinary = "VALUE_BINARY"
$lzmashared = "VALUE_SHARED"
$lzmastatic = "VALUE_STATIC"
$lzmacmakepath = "VALUE_CMAKE_PATH"
$env:LZMA_PATH = $lzmaroot
$env:LZMA_ROOT = $lzmaroot
$env:LZMA_BIN = $lzmabin
$env:LZMA_INCLUDE_DIR = $lzmainclude
$env:LZMA_LIBRARY_DIR = $lzmalibrary
$env:BINARY_LIB_LZMA = $lzmabinary
$env:SHARED_LIB_LZMA = $lzmashared
$env:STATIC_LIB_LZMA = $lzmastatic
if ($env:CMAKE_PREFIX_PATH -notlike "*$lzmacmakepath*") { $env:CMAKE_PREFIX_PATH = $lzmacmakepath + ";" + $env:CMAKE_PREFIX_PATH; $env:CMAKE_PREFIX_PATH = ($env:CMAKE_PREFIX_PATH).Replace(";;", ";") }
if ($env:INCLUDE -notlike "*$lzmainclude*") { $env:INCLUDE = $lzmainclude + ";" + $env:INCLUDE; $env:INCLUDE = ($env:INCLUDE).Replace(";;", ";") }
if ($env:LIB -notlike "*$lzmalibrary*") { $env:LIB = $lzmalibrary + ";" + $env:LIB; $env:LIB = ($env:LIB).Replace(";;", ";") }
if ($env:PATH -notlike "*$lzmabin*") { $env:PATH = $lzmabin + ";" + $env:PATH; $env:PATH = ($env:PATH).Replace(";;", ";") }
Write-Host "lzma Environment Loaded (Version: $lzmaversion) (Bin: $lzmabin)" -ForegroundColor Green
Write-Host "LZMA_ROOT: $env:LZMA_ROOT" -ForegroundColor Gray
'@  -replace "VALUE_ROOT_PATH", $lzmaInstallDir `
    -replace "VALUE_INCLUDE_PATH", $lzmaIncludeDir `
    -replace "VALUE_LIB_PATH", $lzmaLibDir `
    -replace "VALUE_BIN_PATH", $lzmaBinPath `
    -replace "VALUE_VERSION", $lzmaVersion `
    -replace "VALUE_SHARED", $SharedLib `
    -replace "VALUE_BINARY", $BinaryLib `
    -replace "VALUE_STATIC", $StaticLib `
    -replace "VALUE_CMAKE_PATH", $lzmaCMakePath

    $EnvContent | Out-File -FilePath $lzmaEnvScript -Encoding utf8
    Write-Host "Created: $lzmaEnvScript" -ForegroundColor Gray
    
    # Update Current Session
    if (Test-Path $lzmaEnvScript) { . $lzmaEnvScript } else {
        Write-Error "lzma build install finished but $lzmaEnvScript was not created."
        Pop-Location; return
    }
    
    if ($lzmaWithMachineEnvironment)
    {
        # Generating Machine Environment wich add to the persist registry machine Environment
        $MachineEnvContent = @'
# lzma Machine Environment Setup

# --- 0. Self-Elevation Logic ---
$IsAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$ScopeColor = "Cyan"

if (-not $IsAdmin) {
    Write-Host "Elevation required to set lzma system variables. Relaunching as Administrator..." -ForegroundColor Yellow
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

$lzmaroot = "VALUE_ROOT_PATH"
$lzmabin = "VALUE_BIN_PATH"
$lzmaversion = "VALUE_VERSION"

$TargetScope = if ($IsAdmin) { "Machine" } else { "User" }
$RegPath = if ($IsAdmin) { "System\CurrentControlSet\Control\Session Manager\Environment" } else { "Environment" }
$RegRoot = if ($IsAdmin) { "LocalMachine" } else { "CurrentUser" }

# Open the registry key once
$RegKey = [Microsoft.Win32.Registry]::$RegRoot.OpenSubKey($RegPath, $true)

# Open the registry key directly to read the RAW (unexpanded) string
$CurrentRawPath = $RegKey.GetValue("EXTCOMPLIBS_PATH", "", [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)

# Cleanup: Remove empty strings, any path containing $lzmaroot, and the current target (to avoid dups)
$CleanedPathList = $CurrentRawPath -split ';' | Where-Object { 
    -not [string]::IsNullOrWhitespace($_) -and 
    $_ -notlike "*$lzmaroot*"
}

$NewRawPath = ($CleanedPathList -join ";").Replace(";;", ";")

$TargetPath = $lzmabin

# Rebuild
$NewRawPath = ($NewRawPath + ";" + $TargetPath + ";").Replace(";;", ";")
Write-Host "[UPDATED] ($TargetScope) '$lzmabin' synced in EXTCOMPLIBS_PATH" -ForegroundColor $ScopeColor

# Save as ExpandString
$RegKey.SetValue("EXTCOMPLIBS_PATH", $NewRawPath, [Microsoft.Win32.RegistryValueKind]::ExpandString)
$env:EXTCOMPLIBS_PATH = $NewRawPath

$RegKey.Close()

$env:LZMA_ROOT = $lzmaroot
Write-Host "lzma Environment Loaded (Version: $lzmaversion) (Bin: $lzmabin)" -ForegroundColor Green
Write-Host "LZMA_ROOT: $env:LZMA_ROOT" -ForegroundColor Gray
'@  -replace "VALUE_ROOT_PATH", $lzmaInstallDir `
    -replace "VALUE_BIN_PATH", $lzmaBinPath `
    -replace "VALUE_VERSION", $lzmaVersion

        $MachineEnvContent | Out-File -FilePath $lzmaMachineEnvScript -Encoding utf8
        Write-Host "Created: $lzmaMachineEnvScript" -ForegroundColor Gray
        
        # --- Interaction: Prompt to apply persistent changes ---
        Write-Host ""
        $choice = Read-Host "Do you want to run the Machine Environment script now to persist lzma changes to the Registry? (y/n)"
        if ($choice -eq 'y' -or $choice -eq 'Y') {
            Write-Host "Executing $lzmaMachineEnvScript..." -ForegroundColor Yellow
            try {
                # Start the generated script. It handles its own elevation logic.
                & $lzmaMachineEnvScript
            }
            catch {
                Write-Error "Failed to execute the Machine Environment script: $($_.Exception.Message)"
            }
        }
        else {
            Write-Host "Skipped persistent registry update. You can run it later at: $lzmaMachineEnvScript" -ForegroundColor Gray
        }
    }
    
    # --- Return to Start ---
    Pop-Location
    Write-Host "Successfully Done! and returned to: $(Get-Location)" -ForegroundColor DarkGreen
} else {
    Write-Error "lzma.lib was not found in the $lzmaLibDir folder."
    Pop-Location; return
}
