# SPDX-FileCopyrightText: Copyright (c) 2026 Navegos. @DevelVitorF. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
# project: buildtools
# file: x64-windows/build-brotli.ps1
# created: 2026-05-01
# lastModified: 2026-05-13

param (
    [Parameter(HelpMessage = "Base workspace path", Mandatory = $false)]
    [string]$workspacePath = $null,

    [Parameter(HelpMessage = "Brotli git repo url", Mandatory = $false)]
    [string]$gitUrl = "https://github.com/google/brotli.git",
    
    [Parameter(HelpMessage = "Brotli git branch to sync from", Mandatory = $false)]
    [string]$gitBranch = "master",

    [Parameter(HelpMessage = "Path for Brotli installation", Mandatory = $false)]
    [string]$brotliInstallDir = "$env:LIBRARIES_PATH\brotli",

    [Parameter(HelpMessage = "Lib name, if it's building with a different name", Mandatory = $false)]
    [string]$brotliLibName = "brotli",

    [Parameter(HelpMessage = "Force a full purge of the local Brotli version before continuing", Mandatory = $false)]
    [switch]$forceCleanup,
    
    [Parameter(HelpMessage = "Add's Brotli Machine Environment Variables. Requires Machine Administrator Rights.", Mandatory = $false)]
    [switch]$withMachineEnvironment,

    [Parameter(ValueFromRemainingArguments = $true)]
    $RemainingArgs
)

# Capture parameters
$brotliWorkspacePath = $workspacePath
$brotliGitUrl = $gitUrl
$brotliGitBranch = $gitBranch
$BrotliForceCleanup = $forceCleanup
$BrotliWithMachineEnvironment = $withMachineEnvironment

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

#$RootbrotliInstallDir = Split-Path -Path $brotliInstallDir -Parent
$RootbrotliWorkspacePath = if ([string]::IsNullOrWhitespace($brotliWorkspacePath)) { Get-Location } else { $brotliWorkspacePath }
$RootPath = $RootbrotliWorkspacePath

Push-Location $RootPath

$Source         = Join-Path $RootPath "brotli"
$BuildDirShared = Join-Path $Source "build_shared"
$BuildDirStatic = Join-Path $Source "build_static"
$RepoUrl        = $brotliGitUrl
$Branch         = $brotliGitBranch
$CMakeSource    = $Source
$tag_name       = $Branch
$url            = $RepoUrl

# if Symlink present delete
$GlobalBinDir = "$env:BINARIES_PATH"
# Brotli provides a single executable (brotli.exe) for the CLI tool.
# The libraries are separate.
$brotlitools = @("brotli.exe")
foreach ($brotlitool in $brotlitools) {
    $target = Join-Path $GlobalBinDir $brotlitool
    if (Test-Path $target) { Remove-Item $target -Force -ErrorAction SilentlyContinue }
}

$brotliBinPath = Join-Path $brotliInstallDir "bin"
$brotliExePath = Join-Path $brotliBinPath "brotli.exe"
$versionFile = Join-Path $brotliInstallDir "version.json"
$brotliEnvScript = Join-Path $EnvironmentDir "env-brotli.ps1"
$brotliMachineEnvScript = Join-Path $EnvironmentDir "machine-env-brotli.ps1"

# --- 1. Cleanup Mechanism (for existing installations) ---
function Invoke-BrotliVersionPurge {
    param ([string]$InstallPath)
    Write-Host "--- Initiating Brotli Purge ---" -ForegroundColor Cyan

    if ($BrotliWithMachineEnvironment)
    {
        $brotliCleanMachineEnvScript = Join-Path $env:TEMP "clean-machine-env-brotli.ps1"

        # Generating Clean Machine Environment wich removes the persist registry machine Environment
        $CleanMachineEnvContent = @'
# Brotli Clean Machine Environment Setup

# --- 0. Self-Elevation Logic ---
$IsAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$ScopeColor = "Cyan"

if (-not $IsAdmin) {
    Write-Host "Elevation required to clean Brotli system variables. Relaunching as Administrator..." -ForegroundColor Yellow
    $Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    foreach ($Parameter in $PSBoundParameters.GetEnumerator()) {
        if ($Parameter.Value -is [switch]) {
            if ($Parameter.Value) { $Arguments += " -$($Parameter.Key)" }
        }
        else {
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

$brotliroot = "VALUE_ROOT_PATH"

$TargetScope = if ($IsAdmin) { "Machine" } else { "User" }
$RegPath = if ($IsAdmin) { "System\CurrentControlSet\Control\Session Manager\Environment" } else { "Environment" }
$RegRoot = if ($IsAdmin) { "LocalMachine" } else { "CurrentUser" }

# 1. Registry Cleanup (EXTCOMPLIBS_PATH)
$RegKey = [Microsoft.Win32.Registry]::$RegRoot.OpenSubKey($RegPath, $true)
$RawPath = $RegKey.GetValue("EXTCOMPLIBS_PATH", "", [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)

# Cleanup: Remove empty strings, any path containing $brotliroot
$CleanPath = ($RawPath -split ';' | Where-Object { $_ -notlike "*$brotliroot*" }) -join ";"

$RegKey.SetValue("EXTCOMPLIBS_PATH", $CleanPath, [Microsoft.Win32.RegistryValueKind]::ExpandString)
$env:EXTCOMPLIBS_PATH = $CleanPath

$RegKey.Close()

Write-Host "[REMOVED] ($TargetScope) all '*$brotliroot*' removed from EXTCOMPLIBS_PATH" -ForegroundColor $ScopeColor
'@  -replace "VALUE_ROOT_PATH", $InstallPath

        $CleanMachineEnvContent | Out-File -FilePath $brotliCleanMachineEnvScript -Encoding utf8
        Write-Host "Created: $brotliCleanMachineEnvScript" -ForegroundColor Gray
        
        # --- Interaction: Prompt to remove persistent changes ---
        Write-Host ""
        $choice = Read-Host "Administrator rights required to Clean Machine Environment Brotli changes? (y/n)"
        if ($choice -eq 'y' -or $choice -eq 'Y') {
            Write-Host "Executing $brotliCleanMachineEnvScript..." -ForegroundColor Yellow
            try {
                & $brotliCleanMachineEnvScript
            }
            catch {
                Write-Error "Failed to execute the Clean Machine Environment script: $($_.Exception.Message)"
                return
            }
        }
        else {
            Write-Error "Skipped Clean Machine Environment Brotli changes."
            return
        }

        Remove-Item $brotliCleanMachineEnvScript -Recurse -Force -ErrorAction SilentlyContinue
    }

    # 2. Filesystem Clean (Requires checking for locked files)
    if (Test-Path $brotliEnvScript) {
        Write-Host "  [DELETING] $brotliEnvScript" -ForegroundColor Yellow
        Remove-Item $brotliEnvScript -Recurse -Force -ErrorAction SilentlyContinue
    }
    if (Test-Path $brotliMachineEnvScript) {
        Write-Host "  [DELETING] $brotliMachineEnvScript" -ForegroundColor Yellow
        Remove-Item $brotliMachineEnvScript -Recurse -Force -ErrorAction SilentlyContinue
    }
    if (Test-Path $InstallPath) {
        Write-Host "  [DELETING] $InstallPath" -ForegroundColor Yellow
        Remove-Item $InstallPath -Recurse -Force -ErrorAction SilentlyContinue
    }
    if (Test-Path $Source) {
        Write-Host "  [DELETING] $Source" -ForegroundColor Yellow
        Remove-Item $Source -Recurse -Force -ErrorAction SilentlyContinue
    }
    
    foreach ($brotlitool in $brotlitools) {
        $target = Join-Path $GlobalBinDir $brotlitool
        if (Test-Path $target) { Remove-Item $target -Force -ErrorAction SilentlyContinue; Write-Host "  [REMOVED] Link: $brotlitool" -ForegroundColor Gray }
    }
    
    # remove local Env variables for current session
    Get-ChildItem Env:\BROTLI_* | ForEach-Object { Remove-Item Env:\$($_.Name) -ErrorAction SilentlyContinue }
    Get-ChildItem Env:\BINARY_LIB_BROTLI* | ForEach-Object { Remove-Item Env:\$($_.Name) -ErrorAction SilentlyContinue }
    Get-ChildItem Env:\SHARED_LIB_BROTLI* | ForEach-Object { Remove-Item Env:\$($_.Name) -ErrorAction SilentlyContinue }
    Get-ChildItem Env:\STATIC_LIB_BROTLI* | ForEach-Object { Remove-Item Env:\$($_.Name) -ErrorAction SilentlyContinue }

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
    
    Write-Host "--- Brotli Purge Complete ---" -ForegroundColor Green
}

if ($BrotliForceCleanup) {
    Invoke-BrotliVersionPurge -InstallPath $brotliInstallDir
}

# --- 2. Source Management ---
if (Test-Path $Source) {
    Write-Host "Syncing Brotli ($Branch) at $Source..." -ForegroundColor Cyan
    Set-Location $Source
    git fetch --all
    if ($LASTEXITCODE -ne 0) { Write-Error "Git fetch failed."; Pop-Location; return }
    git reset --hard "origin/$Branch"
    git clean -xdf
    git pull --recurse-submodules --force
    if ($LASTEXITCODE -ne 0) { Write-Error "Git pull failed."; Pop-Location; return }
    $tagCommit = (& git rev-parse --verify HEAD).Trim()
} else {
    Write-Host "Cloning Brotli ($Branch) into $Source..." -ForegroundColor Cyan
    git clone --recurse-submodules $RepoUrl $Source -b $Branch
    if ($LASTEXITCODE -ne 0) { Write-Error "Git clone failed."; Pop-Location; return }
    Set-Location $Source
    $tagCommit = (& git rev-parse --verify HEAD).Trim()
}

# --- 3. Clean Final Destination ---
if (Test-Path $brotliInstallDir) {
    Write-Host "[CLEANUP] Removing existing Brotli installation at $brotliInstallDir..." -ForegroundColor Yellow
    Remove-Item -Path $brotliInstallDir -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "[INSTALL] Creating fresh directory: $brotliInstallDir" -ForegroundColor Cyan
New-Item -Path $brotliInstallDir -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null
New-Item -Path $brotliBinPath -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null

if (Test-Path $BuildDirShared) { Remove-Item $BuildDirShared -Recurse -Force -ErrorAction SilentlyContinue }
if (Test-Path $BuildDirStatic) { Remove-Item $BuildDirStatic -Recurse -Force -ErrorAction SilentlyContinue }
New-Item -Path $BuildDirShared -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null
New-Item -Path $BuildDirStatic -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null

# Common CMake Flags 
$CommonCmakeArgs = @(
    "-G", "Ninja",
    "-DCMAKE_POLICY_DEFAULT_CMP0091=NEW",
    "-DCMAKE_POLICY_DEFAULT_CMP0109=NEW",
    "-DCMAKE_C_COMPILER=clang-cl",
    "-DCMAKE_CXX_COMPILER=clang-cl",
    "-DCMAKE_BUILD_TYPE=Release",
    "-DBROTLI_DISABLE_TESTS=ON",
    "-DBROTLI_BUNDLED_MODE=OFF"
)

# --- 9. STAGE 1: Build Static Libraries ---
Write-Host "Building Static (brotli-static.lib)..." -ForegroundColor Cyan
cmake $CommonCmakeArgs `
    -S "$CMakeSource" `
    -B "$BuildDirStatic" `
    -DCMAKE_INSTALL_PREFIX="$brotliInstallDir" `
    -DBUILD_SHARED_LIBS=OFF `
    -DBROTLI_BUILD_TOOLS=OFF `
    -DCMAKE_CXX_STANDARD=20 `
    -DCMAKE_C_STANDARD=17 `
    -DCMAKE_C_FLAGS="-Wno-deprecated-declarations -D_CRT_SECURE_NO_WARNINGS=1" `
    -DCMAKE_CXX_FLAGS="-Wno-deprecated-declarations -D_CRT_SECURE_NO_WARNINGS=1" `
    --no-warn-unused-cli

if ($LASTEXITCODE -ne 0) { Write-Error "Brotli CMake Static configuration failed."; Pop-Location; return }

Write-Host "Building and Installing static lib to $brotliInstallDir..." -ForegroundColor Green
cmake --build "$BuildDirStatic" --target install --config Release --parallel

if ($LASTEXITCODE -ne 0) { Write-Error "Brotli Static Build failed with exit code $LASTEXITCODE"; Pop-Location; return }

# --- 9.5. Rename Static Libraries (Suffix 's' Only) ---
Write-Host "Applying 's' suffix to static libs..." -ForegroundColor Gray
Get-ChildItem -Path "$brotliInstallDir\lib\*.lib" | ForEach-Object {
    $newName = $_.BaseName + "_static" + $_.Extension
    Move-Item -Path $_.FullName -Destination (Join-Path $_.DirectoryName $newName) -Force -ErrorAction SilentlyContinue
    Write-Host "  -> $newName" -ForegroundColor DarkGray
}

# --- 10. STAGE 2: Build Shared Libraries ---
Write-Host "Building Shared (DLL)..." -ForegroundColor Cyan
cmake $CommonCmakeArgs `
    -S "$CMakeSource" `
    -B "$BuildDirShared" `
    -DCMAKE_INSTALL_PREFIX="$brotliInstallDir" `
    -DBUILD_SHARED_LIBS=ON `
    -DBROTLI_BUILD_TOOLS=ON `
    -DCMAKE_CXX_STANDARD=20 `
    -DCMAKE_C_STANDARD=17 `
    -DCMAKE_C_FLAGS="-Wno-deprecated-declarations -D_CRT_SECURE_NO_WARNINGS=1" `
    -DCMAKE_CXX_FLAGS="-Wno-deprecated-declarations -D_CRT_SECURE_NO_WARNINGS=1" `
    --no-warn-unused-cli
    
if ($LASTEXITCODE -ne 0) { Write-Error "Brotli CMake Shared (DLL) configuration failed."; Pop-Location; return }

Write-Host "Building and Installing dynamic lib to $brotliInstallDir..." -ForegroundColor Green
cmake --build "$BuildDirShared" --target install --config Release --parallel

if ($LASTEXITCODE -ne 0) { Write-Error "Brotli Shared Build failed with exit code $LASTEXITCODE"; Pop-Location; return }

Write-Host "Successfully built and installed brotli to $brotliInstallDir!" -ForegroundColor Green

# Cleanup temporary build debris
Remove-Item $BuildDirShared -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item $BuildDirStatic -Recurse -Force -ErrorAction SilentlyContinue

# Generate Environment Helper with Clean Paths
$brotliInstallDir = $brotliInstallDir.TrimEnd('\')
$brotliBinPath = $brotliBinPath.TrimEnd('\')
$brotliExePath = Join-Path $brotliBinPath "brotli.exe"
$brotliIncludeDir = Join-Path $brotliInstallDir "include"
$brotliLibDir = Join-Path $brotliInstallDir "lib"
$brotliCMakePath = $brotliInstallDir.Replace('\', '/')

$StaticLibCommon = Join-Path $brotliLibDir ($brotliLibName + "common_static.lib")
$SharedLibCommon = Join-Path $brotliLibDir ($brotliLibName + "common.lib")
$BinaryLibCommon = Join-Path $brotliBinPath ($brotliLibName + "common.dll")

$StaticLibDec = Join-Path $brotliLibDir ($brotliLibName + "dec_static.lib")
$SharedLibDec = Join-Path $brotliLibDir ($brotliLibName + "dec.lib")
$BinaryLibDec = Join-Path $brotliBinPath ($brotliLibName + "dec.dll")

$StaticLibEnc = Join-Path $brotliLibDir ($brotliLibName + "enc_static.lib")
$SharedLibEnc = Join-Path $brotliLibDir ($brotliLibName + "enc.lib")
$BinaryLibEnc = Join-Path $brotliBinPath ($brotliLibName + "enc.dll")
$versionFile = Join-Path $brotliInstallDir "version.json"

if ((Test-Path $brotliExePath) -or (Test-Path $StaticLibCommon) -or (Test-Path $SharedLibCommon) -or (Test-Path $BinaryLibCommon)) {
    $localVersion = "0.0.0"
    $rawVersion = $Branch
    $binaryversion = "0"

    if (Test-Path $brotliExePath) {
        $rawVersion = (& $brotliExePath -V 2>&1 | Select-String "brotli\s+v?([0-9rc\.]+)").Matches.Value
        if ($rawVersion -match 'brotli\s+v?([0-9rc\.]+)') { 
            $localVersion = $Matches[1]
            
            # Parse version formats like 1.2.0.rc7, 1.2.0rc7, 1.2.rc7, 1.2rc7 into 1.2.0.7
            if ($localVersion -match '^(\d+)\.(\d+)(?:\.(\d+))?(?:\.?rc(\d+))?$') {
                $major = $Matches[1]
                $minor = $Matches[2]
                $patch = if ([string]::IsNullOrEmpty($Matches[3])) { "0" } else { $Matches[3] }
                if (-not [string]::IsNullOrEmpty($Matches[4])) {
                    $rc = $Matches[4]
                    $localVersion = "$major.$minor.$patch.$rc"
                } else {
                    $localVersion = "$major.$minor.$patch"
                }
                $binaryversion = $major
            } elseif ($localVersion -match '^(\d+)') {
                $binaryversion = $Matches[1]
            }
            Write-Host "[VERSION] Detected brotli: $localVersion" -ForegroundColor Cyan
        }
    }

    $brotliVersion = $localVersion
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

    # --- 3. Finalize Helpers & Symlinks ---
    Write-Host "Generating environment helper script..." -ForegroundColor Cyan

    $cleanBrotliVersion = $brotliVersion -replace 'rc.*', ''
    $vBrotli = [version]$cleanBrotliVersion
    $brotliMajor = $vBrotli.Major
    $brotliMinor = $vBrotli.Minor
    $brotliPatch = $vBrotli.Build

    $EnvContent = @'
# Brotli Environment Setup
$brotliroot = "VALUE_ROOT_PATH"
$brotlibin = "VALUE_BIN_PATH"
$brotliexe = "VALUE_EXE_PATH"
$brotliversion = "VALUE_VERSION"
$brotliinclude = "VALUE_INCLUDE_PATH"
$brotlilibrary = "VALUE_LIB_PATH"
$brotliabiversion = "VALUE_ABI_VERSION"
$brotlisoversion = "VALUE_SO_VERSION"
$brotlicommonbinary = "VALUE_BINARY_COMMON"
$brotlicommonshared = "VALUE_SHARED_COMMON"
$brotlicommonstatic = "VALUE_STATIC_COMMON"
$brotlidecbinary = "VALUE_BINARY_DEC"
$brotlidecshared = "VALUE_SHARED_DEC"
$brotlidecstatic = "VALUE_STATIC_DEC"
$brotliencbinary = "VALUE_BINARY_ENC"
$brotliencshared = "VALUE_SHARED_ENC"
$brotliencstatic = "VALUE_STATIC_ENC"
$brotlicmakepath = "VALUE_CMAKE_PATH"
$env:BROTLI_PATH = $brotliroot
$env:BROTLI_ROOT = $brotliroot
$env:BROTLI_BIN = $brotlibin
$env:BROTLI_INCLUDE_DIR = $brotliinclude
$env:BROTLI_LIBRARY_DIR = $brotlilibrary
$env:BINARY_BROTLI = $brotliexe
$env:BINARY_LIB_BROTLI_COMMON = $brotlicommonbinary
$env:SHARED_LIB_BROTLI_COMMON = $brotlicommonshared
$env:STATIC_LIB_BROTLI_COMMON = $brotlicommonstatic
$env:BINARY_LIB_BROTLI_DEC = $brotlidecbinary
$env:SHARED_LIB_BROTLI_DEC = $brotlidecshared
$env:STATIC_LIB_BROTLI_DEC = $brotlidecstatic
$env:BINARY_LIB_BROTLI_ENC = $brotliencbinary
$env:SHARED_LIB_BROTLI_ENC = $brotliencshared
$env:STATIC_LIB_BROTLI_ENC = $brotliencstatic
$env:BROTLI_VERSION = $brotliversion
$env:BROTLI_MAJOR = "VALUE_MAJOR"
$env:BROTLI_MINOR = "VALUE_MINOR"
$env:BROTLI_PATCH = "VALUE_PATCH"
$env:BROTLI_ABI_VERSION = $brotliabiversion
$env:BROTLI_SO_VERSION = $brotlisoversion
if ($env:CMAKE_PREFIX_PATH -notlike "*$brotlicmakepath*") { $env:CMAKE_PREFIX_PATH = $brotlicmakepath + ";" + $env:CMAKE_PREFIX_PATH; $env:CMAKE_PREFIX_PATH = ($env:CMAKE_PREFIX_PATH).Replace(";;", ";") }
if ($env:INCLUDE -notlike "*$brotliinclude*") { $env:INCLUDE = $brotliinclude + ";" + $env:INCLUDE; $env:INCLUDE = ($env:INCLUDE).Replace(";;", ";") }
if ($env:LIB -notlike "*$brotlilibrary*") { $env:LIB = $brotlilibrary + ";" + $env:LIB; $env:LIB = ($env:LIB).Replace(";;", ";") }
if ($env:PATH -notlike "*$brotlibin*") { $env:PATH = $brotlibin + ";" + $env:PATH; $env:PATH = ($env:PATH).Replace(";;", ";") }
Write-Host "Brotli Environment Loaded (Version: $brotliversion) (Bin: $brotlibin)" -ForegroundColor Green
Write-Host "BROTLI_ROOT: $env:BROTLI_ROOT" -ForegroundColor Gray
'@  -replace "VALUE_BIN_PATH", $brotliBinPath `
    -replace "VALUE_EXE_PATH", $brotliExePath `
    -replace "VALUE_ROOT_PATH", $brotliInstallDir `
    -replace "VALUE_VERSION", $brotliVersion `
    -replace "VALUE_INCLUDE_PATH", $brotliIncludeDir `
    -replace "VALUE_LIB_PATH", $brotliLibDir `
    -replace "VALUE_ABI_VERSION", $binaryversion `
    -replace "VALUE_SO_VERSION", $binaryversion `
    -replace "VALUE_SHARED_COMMON", $SharedLibCommon `
    -replace "VALUE_BINARY_COMMON", $BinaryLibCommon `
    -replace "VALUE_STATIC_COMMON", $StaticLibCommon `
    -replace "VALUE_SHARED_DEC", $SharedLibDec `
    -replace "VALUE_BINARY_DEC", $BinaryLibDec `
    -replace "VALUE_STATIC_DEC", $StaticLibDec `
    -replace "VALUE_SHARED_ENC", $SharedLibEnc `
    -replace "VALUE_BINARY_ENC", $BinaryLibEnc `
    -replace "VALUE_STATIC_ENC", $StaticLibEnc `
    -replace "VALUE_CMAKE_PATH", $brotliCMakePath `
    -replace "VALUE_MAJOR", $brotliMajor `
    -replace "VALUE_MINOR", $brotliMinor `
    -replace "VALUE_PATCH", $brotliPatch

    $EnvContent | Out-File -FilePath $brotliEnvScript -Encoding utf8
    Write-Host "Created: $brotliEnvScript" -ForegroundColor Gray

    if (Test-Path $brotliEnvScript) { . $brotliEnvScript } else {
        Write-Error "brotli dep install finished but $brotliEnvScript was not created."
        Pop-Location; return
    }
    
    # --- 10. Symlink to Global Binaries ---
    Write-Host "Creating global symlink to: $GlobalBinDir..." -ForegroundColor Cyan

    foreach ($brotlitool in $brotlitools) {
        $source = Join-Path $brotliBinPath $brotlitool
        $target = Join-Path $GlobalBinDir $brotlitool

        if (Test-Path $source) {
            if (Test-Path $target) { Remove-Item $target -Force -ErrorAction SilentlyContinue }
            try {
                New-Item -Path $target -ItemType SymbolicLink -Value $source -ErrorAction Stop | Out-Null
                Write-Host "[LINKED] $brotlitool" -ForegroundColor Gray
            } catch {
                New-Item -Path $target -ItemType HardLink -Value $source | Out-Null
                Write-Host "[HARDLINKED] $brotlitool (Global) -> $source" -ForegroundColor Gray
            }
        }
    }

    Write-Host "[LINKED] Brotli is now globally available via %BINARIES_PATH%" -ForegroundColor Green
    Write-Host "Brotli Version: $(& $brotliExePath -V 2>&1)" -ForegroundColor Gray
    
    if ($BrotliWithMachineEnvironment)
    {
        $MachineEnvContent = @'
# Brotli Machine Environment Setup

# --- 0. Self-Elevation Logic ---
$IsAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$ScopeColor = "Cyan"

if (-not $IsAdmin) {
    Write-Host "Elevation required to set Brotli system variables. Relaunching as Administrator..." -ForegroundColor Yellow
    $Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    foreach ($Parameter in $PSBoundParameters.GetEnumerator()) {
        if ($Parameter.Value -is [switch]) {
            if ($Parameter.Value) { $Arguments += " -$($Parameter.Key)" }
        }
        else {
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

$brotliroot = "VALUE_ROOT_PATH"
$brotlibin = "VALUE_BIN_PATH"
$brotliversion = "VALUE_VERSION"

$TargetScope = if ($IsAdmin) { "Machine" } else { "User" }
$RegPath = if ($IsAdmin) { "System\CurrentControlSet\Control\Session Manager\Environment" } else { "Environment" }
$RegRoot = if ($IsAdmin) { "LocalMachine" } else { "CurrentUser" }

$RegKey = [Microsoft.Win32.Registry]::$RegRoot.OpenSubKey($RegPath, $true)
$CurrentRawPath = $RegKey.GetValue("EXTCOMPLIBS_PATH", "", [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)

$CleanedPathList = $CurrentRawPath -split ';' | Where-Object { 
    -not [string]::IsNullOrWhitespace($_) -and 
    $_ -notlike "*$brotliroot*"
}

$NewRawPath = ($CleanedPathList -join ";").Replace(";;", ";")
$NewRawPath = ($NewRawPath + ";" + $brotlibin + ";").Replace(";;", ";")

Write-Host "[UPDATED] ($TargetScope) Brotli path synced in EXTCOMPLIBS_PATH" -ForegroundColor $ScopeColor

$RegKey.SetValue("EXTCOMPLIBS_PATH", $NewRawPath, [Microsoft.Win32.RegistryValueKind]::ExpandString)
$env:EXTCOMPLIBS_PATH = $NewRawPath

$RegKey.Close()

$env:BROTLI_ROOT = $brotliroot
Write-Host "Brotli Environment Loaded (Version: $brotliversion) (Bin: $brotlibin)" -ForegroundColor Green
Write-Host "BROTLI_ROOT: $env:BROTLI_ROOT" -ForegroundColor Gray
'@  -replace "VALUE_ROOT_PATH", $brotliInstallDir `
    -replace "VALUE_BIN_PATH", $brotliBinPath `
    -replace "VALUE_VERSION", $brotliVersion

        $MachineEnvContent | Out-File -FilePath $brotliMachineEnvScript -Encoding utf8
        Write-Host "Created: $brotliMachineEnvScript" -ForegroundColor Gray
        
        Write-Host ""
        $choice = Read-Host "Do you want to run the Machine Environment script now to persist Brotli changes to the Registry? (y/n)"
        if ($choice -eq 'y' -or $choice -eq 'Y') {
            Write-Host "Executing $brotliMachineEnvScript..." -ForegroundColor Yellow
            try {
                & $brotliMachineEnvScript
            }
            catch {
                Write-Error "Failed to execute the Machine Environment script: $($_.Exception.Message)"
            }
        }
        else {
            Write-Host "Skipped persistent registry update. You can run it later at: $brotliMachineEnvScript" -ForegroundColor Gray
        }
    }

    # --- Return to Start ---
    Pop-Location
    Write-Host "Successfully Done! and returned to: $(Get-Location)" -ForegroundColor DarkGreen
} else {
    Write-Error "brotli library was not found in the $brotliLibDir folder. The CMake build might have failed."
    $brotlitools | ForEach-Object { 
        $globalLinkPath = Join-Path $GlobalBinDir $_
        if (Test-Path $globalLinkPath) {
            Write-Host "Cleaning up dead symlink at $globalLinkPath..." -ForegroundColor Yellow
            Remove-Item $globalLinkPath -Force -ErrorAction SilentlyContinue
        } 
    }
    Pop-Location; return
}
