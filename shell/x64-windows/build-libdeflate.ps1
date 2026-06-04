# SPDX-FileCopyrightText: Copyright (c) 2026 Navegos. @DevelVitorF. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
# project: buildtools
# file: x64-windows/build-libdeflate.ps1
# created: 2026-05-03
# lastModified: 2026-05-13

param (
    [Parameter(HelpMessage = "Base workspace path", Mandatory = $false)]
    [string]$workspacePath = $null,

    [Parameter(HelpMessage = "libdeflate git repo url", Mandatory = $false)]
    [string]$gitUrl = "https://github.com/ebiggers/libdeflate.git",
    
    [Parameter(HelpMessage = "libdeflate git branch to sync from", Mandatory = $false)]
    [string]$gitBranch = "master",

    [Parameter(HelpMessage = "Path for libdeflate library storage", Mandatory = $false)]
    [string]$libdeflateInstallDir = "$env:LIBRARIES_PATH\libdeflate",
    
    [Parameter(HelpMessage = "Lib name, if it's building with a different name", Mandatory = $false)]
    [string]$libdeflateLibName = "deflate",
    
    [Parameter(HelpMessage = "Force a full purge of the local libdeflate version before continuing", Mandatory = $false)]
    [switch]$forceCleanup,
    
    [Parameter(HelpMessage = "Add's libdeflate Machine Environment Variables.", Mandatory = $false)]
    [switch]$withMachineEnvironment,

    [Parameter(ValueFromRemainingArguments = $true)]
    $RemainingArgs
)

$libdeflateWorkspacePath = $workspacePath
$libdeflateGitUrl = $gitUrl
$libdeflateGitBranch = $gitBranch
$libdeflateForceCleanup = $forceCleanup
$libdeflateWithMachineEnvironment = $withMachineEnvironment

# 1. Bootstrap Environment if variables are missing
if ([string]::IsNullOrWhitespace($env:ENVIRONMENT_PATH) -or -not (Test-Path $env:ENVIRONMENT_PATH) -or [string]::IsNullOrWhitespace($env:BINARIES_PATH) -or -not (Test-Path $env:BINARIES_PATH) -or [string]::IsNullOrWhitespace($env:LIBRARIES_PATH) -or -not (Test-Path $env:LIBRARIES_PATH) -or [string]::IsNullOrWhitespace($env:BUILDTOOLS_PATH) -or -not (Test-Path $env:BUILDTOOLS_PATH)) {
    Write-Error "User Environment variables missing. Please run add-user-paths.ps1 -LibrariesDir 'Path/for/Libraries' -BinariesDir 'Path/for/Binaries' -EnvironmentDir 'Path/for/Environment' -BuildToolsDir 'Path/for/BuildTools'"
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

# --- Dependencies: ---
#$RootlibdeflateInstallDir = Split-Path -Path $libdeflateInstallDir -Parent
$RootlibdeflateWorkspacePath = if ([string]::IsNullOrWhitespace($libdeflateWorkspacePath)) { Get-Location } else { $libdeflateWorkspacePath }
$RootPath = if ([string]::IsNullOrWhitespace($RootlibdeflateWorkspacePath)) { Get-Location } else { $RootlibdeflateWorkspacePath }

# --- 6. Path Resolution ---
Push-Location $RootPath

$Source         = Join-Path $RootPath "libdeflate"
$BuildDirShared = Join-Path $Source "build_shared"
$BuildDirStatic = Join-Path $Source "build_static"
$RepoUrl        = $libdeflateGitUrl
$Branch         = $libdeflateGitBranch
$CMakeSource    = $Source
$tag_name       = $Branch
$url            = $RepoUrl

$libdeflateEnvScript = Join-Path $EnvironmentDir "env-libdeflate.ps1"
$libdeflateMachineEnvScript = Join-Path $EnvironmentDir "machine-env-libdeflate.ps1"

# --- 1. Cleanup Mechanism ---
function Invoke-libdeflateVersionPurge {
    param ([string]$InstallPath)
    Write-Host "--- Initiating libdeflate Purge ---" -ForegroundColor Cyan

    if ($libdeflateWithMachineEnvironment) {
        $libdeflateCleanMachineEnvScript = Join-Path $env:TEMP "clean-machine-env-libdeflate.ps1"

        # Generating Clean Machine Environment wich removes the persist registry machine Environment
        $CleanMachineEnvContent = @'
# libdeflate Clean Machine Environment Setup

# --- 0. Self-Elevation Logic ---
$IsAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$ScopeColor = "Cyan"

if (-not $IsAdmin) {
    Write-Host "Elevation required to clean libdeflate system variables. Relaunching as Administrator..." -ForegroundColor Yellow
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

$libdeflateroot = "VALUE_ROOT_PATH"

$TargetScope = if ($IsAdmin) { "Machine" } else { "User" }
$RegPath = if ($IsAdmin) { "System\CurrentControlSet\Control\Session Manager\Environment" } else { "Environment" }
$RegRoot = if ($IsAdmin) { "LocalMachine" } else { "CurrentUser" }

# 1. Registry Cleanup (EXTCOMPLIBS_PATH)
$RegKey = [Microsoft.Win32.Registry]::$RegRoot.OpenSubKey($RegPath, $true)

# Open the registry key directly to read the RAW (unexpanded) string
$RawPath = $RegKey.GetValue("EXTCOMPLIBS_PATH", "", [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)

# Cleanup: Remove empty strings, any path containing $libdeflateroot,
$CleanPath = ($RawPath -split ';' | Where-Object { $_ -notlike "*$libdeflateroot*" }) -join ";"

# Save as ExpandString
$RegKey.SetValue("EXTCOMPLIBS_PATH", $CleanPath, [Microsoft.Win32.RegistryValueKind]::ExpandString)
$env:EXTCOMPLIBS_PATH = $CleanPath

$RegKey.Close()

Write-Host "[REMOVED] ($TargetScope) all '*$libdeflateroot*' removed from EXTCOMPLIBS_PATH" -ForegroundColor $ScopeColor
'@  -replace "VALUE_ROOT_PATH", $InstallPath

        $CleanMachineEnvContent | Out-File -FilePath $libdeflateCleanMachineEnvScript -Encoding utf8
        Write-Host "Created: $libdeflateCleanMachineEnvScript" -ForegroundColor Gray
        
        # --- Interaction: Prompt to remove persistent changes ---
        Write-Host ""
        $choice = Read-Host "Administrator rights required to Clean Machine Environment libdeflate changes? (y/n)"
        if ($choice -eq 'y' -or $choice -eq 'Y') {
            Write-Host "Executing $libdeflateCleanMachineEnvScript..." -ForegroundColor Yellow
            try {
                # Start the generated script. It handles its own elevation logic.
                & $libdeflateCleanMachineEnvScript
            }
            catch {
                Write-Error "Failed to execute the Clean Machine Environment script: $($_.Exception.Message)"
                Pop-Location; return
            }
        }
        else {
            Write-Error "Skipped Clean Machine Environment libdeflate changes."
            Pop-Location; return
        }

        # Cleanup
        Remove-Item $libdeflateCleanMachineEnvScript -Recurse -Force -ErrorAction SilentlyContinue
    }

    # 2. Filesystem Clean (Requires checking for locked files)
    # delete everithing we create don't fail later
    if (Test-Path $libdeflateEnvScript) {
        Write-Host "  [DELETING] $libdeflateEnvScript" -ForegroundColor Yellow
        Remove-Item $libdeflateEnvScript -Recurse -Force -ErrorAction SilentlyContinue
    }
    if (Test-Path $libdeflateMachineEnvScript) {
        Write-Host "  [DELETING] $libdeflateMachineEnvScript" -ForegroundColor Yellow
        Remove-Item $libdeflateMachineEnvScript -Recurse -Force -ErrorAction SilentlyContinue
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
    Get-ChildItem Env:\LIBDEFLATE_* | ForEach-Object { Remove-Item Env:\$($_.Name) -ErrorAction SilentlyContinue }
    Get-ChildItem Env:\BINARY_LIB_DEFLATE* | ForEach-Object { Remove-Item Env:\$($_.Name) -ErrorAction SilentlyContinue }
    Get-ChildItem Env:\SHARED_LIB_DEFLATE* | ForEach-Object { Remove-Item Env:\$($_.Name) -ErrorAction SilentlyContinue }
    Get-ChildItem Env:\STATIC_LIB_DEFLATE* | ForEach-Object { Remove-Item Env:\$($_.Name) -ErrorAction SilentlyContinue }
    
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
    
    Write-Host "--- LIBDEFLATE Purge Complete ---" -ForegroundColor Green
}

if ($libdeflateForceCleanup) {
    Invoke-libdeflateVersionPurge -InstallPath $libdeflateInstallDir
}

if (Test-Path $Source) {
    Write-Host "Syncing libdeflate ($Branch) at $Source..." -ForegroundColor Cyan
    Set-Location $Source
    git fetch --all
    if ($LASTEXITCODE -ne 0) { Write-Error "Git fetch failed."; Pop-Location; return }
    git reset --hard "origin/$Branch"
    git clean -xdf
    git pull --recurse-submodules --force
    if ($LASTEXITCODE -ne 0) { Write-Error "Git pull failed."; Pop-Location; return }
    $tagCommit = (& git rev-parse --verify HEAD).Trim()
}
else {
    Write-Host "Cloning libdeflate ($Branch) into $Source..." -ForegroundColor Cyan
    git clone --recurse-submodules $RepoUrl $Source -b $Branch
    if ($LASTEXITCODE -ne 0) { Write-Error "Git clone failed."; Pop-Location; return }
    Set-Location $Source
    $tagCommit = (& git rev-parse --verify HEAD).Trim()
}

# --- 8. Clean Final Destination ---
if (Test-Path $libdeflateInstallDir) {
    Write-Host "Wiping existing installation..." -ForegroundColor Yellow
    Remove-Item $libdeflateInstallDir -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "[INSTALL] Creating fresh directory: $libdeflateInstallDir" -ForegroundColor Cyan
New-Item -Path $libdeflateInstallDir -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null

# Ensure fresh build directory
if (Test-Path $BuildDirShared) { Remove-Item $BuildDirShared -Recurse -Force -ErrorAction SilentlyContinue }
if (Test-Path $BuildDirStatic) { Remove-Item $BuildDirStatic -Recurse -Force -ErrorAction SilentlyContinue }
New-Item -Path $BuildDirShared -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null
New-Item -Path $BuildDirStatic -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null

$CommonCmakeArgs = @(
    "-G", "Ninja",
    "-DCMAKE_POLICY_DEFAULT_CMP0091=NEW",
    "-DCMAKE_POLICY_DEFAULT_CMP0109=NEW",
    "-DCMAKE_C_COMPILER=clang-cl",
    "-DCMAKE_CXX_COMPILER=clang-cl",
    "-DCMAKE_BUILD_TYPE=Release",
    "-DLIBDEFLATE_COMPRESSION_SUPPORT=ON",
    "-DLIBDEFLATE_DECOMPRESSION_SUPPORT=ON",
    "-DLIBDEFLATE_ZLIB_SUPPORT=ON",
    "-DLIBDEFLATE_GZIP_SUPPORT=ON",
    "-DLIBDEFLATE_BUILD_GZIP=OFF",
    "-DLIBDEFLATE_BUILD_TESTS=OFF"
)

# --- STAGE 1: Build Static Libraries ---
Write-Host "Building Static..." -ForegroundColor Cyan
cmake $CommonCmakeArgs `
    -S "$CMakeSource" `
    -B "$BuildDirStatic" `
    -DCMAKE_INSTALL_PREFIX="$libdeflateInstallDir" `
    -DLIBDEFLATE_BUILD_SHARED_LIB=OFF `
    -DLIBDEFLATE_BUILD_STATIC_LIB=ON `
    -DCMAKE_C_FLAGS="-Wno-deprecated-declarations -D_CRT_SECURE_NO_WARNINGS=1" `
    -DCMAKE_CXX_FLAGS="-Wno-deprecated-declarations -D_CRT_SECURE_NO_WARNINGS=1" `
    --no-warn-unused-cli
    
if ($LASTEXITCODE -ne 0) { Write-Error "libdeflate CMake Static configuration failed."; Pop-Location; return }

Write-Host "Building and Installing static lib to $libdeflateInstallDir..." -ForegroundColor Green
cmake --build "$BuildDirStatic" --target install --config Release --parallel

if ($LASTEXITCODE -ne 0) { Write-Error "libdeflate Static Build failed with exit code $LASTEXITCODE"; Pop-Location; return }

# Rename static lib to libdeflate_static.lib to avoid collision
Write-Host "Applying '_static' suffix to static libs..." -ForegroundColor Gray
Get-ChildItem -Path "$libdeflateInstallDir\lib\*.lib" | ForEach-Object {
    if ($_.BaseName -notmatch "_static") {
        $newName = ($_.BaseName -replace '(?i)-?static$', '') + "_static" + $_.Extension
        Move-Item -Path $_.FullName -Destination (Join-Path $_.DirectoryName $newName) -Force -ErrorAction SilentlyContinue
        Write-Host "  -> $newName" -ForegroundColor DarkGray
    }
}

# --- STAGE 2: Build Shared Libraries ---
Write-Host "Building Shared (DLL)..." -ForegroundColor Cyan
cmake $CommonCmakeArgs `
    -S "$CMakeSource" `
    -B "$BuildDirShared" `
    -DCMAKE_INSTALL_PREFIX="$libdeflateInstallDir" `
    -DLIBDEFLATE_BUILD_SHARED_LIB=ON `
    -DLIBDEFLATE_BUILD_STATIC_LIB=OFF `
    -DCMAKE_C_FLAGS="-Wno-deprecated-declarations -D_CRT_SECURE_NO_WARNINGS=1" `
    -DCMAKE_CXX_FLAGS="-Wno-deprecated-declarations -D_CRT_SECURE_NO_WARNINGS=1" `
    --no-warn-unused-cli
    
if ($LASTEXITCODE -ne 0) { Write-Error "libdeflate CMake Shared (DLL) configuration failed."; Pop-Location; return }

Write-Host "Building and Installing dynamic lib to $libdeflateInstallDir..." -ForegroundColor Green
cmake --build "$BuildDirShared" --target install --config Release --parallel

if ($LASTEXITCODE -ne 0) { Write-Error "libdeflate Shared Build failed with exit code $LASTEXITCODE"; Pop-Location; return }

Write-Host "Successfully built and installed libdeflate to $libdeflateInstallDir!" -ForegroundColor Green

# Cleanup temporary build debris
Remove-Item $BuildDirShared -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item $BuildDirStatic -Recurse -Force -ErrorAction SilentlyContinue

# Generate Environment Helper with Clean Paths
$libdeflateInstallDir = $libdeflateInstallDir.TrimEnd('\')
$libdeflateIncludeDir = Join-Path $libdeflateInstallDir "include"
$libdeflateLibDir = Join-Path $libdeflateInstallDir "lib"
$libdeflateBinPath = Join-Path $libdeflateInstallDir "bin"
$libdeflateCMakePath = $libdeflateInstallDir.Replace('\', '/')

$StaticLib = Join-Path $libdeflateLibDir ("$libdeflateLibName" + "_static.lib")
$SharedLib = Join-Path $libdeflateLibDir "$libdeflateLibName.lib"
$BinaryLib = Join-Path $libdeflateBinPath "$libdeflateLibName.dll"
$versionFile = Join-Path $libdeflateInstallDir "version.json"

if ((Test-Path $StaticLib) -or (Test-Path $SharedLib) -or (Test-Path $BinaryLib)) {

    $libdeflateHeader = Join-Path $libdeflateIncludeDir "libdeflate.h"
    if (-not (Test-Path $libdeflateHeader)) { $libdeflateHeader = Join-Path $Source "libdeflate.h" }

    $localVersion = "0.0.0"
    $rawVersion = $Branch
    $binaryversion = "0"

    if (Test-Path $libdeflateHeader) {
        $headerContent = Get-Content $libdeflateHeader
        $versionMatch = ($headerContent | Select-String '#define\s+LIBDEFLATE_VERSION_STRING\s+"([^"]+)"').Matches.Groups[1].Value

        if ($versionMatch) {
            $localVersion = $versionMatch
            $rawVersion = $localVersion
            $binaryversion = ([version]$localVersion).Major
            Write-Host "[VERSION] Detected libdeflate: $localVersion" -ForegroundColor Cyan
        }
    }

    # Save new version state
    $libdeflateVersion = $localVersion
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
    
    # --- 10. Create Environment Helper ---
    Write-Host "Generating environment helper script..." -ForegroundColor Cyan
    $EnvContent = @'
# LIBDEFLATE Environment Setup
$libdeflateroot = "VALUE_ROOT_PATH"
$libdeflateinclude = "VALUE_INCLUDE_PATH"
$libdeflatelibrary = "VALUE_LIB_PATH"
$libdeflatebin = "VALUE_BIN_PATH"
$libdeflateversion = "VALUE_VERSION"
$libdeflateabiversion = "VALUE_ABI_VERSION"
$libdeflatesoversion = "VALUE_SO_VERSION"
$libdeflatebinary = "VALUE_BINARY"
$libdeflateshared = "VALUE_SHARED"
$libdeflatestatic = "VALUE_STATIC"
$libdeflatelibname = "VALUE_LIB_NAME"
$libdeflatecmakepath = "VALUE_CMAKE_PATH"
$env:LIBDEFLATE_PATH = $libdeflateroot
$env:LIBDEFLATE_ROOT = $libdeflateroot
$env:LIBDEFLATE_BIN = $libdeflatebin
$env:LIBDEFLATE_INCLUDE_DIR = $libdeflateinclude
$env:LIBDEFLATE_LIBRARY_DIR = $libdeflatelibrary
$env:BINARY_LIB_DEFLATE = $libdeflatebinary
$env:SHARED_LIB_DEFLATE = $libdeflateshared
$env:STATIC_LIB_DEFLATE = $libdeflatestatic
$env:LIBDEFLATE_LIB_NAME = $libdeflatelibname
$env:LIBDEFLATE_VERSION = $libdeflateversion
$env:LIBDEFLATE_MAJOR = ([version]$libdeflateversion).Major
$env:LIBDEFLATE_MINOR = ([version]$libdeflateversion).Minor
$env:LIBDEFLATE_PATCH = ([version]$libdeflateversion).Build
$env:LIBDEFLATE_ABI_VERSION = $libdeflateabiversion
$env:LIBDEFLATE_SO_VERSION = $libdeflatesoversion
if ($env:CMAKE_PREFIX_PATH -notlike "*$libdeflatecmakepath*") { $env:CMAKE_PREFIX_PATH = $libdeflatecmakepath + ";" + $env:CMAKE_PREFIX_PATH; $env:CMAKE_PREFIX_PATH = ($env:CMAKE_PREFIX_PATH).Replace(";;", ";") }
if ($env:INCLUDE -notlike "*$libdeflateinclude*") { $env:INCLUDE = $libdeflateinclude + ";" + $env:INCLUDE; $env:INCLUDE = ($env:INCLUDE).Replace(";;", ";") }
if ($env:LIB -notlike "*$libdeflatelibrary*") { $env:LIB = $libdeflatelibrary + ";" + $env:LIB; $env:LIB = ($env:LIB).Replace(";;", ";") }
if ($env:PATH -notlike "*$libdeflatebin*") { $env:PATH = $libdeflatebin + ";" + $env:PATH; $env:PATH = ($env:PATH).Replace(";;", ";") }
Write-Host "libdeflate Environment Loaded (Version: $libdeflateversion) (Bin: $libdeflatebin)" -ForegroundColor Green
Write-Host "LIBDEFLATE_ROOT: $env:LIBDEFLATE_ROOT" -ForegroundColor Gray
'@  -replace "VALUE_ROOT_PATH", $libdeflateInstallDir `
    -replace "VALUE_INCLUDE_PATH", $libdeflateIncludeDir `
    -replace "VALUE_LIB_PATH", $libdeflateLibDir `
    -replace "VALUE_BIN_PATH", $libdeflateBinPath `
    -replace "VALUE_VERSION", $libdeflateVersion `
    -replace "VALUE_ABI_VERSION", $binaryversion `
    -replace "VALUE_SO_VERSION", $binaryversion `
    -replace "VALUE_SHARED", $SharedLib `
    -replace "VALUE_BINARY", $BinaryLib `
    -replace "VALUE_STATIC", $StaticLib `
    -replace "VALUE_LIB_NAME", $libdeflateLibName `
    -replace "VALUE_CMAKE_PATH", $libdeflateCMakePath

    $EnvContent | Out-File -FilePath $libdeflateEnvScript -Encoding utf8
    Write-Host "Created: $libdeflateEnvScript" -ForegroundColor Gray

    # Update Current Session
    if (Test-Path $libdeflateEnvScript) { . $libdeflateEnvScript } else {
        Write-Error "libdeflate build install finished but $libdeflateEnvScript was not created."
        Pop-Location; return
    }
    
    if ($libdeflateWithMachineEnvironment)
    {
        $MachineEnvContent = @'
# libdeflate Machine Environment Setup
$IsAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$ScopeColor = "Cyan"

if (-not $IsAdmin) {
    Write-Host "Elevation required to set libdeflate system variables. Relaunching as Administrator..." -ForegroundColor Yellow
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

$libdeflateroot = "VALUE_ROOT_PATH"
$libdeflatebin = "VALUE_BIN_PATH"
$libdeflateversion = "VALUE_VERSION"

$TargetScope = if ($IsAdmin) { "Machine" } else { "User" }
$RegPath = if ($IsAdmin) { "System\CurrentControlSet\Control\Session Manager\Environment" } else { "Environment" }
$RegRoot = if ($IsAdmin) { "LocalMachine" } else { "CurrentUser" }

# Open the registry key once
$RegKey = [Microsoft.Win32.Registry]::$RegRoot.OpenSubKey($RegPath, $true)

# Open the registry key directly to read the RAW (unexpanded) string
$CurrentRawPath = $RegKey.GetValue("EXTCOMPLIBS_PATH", "", [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)

$CleanedPathList = $CurrentRawPath -split ';' | Where-Object { 
    -not [string]::IsNullOrWhitespace($_) -and 
    $_ -notlike "*$libdeflateroot*"
}

$NewRawPath = ($CleanedPathList -join ";").Replace(";;", ";")

$TargetPath = $libdeflatebin

# Rebuild
$NewRawPath = ($NewRawPath + ";" + $TargetPath + ";").Replace(";;", ";")
Write-Host "[UPDATED] ($TargetScope) '$libdeflatebin' synced in EXTCOMPLIBS_PATH" -ForegroundColor $ScopeColor

# Save as ExpandString
$RegKey.SetValue("EXTCOMPLIBS_PATH", $NewRawPath, [Microsoft.Win32.RegistryValueKind]::ExpandString)
$env:EXTCOMPLIBS_PATH = $NewRawPath

$RegKey.Close()

$env:LIBDEFLATE_ROOT = $libdeflateroot
Write-Host "libdeflate Environment Loaded (Version: $libdeflateversion) (Bin: $libdeflatebin)" -ForegroundColor Green
Write-Host "LIBDEFLATE_ROOT: $env:LIBDEFLATE_ROOT" -ForegroundColor Gray
'@  -replace "VALUE_ROOT_PATH", $libdeflateInstallDir `
    -replace "VALUE_BIN_PATH", $libdeflateBinPath `
    -replace "VALUE_VERSION", $libdeflateVersion

        $MachineEnvContent | Out-File -FilePath $libdeflateMachineEnvScript -Encoding utf8
        Write-Host "Created: $libdeflateMachineEnvScript" -ForegroundColor Gray
        
        # --- Interaction: Prompt to apply persistent changes ---
        Write-Host ""
        $choice = Read-Host "Do you want to run the Machine Environment script now to persist libdeflate changes to the Registry? (y/n)"
        if ($choice -eq 'y' -or $choice -eq 'Y') {
            Write-Host "Executing $libdeflateMachineEnvScript..." -ForegroundColor Yellow
            try {
                # Start the generated script. It handles its own elevation logic.
                & $libdeflateMachineEnvScript
            }
            catch {
                Write-Error "Failed to execute the Machine Environment script: $($_.Exception.Message)"
            }
        }
        else {
            Write-Host "Skipped persistent registry update. You can run it later at: $libdeflateMachineEnvScript" -ForegroundColor Gray
        }
    }
    
    # --- Return to Start ---
    Pop-Location
    Write-Host "Successfully Done! and returned to: $(Get-Location)" -ForegroundColor DarkGreen
} else {
    Write-Error "libdeflate library was not found in the $libdeflateLibDir folder."
    Pop-Location; return
}
