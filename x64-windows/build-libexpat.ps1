# SPDX-FileCopyrightText: Copyright (c) 2026 Navegos. @DevelVitorF. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
# project: buildtools
# file: x64-windows/build-libexpat.ps1
# created: 2026-04-15
# lastModified: 2026-04-26

param (
    [Parameter(HelpMessage = "Base workspace path", Mandatory = $false)]
    [string]$workspacePath = $null,

    [Parameter(HelpMessage = "libexpat (xz) git repo url", Mandatory = $false)]
    [string]$gitUrl = "https://github.com/libexpat/libexpat.git",
    
    [Parameter(HelpMessage = "libexpat git branch to sync from", Mandatory = $false)]
    [string]$gitBranch = "master",

    [Parameter(HelpMessage = "Path for libexpat library storage", Mandatory = $false)]
    [string]$libexpatInstallDir = "$env:LIBRARIES_PATH\libexpat",
    
    [Parameter(HelpMessage = "Lib name, if it's building with a different name (fixit by changing it's default name beforehand)", Mandatory = $false)]
    [string]$libexpatLibName = "libexpat",
    
    [Parameter(HelpMessage = "Force a full purge of the local libexpat version before continuing", Mandatory = $false)]
    [switch]$forceCleanup,
    
    [Parameter(HelpMessage = "Add's libexpat Machine Environment Variables. Requires Machine Administrator Rights.", Mandatory = $false)]
    [switch]$withMachineEnvironment
)

# Capture parameters
$libexpatWorkspacePath = $workspacePath
$libexpatGitUrl = $gitUrl
$libexpatGitBranch = $gitBranch
$libexpatForceCleanup = $forceCleanup
$libexpatWithMachineEnvironment = $withMachineEnvironment

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

# Load pkgconf requirement
if ([string]::IsNullOrWhitespace($env:BINARY_PKGCONF) -or -not (Test-Path $env:BINARY_PKGCONF)) {
    $pkgconfEnvScript = Join-Path $EnvironmentDir "env-pkgconf.ps1"
    if (Test-Path $pkgconfEnvScript) { . $pkgconfEnvScript }
    if ([string]::IsNullOrWhitespace($env:BINARY_PKGCONF) -or -not (Test-Path $env:BINARY_PKGCONF)) {
        $deppkgconfEnvScript = Join-Path $PSScriptRoot "dep-pkgconf.ps1"
        if (Test-Path $deppkgconfEnvScript) { . $deppkgconfEnvScript }
        else {
            Write-Error "CRITICAL: Cannot load pkgconf environment. pkgconf is missing and $pkgconfEnvScript was not found."
            return
        }
    }
}

$RootPath = if ([string]::IsNullOrWhitespace($libexpatWorkspacePath)) { Get-Location } else { $libexpatWorkspacePath }

# --- 6. Path Resolution ---
Push-Location $RootPath

$Source         = Join-Path $RootPath "libexpat"
$BuildDirShared = Join-Path $Source "build_shared"
$BuildDirStatic = Join-Path $Source "build_static"
$RepoUrl        = $libexpatGitUrl
$Branch         = $libexpatGitBranch
$CMakeSource    = Join-Path $Source "expat"
$tag_name       = $Branch
$url            = $RepoUrl

$libexpatMachineEnvScript = Join-Path $EnvironmentDir "machine-env-libexpat.ps1"
$libexpatEnvScript = Join-Path $EnvironmentDir "env-libexpat.ps1"

# --- 1. Cleanup Mechanism ---
function Invoke-libexpatVersionPurge {
    param ([string]$InstallPath)
    Write-Host "--- Initiating libexpat Purge ---" -ForegroundColor Cyan

    if ($libexpatWithMachineEnvironment) {
        $libexpatCleanMachineEnvScript = Join-Path $env:TEMP "clean-machine-env-libexpat.ps1"

        # Generating Clean Machine Environment wich removes the persist registry machine Environment
        $CleanMachineEnvContent = @'
# libexpat Clean Machine Environment Setup

# --- 0. Self-Elevation Logic ---
$IsAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$ScopeColor = "Cyan"

if (-not $IsAdmin) {
    Write-Host "Elevation required to clean libexpat system variables. Relaunching as Administrator..." -ForegroundColor Yellow
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

$libexpatroot = "VALUE_ROOT_PATH"

$TargetScope = if ($IsAdmin) { "Machine" } else { "User" }
$RegPath = if ($IsAdmin) { "System\CurrentControlSet\Control\Session Manager\Environment" } else { "Environment" }
$RegRoot = if ($IsAdmin) { "LocalMachine" } else { "CurrentUser" }

# 1. Registry Cleanup (EXTCOMPLIBS_PATH)
$RegKey = [Microsoft.Win32.Registry]::$RegRoot.OpenSubKey($RegPath, $true)

# Open the registry key directly to read the RAW (unexpanded) string
$RawPath = $RegKey.GetValue("EXTCOMPLIBS_PATH", "", [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)

# Cleanup: Remove empty strings, any path containing $libexpatroot,
$CleanPath = ($RawPath -split ';' | Where-Object { $_ -notlike "*$libexpatroot*" }) -join ";"

# Save as ExpandString
$RegKey.SetValue("EXTCOMPLIBS_PATH", $CleanPath, [Microsoft.Win32.RegistryValueKind]::ExpandString)
$env:EXTCOMPLIBS_PATH = $CleanPath

$RegKey.Close()

Write-Host "[REMOVED] ($TargetScope) all '*$libexpatroot*' removed from EXTCOMPLIBS_PATH" -ForegroundColor $ScopeColor
'@  -replace "VALUE_ROOT_PATH", $InstallPath

        $CleanMachineEnvContent | Out-File -FilePath $libexpatCleanMachineEnvScript -Encoding utf8
        Write-Host "Created: $libexpatCleanMachineEnvScript" -ForegroundColor Gray
        
        # --- Interaction: Prompt to remove persistent changes ---
        Write-Host ""
        $choice = Read-Host "Administrator rights required to Clean Machine Environment libexpat changes? (y/n)"
        if ($choice -eq 'y' -or $choice -eq 'Y') {
            Write-Host "Executing $libexpatCleanMachineEnvScript..." -ForegroundColor Yellow
            try {
                # Start the generated script. It handles its own elevation logic.
                & $libexpatCleanMachineEnvScript
            }
            catch {
                Write-Error "Failed to execute the Clean Machine Environment script: $($_.Exception.Message)"
                Pop-Location; return
            }
        }
        else {
            Write-Error "Skipped Clean Machine Environment libexpat changes."
            Pop-Location; return
        }

        # Cleanup
        Remove-Item $libexpatCleanMachineEnvScript -Recurse -Force -ErrorAction SilentlyContinue
    }

    # 2. Filesystem Clean (Requires checking for locked files)
    # delete everithing we create don't fail later
    if (Test-Path $libexpatEnvScript) {
        Write-Host "  [DELETING] $libexpatEnvScript" -ForegroundColor Yellow
        Remove-Item $libexpatEnvScript -Recurse -Force -ErrorAction SilentlyContinue
    }
    if (Test-Path $libexpatMachineEnvScript) {
        Write-Host "  [DELETING] $libexpatMachineEnvScript" -ForegroundColor Yellow
        Remove-Item $libexpatMachineEnvScript -Recurse -Force -ErrorAction SilentlyContinue
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
    Get-ChildItem Env:\LIBEXPAT_PATH* | Remove-Item -ErrorAction SilentlyContinue
    Get-ChildItem Env:\LIBEXPAT_ROOT* | Remove-Item -ErrorAction SilentlyContinue
    Get-ChildItem Env:\LIBEXPAT_BIN* | Remove-Item -ErrorAction SilentlyContinue
    Get-ChildItem Env:\LIBEXPAT_INCLUDE_DIR* | Remove-Item -ErrorAction SilentlyContinue
    Get-ChildItem Env:\LIBEXPAT_LIBRARY_DIR* | Remove-Item -ErrorAction SilentlyContinue
    Get-ChildItem Env:\BINARY_LIB_EXPAT* | Remove-Item -ErrorAction SilentlyContinue
    Get-ChildItem Env:\SHARED_LIB_EXPAT* | Remove-Item -ErrorAction SilentlyContinue
    Get-ChildItem Env:\STATIC_LIB_EXPAT* | Remove-Item -ErrorAction SilentlyContinue
    Get-ChildItem Env:\LIBEXPAT_LIB_NAME* | Remove-Item -ErrorAction SilentlyContinue
    Get-ChildItem Env:\LIBEXPAT_VERSION* | Remove-Item -ErrorAction SilentlyContinue
    Get-ChildItem Env:\LIBEXPAT_MAJOR* | Remove-Item -ErrorAction SilentlyContinue
    Get-ChildItem Env:\LIBEXPAT_MINOR* | Remove-Item -ErrorAction SilentlyContinue
    Get-ChildItem Env:\LIBEXPAT_PATCH* | Remove-Item -ErrorAction SilentlyContinue
    Get-ChildItem Env:\LIBEXPAT_ABI_VERSION* | Remove-Item -ErrorAction SilentlyContinue
    Get-ChildItem Env:\LIBEXPAT_SO_VERSION* | Remove-Item -ErrorAction SilentlyContinue
    
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
    
    Write-Host "--- LIBEXPAT Purge Complete ---" -ForegroundColor Green
}

if ($libexpatForceCleanup) {
    Invoke-libexpatVersionPurge -InstallPath $libexpatInstallDir
}

# --- 7. Source Management ---
if (Test-Path $Source) {
    Write-Host "Syncing LIBEXPAT ($Branch) at $Source..." -ForegroundColor Cyan
    Set-Location $Source
    git fetch --all
    git reset --hard "origin/$Branch"
    git pull --recurse-submodules --force
    $tagCommit = (& git rev-parse --verify HEAD).Trim()
}
else {
    Write-Host "Cloning LIBEXPAT ($Branch) into $Source..." -ForegroundColor Cyan
    git clone --recurse-submodules $RepoUrl $Source -b $Branch
    Set-Location $Source
    $tagCommit = (& git rev-parse --verify HEAD).Trim()
}

# --- Apply Patch some symbols are not exported and build fails linking shared lib ---
<# $PatchFile = Join-Path $PSScriptRoot "patch\libexpat_cmake.patch"
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
    }
    else {
        # The check failed, which usually means the repo has changed 
        # or the patch was already partially applied (unlikely after git reset --hard)
        Write-Warning "[PATCH] Patch verification failed. The source may have changed upstream."
        Write-Host "Check the patch file for conflicts or update the patch." -ForegroundColor Yellow
        
        # In a strict build-chain, you might want to stop here:
        Pop-Location; return
    }
} #>

# --- 8. Clean Final Destination ---
if (Test-Path $libexpatInstallDir) {
    Write-Host "Wiping existing installation..." -ForegroundColor Yellow
    Remove-Item $libexpatInstallDir -Recurse -Force -ErrorAction SilentlyContinue
}
New-Item -Path $libexpatInstallDir -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null

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
    "-DEXPAT_BUILD_EXAMPLES=OFF",
    "-DEXPAT_BUILD_TESTS=OFF",
    "-DEXPAT_BUILD_DOCS=OFF",
    "-DEXPAT_BUILD_FUZZERS=OFF",
    "-DEXPAT_BUILD_PKGCONFIG=ON",
    "-DEXPAT_OSSFUZZ_BUILD=OFF",
    "-DEXPAT_ENABLE_INSTALL=ON",
    "-DEXPAT_CONTEXT_BYTES=1024",
    "-DEXPAT_SYMBOL_VERSIONING=OFF",
    "-DEXPAT_DTD=ON",
    "-DEXPAT_GE=ON",
    "-DEXPAT_NS=ON",
    "-DEXPAT_WARNINGS_AS_ERRORS=OFF",
    "-DEXPAT_CHAR_TYPE=char",
    "-DEXPAT_ATTR_INFO=OFF",
    "-DEXPAT_LARGE_SIZE=ON",
    "-DEXPAT_MIN_SIZE=OFF",
    "-DEXPAT_MSVC_STATIC_CRT=OFF",
    "-D_EXPAT_M32=OFF"
)

# --- 9. STAGE 1: Build Static Libraries ---
Write-Host "Building LIBEXPAT Static (libexpats.lib)..." -ForegroundColor Cyan
cmake $CommonCmakeArgs `
    -S "$CMakeSource" `
    -B "$BuildDirStatic" `
    -DCMAKE_INSTALL_PREFIX="$libexpatInstallDir" `
    -DBUILD_SHARED_LIBS=OFF `
    -DEXPAT_BUILD_TOOLS=OFF `
    -DCMAKE_CXX_STANDARD=20 `
    -DCMAKE_C_STANDARD=17 `
    -DCMAKE_C_FLAGS="-Wno-deprecated-declarations -D_CRT_SECURE_NO_WARNINGS=1" `
    -DCMAKE_CXX_FLAGS="-Wno-deprecated-declarations -D_CRT_SECURE_NO_WARNINGS=1" `
    --no-warn-unused-cli

if ($LASTEXITCODE -ne 0) { Write-Error "libexpat CMake Static (libexpats.lib) configuration failed."; Pop-Location; return }

Write-Host "Building and Installing static lib to $libexpatInstallDir..." -ForegroundColor Green
cmake --build "$BuildDirStatic" --target install --config Release --parallel

if ($LASTEXITCODE -ne 0) { Write-Error "libexpat Static Build failed with exit code $LASTEXITCODE"; Pop-Location; return }

# Rename static lib to libexpats.lib to avoid collision
$StaticLibPath = Join-Path $libexpatInstallDir "lib/libexpat.lib"
$NewStaticName = Join-Path $libexpatInstallDir "lib/libexpats.lib"
if (Test-Path $StaticLibPath) {
    Move-Item -Path $StaticLibPath -Destination $NewStaticName -Force -ErrorAction SilentlyContinue
    Write-Host "Static library renamed to libexpats.lib" -ForegroundColor Gray
}

# --- 10. STAGE 2: Build Shared Libraries ---
Write-Host "Building LIBEXPAT Shared (DLL)..." -ForegroundColor Cyan
cmake $CommonCmakeArgs `
    -S "$CMakeSource" `
    -B "$BuildDirShared" `
    -DCMAKE_INSTALL_PREFIX="$libexpatInstallDir" `
    -DBUILD_SHARED_LIBS=ON `
    -DEXPAT_SHARED_LIBS=ON `
    -DEXPAT_BUILD_TOOLS=ON `
    -DCMAKE_CXX_STANDARD=20 `
    -DCMAKE_C_STANDARD=17 `
    -DCMAKE_C_FLAGS="-Wno-deprecated-declarations -D_CRT_SECURE_NO_WARNINGS=1" `
    -DCMAKE_CXX_FLAGS="-Wno-deprecated-declarations -D_CRT_SECURE_NO_WARNINGS=1" `
    --no-warn-unused-cli

if ($LASTEXITCODE -ne 0) { Write-Error "libexpat CMake Shared (DLL) configuration failed."; Pop-Location; return }

Write-Host "Building and Installing dynamic lib to $libexpatInstallDir..." -ForegroundColor Green
cmake --build "$BuildDirShared" --target install --config Release --parallel

if ($LASTEXITCODE -ne 0) { Write-Error "libexpat Shared Build failed with exit code $LASTEXITCODE"; Pop-Location; return }

Write-Host "Successfully built and installed libexpat to $libexpatInstallDir!" -ForegroundColor Green

# Cleanup temporary build debris
Remove-Item $BuildDirShared -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item $BuildDirStatic -Recurse -Force -ErrorAction SilentlyContinue

# Generate Environment Helper with Clean Paths
$libexpatInstallDir = $libexpatInstallDir.TrimEnd('\')
$libexpatIncludeDir = Join-Path $libexpatInstallDir "include"
$libexpatLibDir = Join-Path $libexpatInstallDir "lib"
$libexpatBinPath = Join-Path $libexpatInstallDir "bin"
$libexpatCMakePath = $libexpatInstallDir.Replace('\', '/')

$StaticLib = Join-Path $libexpatLibDir ("$libexpatLibName" + "static.lib")
$SharedLib = Join-Path $libexpatLibDir "$libexpatLibName.lib"
$BinaryLib = Join-Path $libexpatBinPath "$libexpatLibName.dll"
$versionFile = Join-Path $libexpatInstallDir "version.json"

# Fallback check for "z.lib" / "zs.lib" naming convention
if (-not (Test-Path $StaticLib)) { $StaticLib = Join-Path $libexpatLibDir ("$libexpatLibName" + "s.lib") }
#if (-not (Test-Path $SharedLib)) { $SharedLib = Join-Path $libexpatLibDir "libexpat.lib" }
#if (-not (Test-Path $BinaryLib)) { $BinaryLib = Join-Path $libexpatBinPath "libexpat.dll" }

if ((Test-Path $StaticLib) -or (Test-Path $SharedLib) -or (Test-Path $BinaryLib)) {
    $libexpatHeader = Join-Path $libexpatIncludeDir "expat.h"
    if (-not (Test-Path $libexpatHeader)) { $libexpatHeader = Join-Path $Source "expat\lib\expat.h" }
    $localVersion = "0.0.0"
    $rawVersion = $Branch
    $binaryversion = "0"
    
    if (Test-Path $libexpatHeader) {
        # Extract version from #define #define XML_MAJOR_VERSION  #define XML_MINOR_VERSION #define XML_MICRO_VERSION
        $headerContent = Get-Content $libexpatHeader
        
        # Extract Major, Minor, and Micro versions safely
        $majorMatch = $headerContent | Select-String '#\s*define\s+XML_MAJOR_VERSION\s+(\d+)' | Select-Object -First 1
        $minorMatch = $headerContent | Select-String '#\s*define\s+XML_MINOR_VERSION\s+(\d+)' | Select-Object -First 1
        $microMatch = $headerContent | Select-String '#\s*define\s+XML_MICRO_VERSION\s+(\d+)' | Select-Object -First 1

        $major = if ($majorMatch) { $majorMatch.Matches.Groups[1].Value } else { "0" }
        $minor = if ($minorMatch) { $minorMatch.Matches.Groups[1].Value } else { "0" }
        $rel   = if ($microMatch) { $microMatch.Matches.Groups[1].Value } else { "0" }

        if ($major -and $minor -and $rel) {
            $localVersion = "$major.$minor.$rel"
            $rawVersion = $localVersion
            $binaryversion = ([version]$localVersion).Major
            Write-Host "[VERSION] Detected libexpat: $localVersion" -ForegroundColor Cyan
        }
    }
    
    # Save new version state
    $libexpatVersion = $localVersion
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
    
    # --- 11. Create Environment Helper ---
    Write-Host "Generating environment helper script..." -ForegroundColor Cyan
    $EnvContent = @'
# LIBEXPAT Environment Setup
$libexpatroot = "VALUE_ROOT_PATH"
$libexpatinclude = "VALUE_INCLUDE_PATH"
$libexpatlibrary = "VALUE_LIB_PATH"
$libexpatbin = "VALUE_BIN_PATH"
$libexpatversion = "VALUE_VERSION"
$libexpatabiversion = "VALUE_ABI_VERSION"
$libexpatsoversion = "VALUE_SO_VERSION"
$libexpatbinary = "VALUE_BINARY"
$libexpatshared = "VALUE_SHARED"
$libexpatstatic = "VALUE_STATIC"
$libexpatlibname = "VALUE_LIB_NAME"
$libexpatcmakepath = "VALUE_CMAKE_PATH"
$env:LIBEXPAT_PATH = $libexpatroot
$env:LIBEXPAT_ROOT = $libexpatroot
$env:LIBEXPAT_BIN = $libexpatbin
$env:LIBEXPAT_INCLUDE_DIR = $libexpatinclude
$env:LIBEXPAT_LIBRARY_DIR = $libexpatlibrary
$env:BINARY_LIB_EXPAT = $libexpatbinary
$env:SHARED_LIB_EXPAT = $libexpatshared
$env:STATIC_LIB_EXPAT = $libexpatstatic
$env:LIBEXPAT_LIB_NAME = $libexpatlibname
$env:LIBEXPAT_VERSION = $libexpatversion
$env:LIBEXPAT_MAJOR = ([version]$libexpatversion).Major
$env:LIBEXPAT_MINOR = ([version]$libexpatversion).Minor
$env:LIBEXPAT_PATCH = ([version]$libexpatversion).Patch
$env:LIBEXPAT_ABI_VERSION = $libexpatabiversion
$env:LIBEXPAT_SO_VERSION = $libexpatsoversion
if ($env:CMAKE_PREFIX_PATH -notlike "*$libexpatcmakepath*") { $env:CMAKE_PREFIX_PATH = $libexpatcmakepath + ";" + $env:CMAKE_PREFIX_PATH; $env:CMAKE_PREFIX_PATH = ($env:CMAKE_PREFIX_PATH).Replace(";;", ";") }
if ($env:INCLUDE -notlike "*$libexpatinclude*") { $env:INCLUDE = $libexpatinclude + ";" + $env:INCLUDE; $env:INCLUDE = ($env:INCLUDE).Replace(";;", ";") }
if ($env:LIB -notlike "*$libexpatlibrary*") { $env:LIB = $libexpatlibrary + ";" + $env:LIB; $env:LIB = ($env:LIB).Replace(";;", ";") }
if ($env:PATH -notlike "*$libexpatbin*") { $env:PATH = $libexpatbin + ";" + $env:PATH; $env:PATH = ($env:PATH).Replace(";;", ";") }
Write-Host "libexpat Environment Loaded (Version: $libexpatversion) (Bin: $libexpatbin)" -ForegroundColor Green
Write-Host "LIBEXPAT_ROOT: $env:LIBEXPAT_ROOT" -ForegroundColor Gray
'@  -replace "VALUE_ROOT_PATH", $libexpatInstallDir `
    -replace "VALUE_INCLUDE_PATH", $libexpatIncludeDir `
    -replace "VALUE_LIB_PATH", $libexpatLibDir `
    -replace "VALUE_BIN_PATH", $libexpatBinPath `
    -replace "VALUE_VERSION", $libexpatVersion `
    -replace "VALUE_ABI_VERSION", $binaryversion `
    -replace "VALUE_SO_VERSION", $binaryversion `
    -replace "VALUE_SHARED", $SharedLib `
    -replace "VALUE_BINARY", $BinaryLib `
    -replace "VALUE_STATIC", $StaticLib `
    -replace "VALUE_LIB_NAME", $libexpatLibName `
    -replace "VALUE_CMAKE_PATH", $libexpatCMakePath

    $EnvContent | Out-File -FilePath $libexpatEnvScript -Encoding utf8
    Write-Host "Created: $libexpatEnvScript" -ForegroundColor Gray
    
    # Update Current Session
    if (Test-Path $libexpatEnvScript) { . $libexpatEnvScript } else {
        Write-Error "libexpat build install finished but $libexpatEnvScript was not created."
        Pop-Location; return
    }
    
    if ($libexpatWithMachineEnvironment) {
        # Generating Machine Environment wich add to the persist registry machine Environment
        $MachineEnvContent = @'
# libexpat Machine Environment Setup

# --- 0. Self-Elevation Logic ---
$IsAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$ScopeColor = "Cyan"

if (-not $IsAdmin) {
    Write-Host "Elevation required to set libexpat system variables. Relaunching as Administrator..." -ForegroundColor Yellow
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

$libexpatroot = "VALUE_ROOT_PATH"
$libexpatbin = "VALUE_BIN_PATH"
$libexpatversion = "VALUE_VERSION"

$TargetScope = if ($IsAdmin) { "Machine" } else { "User" }
$RegPath = if ($IsAdmin) { "System\CurrentControlSet\Control\Session Manager\Environment" } else { "Environment" }
$RegRoot = if ($IsAdmin) { "LocalMachine" } else { "CurrentUser" }

# Open the registry key once
$RegKey = [Microsoft.Win32.Registry]::$RegRoot.OpenSubKey($RegPath, $true)

# Open the registry key directly to read the RAW (unexpanded) string
$CurrentRawPath = $RegKey.GetValue("EXTCOMPLIBS_PATH", "", [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)

# Cleanup: Remove empty strings, any path containing $libexpatroot, and the current target (to avoid dups)
$CleanedPathList = $CurrentRawPath -split ';' | Where-Object { 
    -not [string]::IsNullOrWhitespace($_) -and 
    $_ -notlike "*$libexpatroot*"
}

$NewRawPath = ($CleanedPathList -join ";").Replace(";;", ";")

$TargetPath = $libexpatbin

# Rebuild
$NewRawPath = ($NewRawPath + ";" + $TargetPath + ";").Replace(";;", ";")
Write-Host "[UPDATED] ($TargetScope) '$libexpatbin' synced in EXTCOMPLIBS_PATH" -ForegroundColor $ScopeColor

# Save as ExpandString
$RegKey.SetValue("EXTCOMPLIBS_PATH", $NewRawPath, [Microsoft.Win32.RegistryValueKind]::ExpandString)
$env:EXTCOMPLIBS_PATH = $NewRawPath

$RegKey.Close()

$env:LIBEXPAT_ROOT = $libexpatroot
Write-Host "libexpat Environment Loaded (Version: $libexpatversion) (Bin: $libexpatbin)" -ForegroundColor Green
Write-Host "LIBEXPAT_ROOT: $env:LIBEXPAT_ROOT" -ForegroundColor Gray
'@  -replace "VALUE_ROOT_PATH", $libexpatInstallDir `
    -replace "VALUE_BIN_PATH", $libexpatBinPath `
    -replace "VALUE_VERSION", $libexpatVersion

        $MachineEnvContent | Out-File -FilePath $libexpatMachineEnvScript -Encoding utf8
        Write-Host "Created: $libexpatMachineEnvScript" -ForegroundColor Gray
        
        # --- Interaction: Prompt to apply persistent changes ---
        Write-Host ""
        $choice = Read-Host "Do you want to run the Machine Environment script now to persist libexpat changes to the Registry? (y/n)"
        if ($choice -eq 'y' -or $choice -eq 'Y') {
            Write-Host "Executing $libexpatMachineEnvScript..." -ForegroundColor Yellow
            try {
                # Start the generated script. It handles its own elevation logic.
                & $libexpatMachineEnvScript
            }
            catch {
                Write-Error "Failed to execute the Machine Environment script: $($_.Exception.Message)"
            }
        }
        else {
            Write-Host "Skipped persistent registry update. You can run it later at: $libexpatMachineEnvScript" -ForegroundColor Gray
        }
    }
    
    # --- Return to Start ---
    Pop-Location
    Write-Host "Successfully Done! and returned to: $(Get-Location)" -ForegroundColor DarkGreen
}
else {
    Write-Error "libexpat.lib was not found in the $libexpatLibDir folder."
    Pop-Location; return
}
