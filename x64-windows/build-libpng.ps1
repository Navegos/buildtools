# SPDX-FileCopyrightText: Copyright (c) 2026 Navegos. @DevelVitorF. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
# project: buildtools
# file: x64-windows/build-libpng.ps1
# created: 2026-05-03
# lastModified: 2026-05-04

param (
    [Parameter(HelpMessage = "Base workspace path", Mandatory = $false)]
    [string]$workspacePath = $null,

    [Parameter(HelpMessage = "libpng git repo url", Mandatory = $false)]
    [string]$gitUrl = "https://github.com/pnggroup/libpng.git",
    
    [Parameter(HelpMessage = "libpng git branch to sync from", Mandatory = $false)]
    [string]$gitBranch = "libpng18",

    [Parameter(HelpMessage = "Path for libpng library storage", Mandatory = $false)]
    [string]$libpngInstallDir = "$env:LIBRARIES_PATH\libpng",
    
    [Parameter(HelpMessage = "Lib name, if it's building with a different name", Mandatory = $false)]
    [string]$libpngLibName = "libpng",
    
    [Parameter(HelpMessage = "Force a full purge of the local libpng version before continuing", Mandatory = $false)]
    [switch]$forceCleanup,
    
    [Parameter(HelpMessage = "Add's libpng Machine Environment Variables.", Mandatory = $false)]
    [switch]$withMachineEnvironment
)

$libpngWorkspacePath = $workspacePath
$libpngGitUrl = $gitUrl
$libpngGitBranch = $gitBranch
$libpngForceCleanup = $forceCleanup
$libpngWithMachineEnvironment = $withMachineEnvironment

# 1. Bootstrap Environment if variables are missing
if ([string]::IsNullOrWhitespace($env:ENVIRONMENT_PATH) -or -not (Test-Path $env:ENVIRONMENT_PATH) -or [string]::IsNullOrWhitespace($env:BINARIES_PATH) -or -not (Test-Path $env:BINARIES_PATH) -or [string]::IsNullOrWhitespace($env:LIBRARIES_PATH) -or -not (Test-Path $env:LIBRARIES_PATH)) {
    Write-Error "User Environment variables missing. Please run adduserpaths.ps1 -LibrariesDir 'Path\for\Libraries' -BinariesDir 'Path\for\Binaries' -EnvironmentDir 'Path\for\Environment'"
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
$RootlibpngInstallDir = Split-Path -Path $libpngInstallDir -Parent
$RootlibpngWorkspacePath = if ([string]::IsNullOrWhitespace($libpngWorkspacePath)) { Get-Location } else { $libpngWorkspacePath }

# Load Zlib requirement
if ([string]::IsNullOrWhiteSpace($env:SHARED_LIB_ZLIB) -or -not (Test-Path $env:SHARED_LIB_ZLIB)) {
    $zlibEnvScript = Join-Path $EnvironmentDir "env-zlib.ps1"
    if (Test-Path $zlibEnvScript) { . $zlibEnvScript }
    if ([string]::IsNullOrWhiteSpace($env:SHARED_LIB_ZLIB) -or -not (Test-Path $env:SHARED_LIB_ZLIB)) {
        $zlibBuildScript = Join-Path $PSScriptRoot "build-zlib.ps1"
        if (Test-Path $zlibBuildScript) {
            $zlibInstallDir = Join-Path $RootlibpngInstallDir "zlib"
            . $zlibBuildScript -workspacePath $RootlibpngWorkspacePath -zlibInstallDir $zlibInstallDir
        }
        else {
            Write-Error "CRITICAL: Cannot build zlib. zlib is missing and $zlibBuildScript was not found."
            return
        }
    }
}

$RootPath = if ([string]::IsNullOrWhitespace($RootlibpngWorkspacePath)) { Get-Location } else { $RootlibpngWorkspacePath }

# --- 6. Path Resolution ---
Push-Location $RootPath

$Source         = Join-Path $RootPath "libpng"
$BuildDirShared = Join-Path $Source "build_shared"
$BuildDirStatic = Join-Path $Source "build_static"
$RepoUrl        = $libpngGitUrl
$Branch         = $libpngGitBranch
$CMakeSource    = $Source
$tag_name       = $Branch
$url            = $RepoUrl

$libpngEnvScript = Join-Path $EnvironmentDir "env-libpng.ps1"
$libpngMachineEnvScript = Join-Path $EnvironmentDir "machine-env-libpng.ps1"

# --- 1. Cleanup Mechanism ---
function Invoke-libpngVersionPurge {
    param ([string]$InstallPath)
    Write-Host "--- Initiating libpng Purge ---" -ForegroundColor Cyan

    if ($libpngWithMachineEnvironment) {
        $libpngCleanMachineEnvScript = Join-Path $env:TEMP "clean-machine-env-libpng.ps1"

        # Generating Clean Machine Environment wich removes the persist registry machine Environment
        $CleanMachineEnvContent = @'
# libpng Clean Machine Environment Setup

# --- 0. Self-Elevation Logic ---
$IsAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$ScopeColor = "Cyan"

if (-not $IsAdmin) {
    Write-Host "Elevation required to clean libpng system variables. Relaunching as Administrator..." -ForegroundColor Yellow
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

$libpngroot = "VALUE_ROOT_PATH"

$TargetScope = if ($IsAdmin) { "Machine" } else { "User" }
$RegPath = if ($IsAdmin) { "System\CurrentControlSet\Control\Session Manager\Environment" } else { "Environment" }
$RegRoot = if ($IsAdmin) { "LocalMachine" } else { "CurrentUser" }

# 1. Registry Cleanup (EXTCOMPLIBS_PATH)
$RegKey = [Microsoft.Win32.Registry]::$RegRoot.OpenSubKey($RegPath, $true)

# Open the registry key directly to read the RAW (unexpanded) string
$RawPath = $RegKey.GetValue("EXTCOMPLIBS_PATH", "", [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)

# Cleanup: Remove empty strings, any path containing $libpngroot,
$CleanPath = ($RawPath -split ';' | Where-Object { $_ -notlike "*$libpngroot*" }) -join ";"

# Save as ExpandString
$RegKey.SetValue("EXTCOMPLIBS_PATH", $CleanPath, [Microsoft.Win32.RegistryValueKind]::ExpandString)
$env:EXTCOMPLIBS_PATH = $CleanPath

$RegKey.Close()

Write-Host "[REMOVED] ($TargetScope) all '*$libpngroot*' removed from EXTCOMPLIBS_PATH" -ForegroundColor $ScopeColor
'@  -replace "VALUE_ROOT_PATH", $InstallPath

        $CleanMachineEnvContent | Out-File -FilePath $libpngCleanMachineEnvScript -Encoding utf8
        Write-Host "Created: $libpngCleanMachineEnvScript" -ForegroundColor Gray
        
        # --- Interaction: Prompt to remove persistent changes ---
        Write-Host ""
        $choice = Read-Host "Administrator rights required to Clean Machine Environment libpng changes? (y/n)"
        if ($choice -eq 'y' -or $choice -eq 'Y') {
            Write-Host "Executing $libpngCleanMachineEnvScript..." -ForegroundColor Yellow
            try {
                # Start the generated script. It handles its own elevation logic.
                & $libpngCleanMachineEnvScript
            }
            catch {
                Write-Error "Failed to execute the Clean Machine Environment script: $($_.Exception.Message)"
                Pop-Location; return
            }
        }
        else {
            Write-Error "Skipped Clean Machine Environment libpng changes."
            Pop-Location; return
        }

        # Cleanup
        Remove-Item $libpngCleanMachineEnvScript -Recurse -Force -ErrorAction SilentlyContinue
    }

    # 2. Filesystem Clean (Requires checking for locked files)
    # delete everithing we create don't fail later
    if (Test-Path $libpngEnvScript) {
        Write-Host "  [DELETING] $libpngEnvScript" -ForegroundColor Yellow
        Remove-Item $libpngEnvScript -Recurse -Force -ErrorAction SilentlyContinue
    }
    if (Test-Path $libpngMachineEnvScript) {
        Write-Host "  [DELETING] $libpngMachineEnvScript" -ForegroundColor Yellow
        Remove-Item $libpngMachineEnvScript -Recurse -Force -ErrorAction SilentlyContinue
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
    Get-ChildItem Env:\LIBPNG_* | ForEach-Object { Remove-Item Env:\$($_.Name) -ErrorAction SilentlyContinue }
    Get-ChildItem Env:\BINARY_LIB_PNG* | ForEach-Object { Remove-Item Env:\$($_.Name) -ErrorAction SilentlyContinue }
    Get-ChildItem Env:\SHARED_LIB_PNG* | ForEach-Object { Remove-Item Env:\$($_.Name) -ErrorAction SilentlyContinue }
    Get-ChildItem Env:\STATIC_LIB_PNG* | ForEach-Object { Remove-Item Env:\$($_.Name) -ErrorAction SilentlyContinue }
    
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
    
    Write-Host "--- LIBPNG Purge Complete ---" -ForegroundColor Green
}

if ($libpngForceCleanup) {
    Invoke-libpngVersionPurge -InstallPath $libpngInstallDir
}

if (Test-Path $Source) {
    Write-Host "Syncing libpng ($Branch) at $Source..." -ForegroundColor Cyan
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
    Write-Host "Cloning libpng ($Branch) into $Source..." -ForegroundColor Cyan
    git clone --recurse-submodules $RepoUrl $Source -b $Branch
    if ($LASTEXITCODE -ne 0) { Write-Error "Git clone failed."; Pop-Location; return }
    Set-Location $Source
    $tagCommit = (& git rev-parse --verify HEAD).Trim()
}

# --- 8. Clean Final Destination ---
if (Test-Path $libpngInstallDir) {
    Write-Host "Wiping existing installation..." -ForegroundColor Yellow
    Remove-Item $libpngInstallDir -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "[INSTALL] Creating fresh directory: $libpngInstallDir" -ForegroundColor Cyan
New-Item -Path $libpngInstallDir -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null

# Ensure fresh build directory
if (Test-Path $BuildDirShared) { Remove-Item $BuildDirShared -Recurse -Force -ErrorAction SilentlyContinue }
if (Test-Path $BuildDirStatic) { Remove-Item $BuildDirStatic -Recurse -Force -ErrorAction SilentlyContinue }
New-Item -Path $BuildDirShared -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null
New-Item -Path $BuildDirStatic -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null

$CommonCmakeArgs = @(
    "-G", "Ninja",
    "-DCMAKE_POLICY_DEFAULT_CMP0091=NEW",
    "-DCMAKE_POLICY_DEFAULT_CMP0109=NEW",
    "-DCMAKE_C_COMPILER=clang",
    "-DCMAKE_CXX_COMPILER=clang++",
    "-DCMAKE_BUILD_TYPE=Release",
    "-DPNG_TESTS=OFF",
    "-DPNG_TOOLS=OFF",
    "-DPNG_EXECUTABLES=OFF",
    "-DPNG_HARDWARE_OPTIMIZATIONS=ON",
    "-DZLIB_ROOT=$($env:ZLIB_ROOT -replace '\\', '/')"
)

# --- STAGE 1: Build Static Libraries ---
Write-Host "Building Static..." -ForegroundColor Cyan
cmake $CommonCmakeArgs `
    -S "$CMakeSource" `
    -B "$BuildDirStatic" `
    -DCMAKE_INSTALL_PREFIX="$libpngInstallDir" `
    -DPNG_SHARED=OFF `
    -DPNG_STATIC=ON `
    -DCMAKE_C_FLAGS="-Wno-deprecated-declarations -D_CRT_SECURE_NO_WARNINGS=1" `
    -DCMAKE_CXX_FLAGS="-Wno-deprecated-declarations -D_CRT_SECURE_NO_WARNINGS=1" `
    --no-warn-unused-cli
    
if ($LASTEXITCODE -ne 0) { Write-Error "libpng CMake Static configuration failed."; Pop-Location; return }

Write-Host "Building and Installing static lib to $libpngInstallDir..." -ForegroundColor Green
cmake --build "$BuildDirStatic" --target install --config Release --parallel

if ($LASTEXITCODE -ne 0) { Write-Error "libpng Static Build failed with exit code $LASTEXITCODE"; Pop-Location; return }

# Rename static lib to libpng_static.lib to avoid collision
Write-Host "Applying '_static' suffix to static libs..." -ForegroundColor Gray
Get-ChildItem -Path "$libpngInstallDir\lib\*.lib" | ForEach-Object {
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
    -DCMAKE_INSTALL_PREFIX="$libpngInstallDir" `
    -DPNG_SHARED=ON `
    -DPNG_STATIC=OFF `
    -DCMAKE_C_FLAGS="-Wno-deprecated-declarations -D_CRT_SECURE_NO_WARNINGS=1" `
    -DCMAKE_CXX_FLAGS="-Wno-deprecated-declarations -D_CRT_SECURE_NO_WARNINGS=1" `
    --no-warn-unused-cli
    
if ($LASTEXITCODE -ne 0) { Write-Error "libpng CMake Shared (DLL) configuration failed."; Pop-Location; return }

Write-Host "Building and Installing dynamic lib to $libpngInstallDir..." -ForegroundColor Green
cmake --build "$BuildDirShared" --target install --config Release --parallel

if ($LASTEXITCODE -ne 0) { Write-Error "libpng Shared Build failed with exit code $LASTEXITCODE"; Pop-Location; return }

Write-Host "Successfully built and installed libpng to $libpngInstallDir!" -ForegroundColor Green

# Cleanup temporary build debris
Remove-Item $BuildDirShared -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item $BuildDirStatic -Recurse -Force -ErrorAction SilentlyContinue

# Generate Environment Helper with Clean Paths
$libpngInstallDir = $libpngInstallDir.TrimEnd('\')
$libpngIncludeDir = Join-Path $libpngInstallDir "include"
$libpngLibDir = Join-Path $libpngInstallDir "lib"
$libpngBinPath = Join-Path $libpngInstallDir "bin"
$libpngCMakePath = $libpngInstallDir.Replace('\', '/')

$StaticLib = Join-Path $libpngLibDir ("$libpngLibName" + "_static.lib")
$SharedLib = Join-Path $libpngLibDir "$libpngLibName.lib"
$BinaryLib = Join-Path $libpngBinPath "$libpngLibName.dll"
$versionFile = Join-Path $libpngInstallDir "version.json"

$cmakeFile = Join-Path $Source "CMakeLists.txt"
$localVersion = "0.0.0"
$rawVersion = $Branch
$binaryversion = "0"
    
if (Test-Path $cmakeFile) {
    $cmakeContent = Get-Content $cmakeFile -Raw
    $majorMatch = [regex]::Match($cmakeContent, '(?i)set\s*\(\s*PNGLIB_MAJOR\s+(\d+)\s*\)')
    $minorMatch = [regex]::Match($cmakeContent, '(?i)set\s*\(\s*PNGLIB_MINOR\s+(\d+)\s*\)')
    $relMatch = [regex]::Match($cmakeContent, '(?i)set\s*\(\s*PNGLIB_REVISION\s+(\d+)\s*\)')
        
    if ($majorMatch.Success -and $minorMatch.Success -and $relMatch.Success) {
        $localVersion = "$($majorMatch.Groups[1].Value).$($minorMatch.Groups[1].Value).$($relMatch.Groups[1].Value)"
        $rawVersion = $localVersion
        $binaryversion = "$($majorMatch.Groups[1].Value)$($minorMatch.Groups[1].Value)"
        Write-Host "[VERSION] Detected libpng: $localVersion" -ForegroundColor Cyan
    }
}

if (-not (Test-Path $StaticLib)) { $StaticLib = Join-Path $libpngLibDir ("$libpngLibName" + "$binaryversion" + "_static.lib") }
if (-not (Test-Path $SharedLib)) { $SharedLib = Join-Path $libpngLibDir ("$libpngLibName" + "$binaryversion" + ".lib") }
if (-not (Test-Path $BinaryLib)) { $BinaryLib = Join-Path $libpngBinPath ("$libpngLibName" + "$binaryversion" + ".dll") }

if ((Test-Path $StaticLib) -or (Test-Path $SharedLib) -or (Test-Path $BinaryLib)) {

    # Save new version state
    $libpngVersion = $localVersion
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
# LIBPNG Environment Setup
$libpngroot = "VALUE_ROOT_PATH"
$libpnginclude = "VALUE_INCLUDE_PATH"
$libpnglibrary = "VALUE_LIB_PATH"
$libpngbin = "VALUE_BIN_PATH"
$libpngversion = "VALUE_VERSION"
$libpngabiversion = "VALUE_ABI_VERSION"
$libpngsoversion = "VALUE_SO_VERSION"
$libpngbinary = "VALUE_BINARY"
$libpngshared = "VALUE_SHARED"
$libpngstatic = "VALUE_STATIC"
$libpnglibname = "VALUE_LIB_NAME"
$libpngcmakepath = "VALUE_CMAKE_PATH"
$env:LIBPNG_PATH = $libpngroot
$env:LIBPNG_ROOT = $libpngroot
$env:LIBPNG_BIN = $libpngbin
$env:LIBPNG_INCLUDE_DIR = $libpnginclude
$env:LIBPNG_LIBRARY_DIR = $libpnglibrary
$env:BINARY_LIB_PNG = $libpngbinary
$env:SHARED_LIB_PNG = $libpngshared
$env:STATIC_LIB_PNG = $libpngstatic
$env:LIBPNG_LIB_NAME = $libpnglibname
$env:LIBPNG_VERSION = $libpngversion
$env:LIBPNG_MAJOR = ([version]$libpngversion).Major
$env:LIBPNG_MINOR = ([version]$libpngversion).Minor
$env:LIBPNG_PATCH = ([version]$libpngversion).Patch
$env:LIBPNG_ABI_VERSION = $libpngabiversion
$env:LIBPNG_SO_VERSION = $libpngsoversion
if ($env:CMAKE_PREFIX_PATH -notlike "*$libpngcmakepath*") { $env:CMAKE_PREFIX_PATH = $libpngcmakepath + ";" + $env:CMAKE_PREFIX_PATH; $env:CMAKE_PREFIX_PATH = ($env:CMAKE_PREFIX_PATH).Replace(";;", ";") }
if ($env:INCLUDE -notlike "*$libpnginclude*") { $env:INCLUDE = $libpnginclude + ";" + $env:INCLUDE; $env:INCLUDE = ($env:INCLUDE).Replace(";;", ";") }
if ($env:LIB -notlike "*$libpnglibrary*") { $env:LIB = $libpnglibrary + ";" + $env:LIB; $env:LIB = ($env:LIB).Replace(";;", ";") }
if ($env:PATH -notlike "*$libpngbin*") { $env:PATH = $libpngbin + ";" + $env:PATH; $env:PATH = ($env:PATH).Replace(";;", ";") }
Write-Host "libpng Environment Loaded (Version: $libpngversion) (Bin: $libpngbin)" -ForegroundColor Green
Write-Host "LIBPNG_ROOT: $env:LIBPNG_ROOT" -ForegroundColor Gray
'@  -replace "VALUE_ROOT_PATH", $libpngInstallDir `
    -replace "VALUE_INCLUDE_PATH", $libpngIncludeDir `
    -replace "VALUE_LIB_PATH", $libpngLibDir `
    -replace "VALUE_BIN_PATH", $libpngBinPath `
    -replace "VALUE_VERSION", $libpngVersion `
    -replace "VALUE_ABI_VERSION", $binaryversion `
    -replace "VALUE_SO_VERSION", $binaryversion `
    -replace "VALUE_SHARED", $SharedLib `
    -replace "VALUE_BINARY", $BinaryLib `
    -replace "VALUE_STATIC", $StaticLib `
    -replace "VALUE_LIB_NAME", $libpngLibName `
    -replace "VALUE_CMAKE_PATH", $libpngCMakePath

    $EnvContent | Out-File -FilePath $libpngEnvScript -Encoding utf8
    Write-Host "Created: $libpngEnvScript" -ForegroundColor Gray

    if (Test-Path $libpngEnvScript) { . $libpngEnvScript } else {
        Write-Error "libpng build install finished but $libpngEnvScript was not created."
        Pop-Location; return
    }
    
    if ($libpngWithMachineEnvironment)
    {
        $MachineEnvContent = @'
# libpng Machine Environment Setup
$IsAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$ScopeColor = "Cyan"

if (-not $IsAdmin) {
    Write-Host "Elevation required to set libpng system variables. Relaunching as Administrator..." -ForegroundColor Yellow
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

$libpngroot = "VALUE_ROOT_PATH"
$libpngbin = "VALUE_BIN_PATH"
$libpngversion = "VALUE_VERSION"

$TargetScope = if ($IsAdmin) { "Machine" } else { "User" }
$RegPath = if ($IsAdmin) { "System\CurrentControlSet\Control\Session Manager\Environment" } else { "Environment" }
$RegRoot = if ($IsAdmin) { "LocalMachine" } else { "CurrentUser" }

# Open the registry key once
$RegKey = [Microsoft.Win32.Registry]::$RegRoot.OpenSubKey($RegPath, $true)

# Open the registry key directly to read the RAW (unexpanded) string
$CurrentRawPath = $RegKey.GetValue("EXTCOMPLIBS_PATH", "", [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)

$CleanedPathList = $CurrentRawPath -split ';' | Where-Object { 
    -not [string]::IsNullOrWhitespace($_) -and 
    $_ -notlike "*$libpngroot*"
}

$NewRawPath = ($CleanedPathList -join ";").Replace(";;", ";")

$TargetPath = $libpngbin

# Rebuild
$NewRawPath = ($NewRawPath + ";" + $TargetPath + ";").Replace(";;", ";")
Write-Host "[UPDATED] ($TargetScope) '$libpngbin' synced in EXTCOMPLIBS_PATH" -ForegroundColor $ScopeColor

# Save as ExpandString
$RegKey.SetValue("EXTCOMPLIBS_PATH", $NewRawPath, [Microsoft.Win32.RegistryValueKind]::ExpandString)
$env:EXTCOMPLIBS_PATH = $NewRawPath

$RegKey.Close()

$env:LIBPNG_ROOT = $libpngroot
Write-Host "libpng Environment Loaded (Version: $libpngversion) (Bin: $libpngbin)" -ForegroundColor Green
Write-Host "LIBPNG_ROOT: $env:LIBPNG_ROOT" -ForegroundColor Gray
'@  -replace "VALUE_ROOT_PATH", $libpngInstallDir `
    -replace "VALUE_BIN_PATH", $libpngBinPath `
    -replace "VALUE_VERSION", $libpngVersion

        $MachineEnvContent | Out-File -FilePath $libpngMachineEnvScript -Encoding utf8
        Write-Host "Created: $libpngMachineEnvScript" -ForegroundColor Gray
        
        # --- Interaction: Prompt to apply persistent changes ---
        Write-Host ""
        $choice = Read-Host "Do you want to run the Machine Environment script now to persist libpng changes to the Registry? (y/n)"
        if ($choice -eq 'y' -or $choice -eq 'Y') {
            Write-Host "Executing $libpngMachineEnvScript..." -ForegroundColor Yellow
            try {
                # Start the generated script. It handles its own elevation logic.
                & $libpngMachineEnvScript
            }
            catch {
                Write-Error "Failed to execute the Machine Environment script: $($_.Exception.Message)"
            }
        }
        else {
            Write-Host "Skipped persistent registry update. You can run it later at: $libpngMachineEnvScript" -ForegroundColor Gray
        }
    }
    
    # --- Return to Start ---
    Pop-Location
    Write-Host "Successfully Done! and returned to: $(Get-Location)" -ForegroundColor DarkGreen
} else {
    Write-Error "libpng library was not found in the $libpngLibDir folder."
    Pop-Location; return
}
