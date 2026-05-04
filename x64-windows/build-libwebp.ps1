# SPDX-FileCopyrightText: Copyright (c) 2026 Navegos. @DevelVitorF. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
# project: buildtools
# file: x64-windows/build-libwebp.ps1
# created: 2026-05-03
# lastModified: 2026-05-04

param (
    [Parameter(HelpMessage = "Base workspace path", Mandatory = $false)]
    [string]$workspacePath = $null,

    [Parameter(HelpMessage = "libwebp git repo url", Mandatory = $false)]
    [string]$gitUrl = "https://github.com/webmproject/libwebp.git",
    
    [Parameter(HelpMessage = "libwebp git branch to sync from", Mandatory = $false)]
    [string]$gitBranch = "main",

    [Parameter(HelpMessage = "Path for libwebp library storage", Mandatory = $false)]
    [string]$libwebpInstallDir = "$env:LIBRARIES_PATH\libwebp",
    
    [Parameter(HelpMessage = "Lib name, if it's building with a different name", Mandatory = $false)]
    [string]$libwebpLibName = "webp",
    
    [Parameter(HelpMessage = "Force a full purge of the local libwebp version before continuing", Mandatory = $false)]
    [switch]$forceCleanup,
    
    [Parameter(HelpMessage = "Add's libwebp Machine Environment Variables.", Mandatory = $false)]
    [switch]$withMachineEnvironment
)

$libwebpWorkspacePath = $workspacePath
$libwebpGitUrl = $gitUrl
$libwebpGitBranch = $gitBranch
$libwebpForceCleanup = $forceCleanup
$libwebpWithMachineEnvironment = $withMachineEnvironment

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
$RootlibwebpWorkspacePath = if ([string]::IsNullOrWhitespace($libwebpWorkspacePath)) { Get-Location } else { $libwebpWorkspacePath }
$RootPath = if ([string]::IsNullOrWhitespace($RootlibwebpWorkspacePath)) { Get-Location } else { $RootlibwebpWorkspacePath }

# --- 6. Path Resolution ---
Push-Location $RootPath

$Source         = Join-Path $RootPath "libwebp"
$BuildDirShared = Join-Path $Source "build_shared"
$BuildDirStatic = Join-Path $Source "build_static"
$RepoUrl        = $libwebpGitUrl
$Branch         = $libwebpGitBranch
$CMakeSource    = $Source
$tag_name       = $Branch
$url            = $RepoUrl

$libwebpEnvScript = Join-Path $EnvironmentDir "env-libwebp.ps1"
$libwebpMachineEnvScript = Join-Path $EnvironmentDir "machine-env-libwebp.ps1"

# --- 1. Cleanup Mechanism ---
function Invoke-libwebpVersionPurge {
    param ([string]$InstallPath)
    Write-Host "--- Initiating libwebp Purge ---" -ForegroundColor Cyan

    if ($libwebpWithMachineEnvironment) {
        $libwebpCleanMachineEnvScript = Join-Path $env:TEMP "clean-machine-env-libwebp.ps1"

        # Generating Clean Machine Environment wich removes the persist registry machine Environment
        $CleanMachineEnvContent = @'
# libwebp Clean Machine Environment Setup

# --- 0. Self-Elevation Logic ---
$IsAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$ScopeColor = "Cyan"

if (-not $IsAdmin) {
    Write-Host "Elevation required to clean libwebp system variables. Relaunching as Administrator..." -ForegroundColor Yellow
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

$libwebproot = "VALUE_ROOT_PATH"

$TargetScope = if ($IsAdmin) { "Machine" } else { "User" }
$RegPath = if ($IsAdmin) { "System\CurrentControlSet\Control\Session Manager\Environment" } else { "Environment" }
$RegRoot = if ($IsAdmin) { "LocalMachine" } else { "CurrentUser" }

# 1. Registry Cleanup (EXTCOMPLIBS_PATH)
$RegKey = [Microsoft.Win32.Registry]::$RegRoot.OpenSubKey($RegPath, $true)

# Open the registry key directly to read the RAW (unexpanded) string
$RawPath = $RegKey.GetValue("EXTCOMPLIBS_PATH", "", [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)

# Cleanup: Remove empty strings, any path containing $libwebproot,
$CleanPath = ($RawPath -split ';' | Where-Object { $_ -notlike "*$libwebproot*" }) -join ";"

# Save as ExpandString
$RegKey.SetValue("EXTCOMPLIBS_PATH", $CleanPath, [Microsoft.Win32.RegistryValueKind]::ExpandString)
$env:EXTCOMPLIBS_PATH = $CleanPath

$RegKey.Close()

Write-Host "[REMOVED] ($TargetScope) all '*$libwebproot*' removed from EXTCOMPLIBS_PATH" -ForegroundColor $ScopeColor
'@  -replace "VALUE_ROOT_PATH", $InstallPath

        $CleanMachineEnvContent | Out-File -FilePath $libwebpCleanMachineEnvScript -Encoding utf8
        Write-Host "Created: $libwebpCleanMachineEnvScript" -ForegroundColor Gray
        
        # --- Interaction: Prompt to remove persistent changes ---
        Write-Host ""
        $choice = Read-Host "Administrator rights required to Clean Machine Environment libwebp changes? (y/n)"
        if ($choice -eq 'y' -or $choice -eq 'Y') {
            Write-Host "Executing $libwebpCleanMachineEnvScript..." -ForegroundColor Yellow
            try {
                # Start the generated script. It handles its own elevation logic.
                & $libwebpCleanMachineEnvScript
            }
            catch {
                Write-Error "Failed to execute the Clean Machine Environment script: $($_.Exception.Message)"
                Pop-Location; return
            }
        }
        else {
            Write-Error "Skipped Clean Machine Environment libwebp changes."
            Pop-Location; return
        }

        # Cleanup
        Remove-Item $libwebpCleanMachineEnvScript -Recurse -Force -ErrorAction SilentlyContinue
    }

    # 2. Filesystem Clean (Requires checking for locked files)
    # delete everithing we create don't fail later
    if (Test-Path $libwebpEnvScript) {
        Write-Host "  [DELETING] $libwebpEnvScript" -ForegroundColor Yellow
        Remove-Item $libwebpEnvScript -Recurse -Force -ErrorAction SilentlyContinue
    }
    if (Test-Path $libwebpMachineEnvScript) {
        Write-Host "  [DELETING] $libwebpMachineEnvScript" -ForegroundColor Yellow
        Remove-Item $libwebpMachineEnvScript -Recurse -Force -ErrorAction SilentlyContinue
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
    Get-ChildItem Env:\LIBWEBP_* | ForEach-Object { Remove-Item Env:\$($_.Name) -ErrorAction SilentlyContinue }
    Get-ChildItem Env:\BINARY_LIB_WEBP* | ForEach-Object { Remove-Item Env:\$($_.Name) -ErrorAction SilentlyContinue }
    Get-ChildItem Env:\SHARED_LIB_WEBP* | ForEach-Object { Remove-Item Env:\$($_.Name) -ErrorAction SilentlyContinue }
    Get-ChildItem Env:\STATIC_LIB_WEBP* | ForEach-Object { Remove-Item Env:\$($_.Name) -ErrorAction SilentlyContinue }
    Get-ChildItem Env:\BINARY_LIB_SHARPYUV* | ForEach-Object { Remove-Item Env:\$($_.Name) -ErrorAction SilentlyContinue }
    Get-ChildItem Env:\SHARED_LIB_SHARPYUV* | ForEach-Object { Remove-Item Env:\$($_.Name) -ErrorAction SilentlyContinue }
    Get-ChildItem Env:\STATIC_LIB_SHARPYUV* | ForEach-Object { Remove-Item Env:\$($_.Name) -ErrorAction SilentlyContinue }
    
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
    
    Write-Host "--- LIBWEBP Purge Complete ---" -ForegroundColor Green
}

if ($libwebpForceCleanup) {
    Invoke-libwebpVersionPurge -InstallPath $libwebpInstallDir
}

if (Test-Path $Source) {
    Write-Host "Syncing libwebp ($Branch) at $Source..." -ForegroundColor Cyan
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
    Write-Host "Cloning libwebp ($Branch) into $Source..." -ForegroundColor Cyan
    git clone --recurse-submodules $RepoUrl $Source -b $Branch
    if ($LASTEXITCODE -ne 0) { Write-Error "Git clone failed."; Pop-Location; return }
    Set-Location $Source
    $tagCommit = (& git rev-parse --verify HEAD).Trim()
}

# --- 8. Clean Final Destination ---
if (Test-Path $libwebpInstallDir) {
    Write-Host "Wiping existing installation..." -ForegroundColor Yellow
    Remove-Item $libwebpInstallDir -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "[INSTALL] Creating fresh directory: $libwebpInstallDir" -ForegroundColor Cyan
New-Item -Path $libwebpInstallDir -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null

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
    "-DWEBP_ENABLE_SIMD=ON",
    "-DWEBP_BUILD_ANIM_UTILS=OFF",
    "-DWEBP_BUILD_CWEBP=OFF",
    "-DWEBP_BUILD_DWEBP=OFF",
    "-DWEBP_BUILD_GIF2WEBP=OFF",
    "-DWEBP_BUILD_IMG2WEBP=OFF",
    "-DWEBP_BUILD_VWEBP=OFF",
    "-DWEBP_BUILD_WEBPINFO=OFF",
    "-DWEBP_BUILD_LIBWEBPMUX=ON",
    "-DWEBP_BUILD_WEBPMUX=OFF",
    "-DWEBP_BUILD_EXTRAS=OFF",
    "-DWEBP_BUILD_WEBP_JS=OFF",
    "-DWEBP_BUILD_FUZZTEST=OFF",
    "-DWEBP_USE_THREAD=ON",
    "-DWEBP_NEAR_LOSSLESS=ON",
    "-DWEBP_ENABLE_WUNUSED_RESULT=ON"
)

# --- STAGE 1: Build Static Libraries ---
Write-Host "Building Static..." -ForegroundColor Cyan
cmake $CommonCmakeArgs `
    -S "$CMakeSource" `
    -B "$BuildDirStatic" `
    -DCMAKE_INSTALL_PREFIX="$libwebpInstallDir" `
    -DBUILD_SHARED_LIBS=OFF `
    -DCMAKE_C_FLAGS="-Wno-deprecated-declarations -D_CRT_SECURE_NO_WARNINGS=1" `
    -DCMAKE_CXX_FLAGS="-Wno-deprecated-declarations -D_CRT_SECURE_NO_WARNINGS=1" `
    --no-warn-unused-cli
    
if ($LASTEXITCODE -ne 0) { Write-Error "libwebp CMake Static configuration failed."; Pop-Location; return }

Write-Host "Building and Installing static lib to $libwebpInstallDir..." -ForegroundColor Green
cmake --build "$BuildDirStatic" --target install --config Release --parallel

if ($LASTEXITCODE -ne 0) { Write-Error "libwebp Static Build failed with exit code $LASTEXITCODE"; Pop-Location; return }

# Rename static lib to libwebp_static.lib to avoid collision
Write-Host "Applying '_static' suffix to static libs..." -ForegroundColor Gray
Get-ChildItem -Path "$libwebpInstallDir\lib\*.lib" | ForEach-Object {
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
    -DCMAKE_INSTALL_PREFIX="$libwebpInstallDir" `
    -DBUILD_SHARED_LIBS=ON `
    -DCMAKE_C_FLAGS="-Wno-deprecated-declarations -D_CRT_SECURE_NO_WARNINGS=1" `
    -DCMAKE_CXX_FLAGS="-Wno-deprecated-declarations -D_CRT_SECURE_NO_WARNINGS=1" `
    --no-warn-unused-cli
    
if ($LASTEXITCODE -ne 0) { Write-Error "libwebp CMake Shared (DLL) configuration failed."; Pop-Location; return }

Write-Host "Building and Installing dynamic lib to $libwebpInstallDir..." -ForegroundColor Green
cmake --build "$BuildDirShared" --target install --config Release --parallel

if ($LASTEXITCODE -ne 0) { Write-Error "libwebp Shared Build failed with exit code $LASTEXITCODE"; Pop-Location; return }

Write-Host "Successfully built and installed libwebp to $libwebpInstallDir!" -ForegroundColor Green

# Cleanup temporary build debris
Remove-Item $BuildDirShared -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item $BuildDirStatic -Recurse -Force -ErrorAction SilentlyContinue

# Generate Environment Helper with Clean Paths
$libwebpInstallDir = $libwebpInstallDir.TrimEnd('\')
$libwebpIncludeDir = Join-Path $libwebpInstallDir "include"
$libwebpLibDir = Join-Path $libwebpInstallDir "lib"
$libwebpBinPath = Join-Path $libwebpInstallDir "bin"
$libwebpCMakePath = $libwebpInstallDir.Replace('\', '/')

$StaticLib = Join-Path $libwebpLibDir ("$libwebpLibName" + "_static.lib")
$SharedLib = Join-Path $libwebpLibDir "$libwebpLibName.lib"
$BinaryLib = Join-Path $libwebpBinPath "$libwebpLibName.dll"
$sharpyuvStaticLib = Join-Path $libwebpLibDir ("sharpyuv" + "_static.lib")
$sharpyuvSharedLib = Join-Path $libwebpLibDir "sharpyuv.lib"
$sharpyuvBinaryLib = Join-Path $libwebpBinPath "sharpyuv.dll"
$decoderStaticLib = Join-Path $libwebpLibDir ("$libwebpLibName" + "decoder" + "_static.lib")
$decoderSharedLib = Join-Path $libwebpLibDir ("$libwebpLibName" + "decoder" + ".lib")
$decoderBinaryLib = Join-Path $libwebpBinPath ("$libwebpLibName" + "decoder" + ".dll")
$demuxStaticLib = Join-Path $libwebpLibDir ("$libwebpLibName" + "demux" + "_static.lib")
$demuxSharedLib = Join-Path $libwebpLibDir ("$libwebpLibName" + "demux" + ".lib")
$demuxBinaryLib = Join-Path $libwebpBinPath ("$libwebpLibName" + "demux" + ".dll")
$muxStaticLib = Join-Path $libwebpLibDir ("$libwebpLibName" + "mux" + "_static.lib")
$muxSharedLib = Join-Path $libwebpLibDir ("$libwebpLibName" + "mux" + ".lib")
$muxBinaryLib = Join-Path $libwebpBinPath ("$libwebpLibName" + "mux" + ".dll")
$versionFile = Join-Path $libwebpInstallDir "version.json"

$configureAcFile = Join-Path $Source "configure.ac"
$localVersion = "0.0.0"
$rawVersion = $Branch
$binaryversion = "0"
    
if (Test-Path $configureAcFile) {
    $configureAcContent = Get-Content $configureAcFile -Raw
    $versionMatch = [regex]::Match($configureAcContent, '(?i)AC_INIT\s*\(\s*\[?libwebp\]?\s*,\s*\[?([\d\.]+)\]?')
        
    if ($versionMatch.Success) {
        $localVersion = $versionMatch.Groups[1].Value
        $rawVersion = $localVersion
        $binaryversion = ([version]$localVersion).Major
        Write-Host "[VERSION] Detected libwebp: $localVersion" -ForegroundColor Cyan
    }
}

if ((Test-Path $StaticLib) -or (Test-Path $SharedLib) -or (Test-Path $BinaryLib)) {

    # Save new version state
    $libwebpVersion = $localVersion
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
# LIBWEBP Environment Setup
$libwebproot = "VALUE_ROOT_PATH"
$libwebpinclude = "VALUE_INCLUDE_PATH"
$libwebplibrary = "VALUE_LIB_PATH"
$libwebpbin = "VALUE_BIN_PATH"
$libwebpversion = "VALUE_VERSION"
$libwebpabiversion = "VALUE_ABI_VERSION"
$libwebpsoversion = "VALUE_SO_VERSION"
$libwebpbinary = "VALUE_BINARY"
$libwebpshared = "VALUE_SHARED"
$libwebpstatic = "VALUE_STATIC"
$sharpyuvlibwebpbinary = "VALUE_SHARPYUV_BINARY"
$sharpyuvlibwebpshared = "VALUE_SHARPYUV_SHARED"
$sharpyuvlibwebpstatic = "VALUE_SHARPYUV_STATIC"
$decoderlibwebpbinary = "VALUE_DECODER_BINARY"
$decoderlibwebpshared = "VALUE_DECODER_SHARED"
$decoderlibwebpstatic = "VALUE_DECODER_STATIC"
$demuxlibwebpbinary = "VALUE_DEMUX_BINARY"
$demuxlibwebpshared = "VALUE_DEMUX_SHARED"
$demuxlibwebpstatic = "VALUE_DEMUX_STATIC"
$muxlibwebpbinary = "VALUE_MUX_BINARY"
$muxlibwebpshared = "VALUE_MUX_SHARED"
$muxlibwebpstatic = "VALUE_MUX_STATIC"
$libwebplibname = "VALUE_LIB_NAME"
$libwebpcmakepath = "VALUE_CMAKE_PATH"
$env:LIBWEBP_PATH = $libwebproot
$env:LIBWEBP_ROOT = $libwebproot
$env:LIBWEBP_BIN = $libwebpbin
$env:LIBWEBP_INCLUDE_DIR = $libwebpinclude
$env:LIBWEBP_LIBRARY_DIR = $libwebplibrary
$env:BINARY_LIB_WEBP = $libwebpbinary
$env:SHARED_LIB_WEBP = $libwebpshared
$env:STATIC_LIB_WEBP = $libwebpstatic
$env:BINARY_LIB_SHARPYUV = $sharpyuvlibwebpbinary
$env:SHARED_LIB_SHARPYUV = $sharpyuvlibwebpshared
$env:STATIC_LIB_SHARPYUV = $sharpyuvlibwebpstatic
$env:BINARY_LIB_WEBPDECODER = $decoderlibwebpbinary
$env:SHARED_LIB_WEBPDECODER = $decoderlibwebpshared
$env:STATIC_LIB_WEBPDECODER = $decoderlibwebpstatic
$env:BINARY_LIB_WEBPDEMUX = $demuxlibwebpbinary
$env:SHARED_LIB_WEBPDEMUX = $demuxlibwebpshared
$env:STATIC_LIB_WEBPDEMUX = $demuxlibwebpstatic
$env:BINARY_LIB_WEBPMUX = $muxlibwebpbinary
$env:SHARED_LIB_WEBPMUX = $muxlibwebpshared
$env:STATIC_LIB_WEBPMUX = $muxlibwebpstatic
$env:LIBWEBP_LIB_NAME = $libwebplibname
$env:LIBWEBP_VERSION = $libwebpversion
$env:LIBWEBP_MAJOR = ([version]$libwebpversion).Major
$env:LIBWEBP_MINOR = ([version]$libwebpversion).Minor
$env:LIBWEBP_PATCH = ([version]$libwebpversion).Patch
$env:LIBWEBP_ABI_VERSION = $libwebpabiversion
$env:LIBWEBP_SO_VERSION = $libwebpsoversion
if ($env:CMAKE_PREFIX_PATH -notlike "*$libwebpcmakepath*") { $env:CMAKE_PREFIX_PATH = $libwebpcmakepath + ";" + $env:CMAKE_PREFIX_PATH; $env:CMAKE_PREFIX_PATH = ($env:CMAKE_PREFIX_PATH).Replace(";;", ";") }
if ($env:INCLUDE -notlike "*$libwebpinclude*") { $env:INCLUDE = $libwebpinclude + ";" + $env:INCLUDE; $env:INCLUDE = ($env:INCLUDE).Replace(";;", ";") }
if ($env:LIB -notlike "*$libwebplibrary*") { $env:LIB = $libwebplibrary + ";" + $env:LIB; $env:LIB = ($env:LIB).Replace(";;", ";") }
if ($env:PATH -notlike "*$libwebpbin*") { $env:PATH = $libwebpbin + ";" + $env:PATH; $env:PATH = ($env:PATH).Replace(";;", ";") }
Write-Host "libwebp Environment Loaded (Version: $libwebpversion) (Bin: $libwebpbin)" -ForegroundColor Green
Write-Host "LIBWEBP_ROOT: $env:LIBWEBP_ROOT" -ForegroundColor Gray
'@  -replace "VALUE_ROOT_PATH", $libwebpInstallDir `
    -replace "VALUE_INCLUDE_PATH", $libwebpIncludeDir `
    -replace "VALUE_LIB_PATH", $libwebpLibDir `
    -replace "VALUE_BIN_PATH", $libwebpBinPath `
    -replace "VALUE_VERSION", $libwebpVersion `
    -replace "VALUE_ABI_VERSION", $binaryversion `
    -replace "VALUE_SO_VERSION", $binaryversion `
    -replace "VALUE_SHARED", $SharedLib `
    -replace "VALUE_BINARY", $BinaryLib `
    -replace "VALUE_STATIC", $StaticLib `
    -replace "VALUE_SHARPYUV_SHARED", $sharpyuvSharedLib `
    -replace "VALUE_SHARPYUV_BINARY", $sharpyuvBinaryLib `
    -replace "VALUE_SHARPYUV_STATIC", $sharpyuvStaticLib `
    -replace "VALUE_DECODER_SHARED", $decoderSharedLib `
    -replace "VALUE_DECODER_BINARY", $decoderBinaryLib `
    -replace "VALUE_DECODER_STATIC", $decoderStaticLib `
    -replace "VALUE_DEMUX_SHARED", $demuxSharedLib `
    -replace "VALUE_DEMUX_BINARY", $demuxBinaryLib `
    -replace "VALUE_DEMUX_STATIC", $demuxStaticLib `
    -replace "VALUE_MUX_SHARED", $muxSharedLib `
    -replace "VALUE_MUX_BINARY", $muxBinaryLib `
    -replace "VALUE_MUX_STATIC", $muxStaticLib `
    -replace "VALUE_LIB_NAME", $libwebpLibName `
    -replace "VALUE_CMAKE_PATH", $libwebpCMakePath

    $EnvContent | Out-File -FilePath $libwebpEnvScript -Encoding utf8
    Write-Host "Created: $libwebpEnvScript" -ForegroundColor Gray

    # Update Current Session
    if (Test-Path $libwebpEnvScript) { . $libwebpEnvScript } else {
        Write-Error "libwebp build install finished but $libwebpEnvScript was not created."
        Pop-Location; return
    }
    
    if ($libwebpWithMachineEnvironment)
    {
        $MachineEnvContent = @'
# libwebp Machine Environment Setup
$IsAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$ScopeColor = "Cyan"

if (-not $IsAdmin) {
    Write-Host "Elevation required to set libwebp system variables. Relaunching as Administrator..." -ForegroundColor Yellow
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

$libwebproot = "VALUE_ROOT_PATH"
$libwebpbin = "VALUE_BIN_PATH"
$libwebpversion = "VALUE_VERSION"

$TargetScope = if ($IsAdmin) { "Machine" } else { "User" }
$RegPath = if ($IsAdmin) { "System\CurrentControlSet\Control\Session Manager\Environment" } else { "Environment" }
$RegRoot = if ($IsAdmin) { "LocalMachine" } else { "CurrentUser" }

# Open the registry key once
$RegKey = [Microsoft.Win32.Registry]::$RegRoot.OpenSubKey($RegPath, $true)

# Open the registry key directly to read the RAW (unexpanded) string
$CurrentRawPath = $RegKey.GetValue("EXTCOMPLIBS_PATH", "", [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)

$CleanedPathList = $CurrentRawPath -split ';' | Where-Object { 
    -not [string]::IsNullOrWhitespace($_) -and 
    $_ -notlike "*$libwebproot*"
}

$NewRawPath = ($CleanedPathList -join ";").Replace(";;", ";")

$TargetPath = $libwebpbin

# Rebuild
$NewRawPath = ($NewRawPath + ";" + $TargetPath + ";").Replace(";;", ";")
Write-Host "[UPDATED] ($TargetScope) '$libwebpbin' synced in EXTCOMPLIBS_PATH" -ForegroundColor $ScopeColor

# Save as ExpandString
$RegKey.SetValue("EXTCOMPLIBS_PATH", $NewRawPath, [Microsoft.Win32.RegistryValueKind]::ExpandString)
$env:EXTCOMPLIBS_PATH = $NewRawPath

$RegKey.Close()

$env:LIBWEBP_ROOT = $libwebproot
Write-Host "libwebp Environment Loaded (Version: $libwebpversion) (Bin: $libwebpbin)" -ForegroundColor Green
Write-Host "LIBWEBP_ROOT: $env:LIBWEBP_ROOT" -ForegroundColor Gray
'@  -replace "VALUE_ROOT_PATH", $libwebpInstallDir `
    -replace "VALUE_BIN_PATH", $libwebpBinPath `
    -replace "VALUE_VERSION", $libwebpVersion

        $MachineEnvContent | Out-File -FilePath $libwebpMachineEnvScript -Encoding utf8
        Write-Host "Created: $libwebpMachineEnvScript" -ForegroundColor Gray
        
        # --- Interaction: Prompt to apply persistent changes ---
        Write-Host ""
        $choice = Read-Host "Do you want to run the Machine Environment script now to persist libwebp changes to the Registry? (y/n)"
        if ($choice -eq 'y' -or $choice -eq 'Y') {
            Write-Host "Executing $libwebpMachineEnvScript..." -ForegroundColor Yellow
            try {
                # Start the generated script. It handles its own elevation logic.
                & $libwebpMachineEnvScript
            }
            catch {
                Write-Error "Failed to execute the Machine Environment script: $($_.Exception.Message)"
            }
        }
        else {
            Write-Host "Skipped persistent registry update. You can run it later at: $libwebpMachineEnvScript" -ForegroundColor Gray
        }
    }
    
    # --- Return to Start ---
    Pop-Location
    Write-Host "Successfully Done! and returned to: $(Get-Location)" -ForegroundColor DarkGreen
} else {
    Write-Error "libwebp library was not found in the $libwebpLibDir folder."
    Pop-Location; return
}
