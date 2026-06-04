# SPDX-FileCopyrightText: Copyright (c) 2026 Navegos. @DevelVitorF. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
# project: buildtools
# file: x64-windows/build-libjpeg.ps1
# created: 2026-05-03
# lastModified: 2026-05-13

param (
    [Parameter(HelpMessage = "Base workspace path", Mandatory = $false)]
    [string]$workspacePath = $null,

    [Parameter(HelpMessage = "libjpeg git repo url", Mandatory = $false)]
    [string]$gitUrl = "https://github.com/libjpeg-turbo/libjpeg-turbo.git",
    
    [Parameter(HelpMessage = "libjpeg git branch to sync from", Mandatory = $false)]
    [string]$gitBranch = "main",

    [Parameter(HelpMessage = "Path for libjpeg library storage", Mandatory = $false)]
    [string]$libjpegInstallDir = "$env:LIBRARIES_PATH\libjpeg",
    
    [Parameter(HelpMessage = "Lib name, if it's building with a different name", Mandatory = $false)]
    [string]$libjpegLibName = "jpeg",
    
    [Parameter(HelpMessage = "ABI version, if it's building with a different version", Mandatory = $false)]
    [string]$libjpegABIVersion = "8",
    
    [Parameter(HelpMessage = "turbojpeg Lib name, if it's building with a different name", Mandatory = $false)]
    [string]$turbojpegLibName = "turbojpeg",
    
    [Parameter(HelpMessage = "Force a full purge of the local libjpeg version before continuing", Mandatory = $false)]
    [switch]$forceCleanup,
    
    [Parameter(HelpMessage = "Add's libjpeg Machine Environment Variables.", Mandatory = $false)]
    [switch]$withMachineEnvironment,

    [Parameter(ValueFromRemainingArguments = $true)]
    $RemainingArgs
)

$libjpegWorkspacePath = $workspacePath
$libjpegGitUrl = $gitUrl
$libjpegGitBranch = $gitBranch
$libjpegForceCleanup = $forceCleanup
$libjpegWithMachineEnvironment = $withMachineEnvironment

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

# Load NASM requirement for libjpeg-turbo optimizations
if ([string]::IsNullOrWhiteSpace($env:BINARY_NASM) -or -not (Test-Path $env:BINARY_NASM)) {
    $nasmEnvScript = Join-Path $EnvironmentDir "env-nasm.ps1"
    if (Test-Path $nasmEnvScript) { . $nasmEnvScript }
    if ([string]::IsNullOrWhiteSpace($env:BINARY_NASM) -or -not (Test-Path $env:BINARY_NASM)) {
        $depnasmEnvScript = Join-Path $PSScriptRoot "dep-nasm.ps1"
        if (Test-Path $depnasmEnvScript) { . $depnasmEnvScript }
        else {
            Write-Error "CRITICAL: Cannot load NASM environment. NASM is missing and $depnasmEnvScript was not found."
            return
        }
    }
}

# --- Dependencies: ---
$RootlibjpegInstallDir = Split-Path -Path $libjpegInstallDir -Parent
$RootlibjpegWorkspacePath = if ([string]::IsNullOrWhitespace($libjpegWorkspacePath)) { Get-Location } else { $libjpegWorkspacePath }

# Load Zlib requirement
if ([string]::IsNullOrWhiteSpace($env:SHARED_LIB_ZLIB) -or -not (Test-Path $env:SHARED_LIB_ZLIB)) {
    $zlibEnvScript = Join-Path $EnvironmentDir "env-zlib.ps1"
    if (Test-Path $zlibEnvScript) { . $zlibEnvScript }
    if ([string]::IsNullOrWhiteSpace($env:SHARED_LIB_ZLIB) -or -not (Test-Path $env:SHARED_LIB_ZLIB)) {
        $zlibBuildScript = Join-Path $PSScriptRoot "build-zlib.ps1"
        if (Test-Path $zlibBuildScript) {
            $zlibInstallDir = Join-Path $RootlibjpegInstallDir "zlib"
            . $zlibBuildScript -workspacePath $RootlibjpegWorkspacePath -zlibInstallDir $zlibInstallDir
        }
        else {
            Write-Error "CRITICAL: Cannot build zlib. zlib is missing and $zlibBuildScript was not found."
            return
        }
    }
}

$RootPath = if ([string]::IsNullOrWhitespace($RootlibjpegWorkspacePath)) { Get-Location } else { $RootlibjpegWorkspacePath }

# --- 6. Path Resolution ---
Push-Location $RootPath

$Source         = Join-Path $RootPath "libjpeg-turbo"
$BuildDirShared = Join-Path $Source "build_shared"
$BuildDirStatic = Join-Path $Source "build_static"
$RepoUrl        = $libjpegGitUrl
$Branch         = $libjpegGitBranch
$CMakeSource    = $Source
$tag_name       = $Branch
$url            = $RepoUrl

$libjpegEnvScript = Join-Path $EnvironmentDir "env-libjpeg.ps1"
$libjpegMachineEnvScript = Join-Path $EnvironmentDir "machine-env-libjpeg.ps1"

# --- 1. Cleanup Mechanism ---
function Invoke-libjpegVersionPurge {
    param ([string]$InstallPath)
    Write-Host "--- Initiating libjpeg Purge ---" -ForegroundColor Cyan

    if ($libjpegWithMachineEnvironment) {
        $libjpegCleanMachineEnvScript = Join-Path $env:TEMP "clean-machine-env-libjpeg.ps1"

        # Generating Clean Machine Environment wich removes the persist registry machine Environment
        $CleanMachineEnvContent = @'
# libjpeg Clean Machine Environment Setup

# --- 0. Self-Elevation Logic ---
$IsAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$ScopeColor = "Cyan"

if (-not $IsAdmin) {
    Write-Host "Elevation required to clean libjpeg system variables. Relaunching as Administrator..." -ForegroundColor Yellow
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

$libjpegroot = "VALUE_ROOT_PATH"

$TargetScope = if ($IsAdmin) { "Machine" } else { "User" }
$RegPath = if ($IsAdmin) { "System\CurrentControlSet\Control\Session Manager\Environment" } else { "Environment" }
$RegRoot = if ($IsAdmin) { "LocalMachine" } else { "CurrentUser" }

# 1. Registry Cleanup (EXTCOMPLIBS_PATH)
$RegKey = [Microsoft.Win32.Registry]::$RegRoot.OpenSubKey($RegPath, $true)

# Open the registry key directly to read the RAW (unexpanded) string
$RawPath = $RegKey.GetValue("EXTCOMPLIBS_PATH", "", [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)

# Cleanup: Remove empty strings, any path containing $libjpegroot,
$CleanPath = ($RawPath -split ';' | Where-Object { $_ -notlike "*$libjpegroot*" }) -join ";"

# Save as ExpandString
$RegKey.SetValue("EXTCOMPLIBS_PATH", $CleanPath, [Microsoft.Win32.RegistryValueKind]::ExpandString)
$env:EXTCOMPLIBS_PATH = $CleanPath

$RegKey.Close()

Write-Host "[REMOVED] ($TargetScope) all '*$libjpegroot*' removed from EXTCOMPLIBS_PATH" -ForegroundColor $ScopeColor
'@  -replace "VALUE_ROOT_PATH", $InstallPath

        $CleanMachineEnvContent | Out-File -FilePath $libjpegCleanMachineEnvScript -Encoding utf8
        Write-Host "Created: $libjpegCleanMachineEnvScript" -ForegroundColor Gray
        
        # --- Interaction: Prompt to remove persistent changes ---
        Write-Host ""
        $choice = Read-Host "Administrator rights required to Clean Machine Environment libjpeg changes? (y/n)"
        if ($choice -eq 'y' -or $choice -eq 'Y') {
            Write-Host "Executing $libjpegCleanMachineEnvScript..." -ForegroundColor Yellow
            try {
                # Start the generated script. It handles its own elevation logic.
                & $libjpegCleanMachineEnvScript
            }
            catch {
                Write-Error "Failed to execute the Clean Machine Environment script: $($_.Exception.Message)"
                Pop-Location; return
            }
        }
        else {
            Write-Error "Skipped Clean Machine Environment libjpeg changes."
            Pop-Location; return
        }

        # Cleanup
        Remove-Item $libjpegCleanMachineEnvScript -Recurse -Force -ErrorAction SilentlyContinue
    }
    
    # 2. Filesystem Clean (Requires checking for locked files)
    # delete everithing we create don't fail later
    if (Test-Path $libjpegEnvScript) {
        Write-Host "  [DELETING] $libjpegEnvScript" -ForegroundColor Yellow
        Remove-Item $libjpegEnvScript -Recurse -Force -ErrorAction SilentlyContinue
    }
    if (Test-Path $libjpegMachineEnvScript) {
        Write-Host "  [DELETING] $libjpegMachineEnvScript" -ForegroundColor Yellow
        Remove-Item $libjpegMachineEnvScript -Recurse -Force -ErrorAction SilentlyContinue
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
    Get-ChildItem Env:\LIBJPEG_* | ForEach-Object { Remove-Item Env:\$($_.Name) -ErrorAction SilentlyContinue }
    Get-ChildItem Env:\BINARY_LIB_JPEG* | ForEach-Object { Remove-Item Env:\$($_.Name) -ErrorAction SilentlyContinue }
    Get-ChildItem Env:\SHARED_LIB_JPEG* | ForEach-Object { Remove-Item Env:\$($_.Name) -ErrorAction SilentlyContinue }
    Get-ChildItem Env:\STATIC_LIB_JPEG* | ForEach-Object { Remove-Item Env:\$($_.Name) -ErrorAction SilentlyContinue }
    
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
    
    Write-Host "--- LIBJPEG Purge Complete ---" -ForegroundColor Green
}

if ($libjpegForceCleanup) { Invoke-libjpegVersionPurge -InstallPath $libjpegInstallDir }

if (Test-Path $Source) {
    Write-Host "Syncing libjpeg ($Branch) at $Source..." -ForegroundColor Cyan
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
    Write-Host "Cloning libjpeg ($Branch) into $Source..." -ForegroundColor Cyan
    git clone --recurse-submodules $RepoUrl $Source -b $Branch
    if ($LASTEXITCODE -ne 0) { Write-Error "Git clone failed."; Pop-Location; return }
    Set-Location $Source
    $tagCommit = (& git rev-parse --verify HEAD).Trim()
}


# --- 8. Clean Final Destination ---
if (Test-Path $libjpegInstallDir) {
    Write-Host "Wiping existing installation..." -ForegroundColor Yellow
    Remove-Item $libjpegInstallDir -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "[INSTALL] Creating fresh directory: $libjpegInstallDir" -ForegroundColor Cyan
New-Item -Path $libjpegInstallDir -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null

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
    "-DMSVC_LIKE=1",
    "-DREQUIRE_SIMD=ON",
    "-DWITH_ARITH_DEC=ON",
    "-DWITH_ARITH_ENC=ON",
    "-DWITH_JPEG7=ON",
    "-DWITH_JPEG8=ON",
    "-DWITH_SIMD=ON",
    "-DWITH_TURBOJPEG=ON",
    "-DWITH_TOOLS=OFF",
    "-DWITH_TESTS=OFF",
    "-DWITH_SYSTEM_ZLIB=OFF"
)

# --- STAGE 1: Build Static Libraries ---
Write-Host "Building Static..." -ForegroundColor Cyan
cmake $CommonCmakeArgs `
    -S "$CMakeSource" `
    -B "$BuildDirStatic" `
    -DCMAKE_INSTALL_PREFIX="$libjpegInstallDir" `
    -DENABLE_SHARED=OFF `
    -DENABLE_STATIC=ON `
    -DCMAKE_C_FLAGS="-Wno-deprecated-declarations -D_CRT_SECURE_NO_WARNINGS=1" `
    -DCMAKE_CXX_FLAGS="-Wno-deprecated-declarations -D_CRT_SECURE_NO_WARNINGS=1" `
    --no-warn-unused-cli
    
if ($LASTEXITCODE -ne 0) { Write-Error "libjpeg CMake Static configuration failed."; Pop-Location; return }

Write-Host "Building and Installing static lib to $libjpegInstallDir..." -ForegroundColor Green
cmake --build "$BuildDirStatic" --target install --config Release --parallel

if ($LASTEXITCODE -ne 0) { Write-Error "libjpeg Static Build failed with exit code $LASTEXITCODE"; Pop-Location; return }

# Rename static lib to libjpeg_static.lib to avoid collision
Write-Host "Applying '_static' suffix to static libs..." -ForegroundColor Gray
Get-ChildItem -Path "$libjpegInstallDir\lib\*.lib" | ForEach-Object {
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
    -DCMAKE_INSTALL_PREFIX="$libjpegInstallDir" `
    -DENABLE_SHARED=ON `
    -DENABLE_STATIC=OFF `
    -DCMAKE_C_FLAGS="-Wno-deprecated-declarations -D_CRT_SECURE_NO_WARNINGS=1" `
    -DCMAKE_CXX_FLAGS="-Wno-deprecated-declarations -D_CRT_SECURE_NO_WARNINGS=1" `
    --no-warn-unused-cli
    
if ($LASTEXITCODE -ne 0) { Write-Error "libjpeg CMake Shared (DLL) configuration failed."; Pop-Location; return }

Write-Host "Building and Installing dynamic lib to $libjpegInstallDir..." -ForegroundColor Green
cmake --build "$BuildDirShared" --target install --config Release --parallel

if ($LASTEXITCODE -ne 0) { Write-Error "libjpeg Shared Build failed with exit code $LASTEXITCODE"; Pop-Location; return }

Write-Host "Successfully built and installed libjpeg to $libjpegInstallDir!" -ForegroundColor Green

# Cleanup temporary build debris
Remove-Item $BuildDirShared -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item $BuildDirStatic -Recurse -Force -ErrorAction SilentlyContinue

# Generate Environment Helper with Clean Paths
$libjpegInstallDir = $libjpegInstallDir.TrimEnd('\')
$libjpegIncludeDir = Join-Path $libjpegInstallDir "include"
$libjpegLibDir = Join-Path $libjpegInstallDir "lib"
$libjpegBinPath = Join-Path $libjpegInstallDir "bin"
$libjpegCMakePath = $libjpegInstallDir.Replace('\', '/')

$StaticLib = Join-Path $libjpegLibDir ("$libjpegLibName" + "_static.lib")
$SharedLib = Join-Path $libjpegLibDir "$libjpegLibName.lib"
$BinaryLib = Join-Path $libjpegBinPath ("$libjpegLibName" + "$libjpegABIVersion" + ".dll")
$turbojpegStaticLib = Join-Path $libjpegLibDir ("$turbojpegLibName" + "_static.lib")
$turbojpegSharedLib = Join-Path $libjpegLibDir "$turbojpegLibName.lib"
$turbojpegBinaryLib = Join-Path $libjpegBinPath ("$turbojpegLibName.dll")
$versionFile = Join-Path $libjpegInstallDir "version.json"

# libjpeg-turbo creates jpeg-static.lib
#if (-not (Test-Path $StaticLib)) { $StaticLib = Join-Path $libjpegLibDir ("$libjpegLibName" + "-static.lib") }

if ((Test-Path $StaticLib) -or (Test-Path $SharedLib) -or (Test-Path $BinaryLib)) {
    $localVersion = "0.0.0"
    $rawVersion = $Branch
    $binaryversion = "0"
    $turbojpegbinaryversion = "0"

    $cmakeFile = Join-Path $Source "CMakeLists.txt"
    if (Test-Path $cmakeFile) {
        $cmakeContent = Get-Content $cmakeFile -Raw
        $versionMatch = [regex]::Match($cmakeContent, '(?i)set\s*\(\s*VERSION\s+([\d\.]+)\s*\)')

        if ($versionMatch.Success) {
            $localVersion = $versionMatch.Groups[1].Value
            $rawVersion = $localVersion
            $binaryversion = $libjpegABIVersion
            $turbojpegbinaryversion = ([version]$localVersion).Major
            Write-Host "[VERSION] Detected libjpeg: $localVersion" -ForegroundColor Cyan
        }
    }

    # Save new version state
    $libjpegVersion = $localVersion
    $versionInfo = @{
        url        = $url;
        tag_name   = $tag_name;
        commit     = $tagCommit;
        version    = $localVersion;
        rawversion = $rawVersion;
        abiversion = $binaryversion;
        soversion  = $binaryversion;
        turbojpegabiversion = $turbojpegbinaryversion;
        turbojpegsoversion     = $turbojpegbinaryversion;
        date       = (Get-Date).ToString("yyyy-MM-dd");
        updated_at = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssZ");
        type       = "source_build";
    }
    $versionInfo | ConvertTo-Json | Out-File -FilePath $versionFile -Encoding utf8 -Force
    
    # --- 10. Create Environment Helper ---
    Write-Host "Generating environment helper script..." -ForegroundColor Cyan
    $EnvContent = @'
# LIBJPEG Environment Setup
$libjpegroot = "VALUE_ROOT_PATH"
$libjpeginclude = "VALUE_INCLUDE_PATH"
$libjpeglibrary = "VALUE_LIB_PATH"
$libjpegbin = "VALUE_BIN_PATH"
$libjpegversion = "VALUE_VERSION"
$libjpegabiversion = "VALUE_ABI_VERSION"
$libjpegsoversion = "VALUE_SO_VERSION"
$libjpegbinary = "VALUE_BINARY"
$libjpegshared = "VALUE_SHARED"
$libjpegstatic = "VALUE_STATIC"
$libjpeglibname = "VALUE_LIB_NAME"
$turbojpegversion = "VALUE_VERSION"
$turbojpegabiversion = "VALUE_TURBOJPEG_ABI_VERSION"
$turbojpegsoversion = "VALUE_TURBOJPEG_SO_VERSION"
$turbojpegbinary = "VALUE_TURBOJPEG_BINARY"
$turbojpegshared = "VALUE_TURBOJPEG_SHARED"
$turbojpegstatic = "VALUE_TURBOJPEG_STATIC"
$turbojpeglibname = "VALUE_TURBOJPEG_LIB_NAME"
$libjpegcmakepath = "VALUE_CMAKE_PATH"
$env:LIBJPEG_PATH = $libjpegroot
$env:LIBJPEG_ROOT = $libjpegroot
$env:LIBJPEG_BIN = $libjpegbin
$env:LIBJPEG_INCLUDE_DIR = $libjpeginclude
$env:LIBJPEG_LIBRARY_DIR = $libjpeglibrary
$env:BINARY_LIB_JPEG = $libjpegbinary
$env:SHARED_LIB_JPEG = $libjpegshared
$env:STATIC_LIB_JPEG = $libjpegstatic
$env:LIBJPEG_LIB_NAME = $libjpeglibname
$env:LIBJPEG_VERSION = $libjpegversion
$env:LIBJPEG_MAJOR = ([version]$libjpegversion).Major
$env:LIBJPEG_MINOR = ([version]$libjpegversion).Minor
$env:LIBJPEG_PATCH = ([version]$libjpegversion).Patch
$env:LIBJPEG_ABI_VERSION = $libjpegabiversion
$env:LIBJPEG_SO_VERSION = $libjpegsoversion
$env:BINARY_LIB_TURBOJPEG = $turbojpegbinary
$env:SHARED_LIB_TURBOJPEG = $turbojpegshared
$env:STATIC_LIB_TURBOJPEG = $turbojpegstatic
$env:TURBOJPEG_LIB_NAME = $turbojpeglibname
$env:TURBOJPEG_VERSION = $turbojpegversion
$env:TURBOJPEG_MAJOR = ([version]$turbojpegversion).Major
$env:TURBOJPEG_MINOR = ([version]$turbojpegversion).Minor
$env:TURBOJPEG_PATCH = ([version]$turbojpegversion).Patch
$env:TURBOJPEG_ABI_VERSION = $turbojpegabiversion
$env:TURBOJPEG_SO_VERSION = $turbojpegsoversion
if ($env:CMAKE_PREFIX_PATH -notlike "*$libjpegcmakepath*") { $env:CMAKE_PREFIX_PATH = $libjpegcmakepath + ";" + $env:CMAKE_PREFIX_PATH; $env:CMAKE_PREFIX_PATH = ($env:CMAKE_PREFIX_PATH).Replace(";;", ";") }
if ($env:INCLUDE -notlike "*$libjpeginclude*") { $env:INCLUDE = $libjpeginclude + ";" + $env:INCLUDE; $env:INCLUDE = ($env:INCLUDE).Replace(";;", ";") }
if ($env:LIB -notlike "*$libjpeglibrary*") { $env:LIB = $libjpeglibrary + ";" + $env:LIB; $env:LIB = ($env:LIB).Replace(";;", ";") }
if ($env:PATH -notlike "*$libjpegbin*") { $env:PATH = $libjpegbin + ";" + $env:PATH; $env:PATH = ($env:PATH).Replace(";;", ";") }
Write-Host "libjpeg Environment Loaded (Version: $libjpegversion) (Bin: $libjpegbin)" -ForegroundColor Green
Write-Host "LIBJPEG_ROOT: $env:LIBJPEG_ROOT" -ForegroundColor Gray
'@  -replace "VALUE_ROOT_PATH", $libjpegInstallDir `
    -replace "VALUE_INCLUDE_PATH", $libjpegIncludeDir `
    -replace "VALUE_LIB_PATH", $libjpegLibDir `
    -replace "VALUE_BIN_PATH", $libjpegBinPath `
    -replace "VALUE_VERSION", $libjpegVersion `
    -replace "VALUE_ABI_VERSION", $binaryversion `
    -replace "VALUE_SO_VERSION", $binaryversion `
    -replace "VALUE_SHARED", $SharedLib `
    -replace "VALUE_BINARY", $BinaryLib `
    -replace "VALUE_STATIC", $StaticLib `
    -replace "VALUE_LIB_NAME", $libjpegLibName `
    -replace "VALUE_TURBOJPEG_ABI_VERSION", $turbojpegbinaryversion `
    -replace "VALUE_TURBOJPEG_SO_VERSION", $turbojpegbinaryversion `
    -replace "VALUE_TURBOJPEG_SHARED", $turbojpegSharedLib `
    -replace "VALUE_TURBOJPEG_BINARY", $turbojpegBinaryLib `
    -replace "VALUE_TURBOJPEG_STATIC", $turbojpegStaticLib `
    -replace "VALUE_TURBOJPEG_LIB_NAME", $turbojpegLibName `
    -replace "VALUE_CMAKE_PATH", $libjpegCMakePath

    $EnvContent | Out-File -FilePath $libjpegEnvScript -Encoding utf8
    Write-Host "Created: $libjpegEnvScript" -ForegroundColor Gray

    # Update Current Session
    if (Test-Path $libjpegEnvScript) { . $libjpegEnvScript } else {
        Write-Error "libjpeg build install finished but $libjpegEnvScript was not created."
        Pop-Location; return
    }
    
    if ($libjpegWithMachineEnvironment)
    {
        $MachineEnvContent = @'
# libjpeg Machine Environment Setup
$IsAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$ScopeColor = "Cyan"

if (-not $IsAdmin) {
    Write-Host "Elevation required to set libjpe system variables. Relaunching as Administrator..." -ForegroundColor Yellow
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

$libjpegroot = "VALUE_ROOT_PATH"
$libjpegbin = "VALUE_BIN_PATH"
$libjpegversion = "VALUE_VERSION"

$TargetScope = if ($IsAdmin) { "Machine" } else { "User" }
$RegPath = if ($IsAdmin) { "System\CurrentControlSet\Control\Session Manager\Environment" } else { "Environment" }
$RegRoot = if ($IsAdmin) { "LocalMachine" } else { "CurrentUser" }

# Open the registry key once
$RegKey = [Microsoft.Win32.Registry]::$RegRoot.OpenSubKey($RegPath, $true)

# Open the registry key directly to read the RAW (unexpanded) string
$CurrentRawPath = $RegKey.GetValue("EXTCOMPLIBS_PATH", "", [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)

$CleanedPathList = $CurrentRawPath -split ';' | Where-Object { 
    -not [string]::IsNullOrWhitespace($_) -and 
    $_ -notlike "*$libjperoot*"
}

$NewRawPath = ($CleanedPathList -join ";").Replace(";;", ";")

$TargetPath = $libjpebin

# Rebuild
$NewRawPath = ($NewRawPath + ";" + $TargetPath + ";").Replace(";;", ";")
Write-Host "[UPDATED] ($TargetScope) '$libjpebin' synced in EXTCOMPLIBS_PATH" -ForegroundColor $ScopeColor

# Save as ExpandString
$RegKey.SetValue("EXTCOMPLIBS_PATH", $NewRawPath, [Microsoft.Win32.RegistryValueKind]::ExpandString)
$env:EXTCOMPLIBS_PATH = $NewRawPath

$RegKey.Close()

$env:LIBJPEG_ROOT = $libjpegroot
Write-Host "libjpeg Environment Loaded (Version: $libjpegversion) (Bin: $libjpegbin)" -ForegroundColor Green
Write-Host "LIBJPEG_ROOT: $env:LIBJPEG_ROOT" -ForegroundColor Gray
'@  -replace "VALUE_ROOT_PATH", $libjpegInstallDir `
    -replace "VALUE_BIN_PATH", $libjpegBinPath `
    -replace "VALUE_VERSION", $libjpegVersion

        $MachineEnvContent | Out-File -FilePath $libjpegMachineEnvScript -Encoding utf8
        Write-Host "Created: $libjpegMachineEnvScript" -ForegroundColor Gray
        
        # --- Interaction: Prompt to apply persistent changes ---
        Write-Host ""
        $choice = Read-Host "Do you want to run the Machine Environment script now to persist libjpe changes to the Registry? (y/n)"
        if ($choice -eq 'y' -or $choice -eq 'Y') {
            Write-Host "Executing $libjpegMachineEnvScript..." -ForegroundColor Yellow
            try {
                # Start the generated script. It handles its own elevation logic.
                & $libjpegMachineEnvScript
            }
            catch {
                Write-Error "Failed to execute the Machine Environment script: $($_.Exception.Message)"
            }
        }
        else {
            Write-Host "Skipped persistent registry update. You can run it later at: $libjpegMachineEnvScript" -ForegroundColor Gray
        }
    }
    
    # --- Return to Start ---
    Pop-Location
    Write-Host "Successfully Done! and returned to: $(Get-Location)" -ForegroundColor DarkGreen
} else {
    Write-Error "libjpeg library was not found in the $libjpegLibDir folder."
    Pop-Location; return
}
