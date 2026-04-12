# Copyright 2026 (C) Navegos. DevelVitorF. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
# file:x64-windows/build-libxml2.ps1

param (
    [Parameter(HelpMessage = "Base workspace path", Mandatory = $false)]
    [string]$workspacePath = $null,

    [Parameter(HelpMessage = "libxml2 git repo url", Mandatory = $false)]
    [string]$gitUrl = "https://github.com/GNOME/libxml2.git",
    
    [Parameter(HelpMessage = "libxml2 git branch to sync from", Mandatory = $false)]
    [string]$gitBranch = "master",

    [Parameter(HelpMessage = "Path for libxml2 library storage", Mandatory = $false)]
    [string]$libxml2InstallDir = "$env:LIBRARIES_PATH\libxml2",
    
    [Parameter(HelpMessage = "Force a full purge of the local libxml2 version before continuing", Mandatory = $false)]
    [switch]$forceCleanup,
    
    [Parameter(HelpMessage = "Add's libxml2 Machine Environment Variables. Requires Machine Administrator Rights.", Mandatory = $false)]
    [switch]$withMachineEnvironment
)

# Capture parameters
$libxml2WorkspacePath = $workspacePath
$libxml2GitUrl = $gitUrl
$libxml2GitBranch = $gitBranch
$libxml2ForceCleanup = $forceCleanup
$libxml2WithMachineEnvironment = $withMachineEnvironment

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
$Rootlibxml2InstallDir = Split-Path -Path $libxml2InstallDir -Parent
$Rootlibxml2WorkspacePath = if ([string]::IsNullOrWhitespace($libxml2WorkspacePath)) { Get-Location } else { $libxml2WorkspacePath }

# Load Lzma requirement
if ([string]::IsNullOrWhiteSpace($env:SHARED_LIB_LZMA) -or -not (Test-Path $env:SHARED_LIB_LZMA)) {
    $lzmaEnvScript = Join-Path $EnvironmentDir "env-lzma.ps1"
    if (Test-Path $lzmaEnvScript) { . $lzmaEnvScript }
    if ([string]::IsNullOrWhiteSpace($env:SHARED_LIB_LZMA) -or -not (Test-Path $env:SHARED_LIB_LZMA)) {
        $lzmaBuildScript = Join-Path $PSScriptRoot "build-lzma.ps1"
        if (Test-Path $lzmaBuildScript) {
            $lzmaInstallDir = Join-Path $Rootlibxml2InstallDir "lzma"
            & $lzmaBuildScript -workspacePath $Rootlibxml2WorkspacePath -lzmaInstallDir $lzmaInstallDir
        }
        else {
            Write-Error "CRITICAL: Cannot build lzma. lzma is missing and $lzmaBuildScript was not found."
            return
        }
    }
}

# Load Zlib requirement
if ([string]::IsNullOrWhiteSpace($env:SHARED_LIB_ZLIB) -or -not (Test-Path $env:SHARED_LIB_ZLIB)) {
    $zlibEnvScript = Join-Path $EnvironmentDir "env-zlib.ps1"
    if (Test-Path $zlibEnvScript) { . $zlibEnvScript }
    if ([string]::IsNullOrWhiteSpace($env:SHARED_LIB_ZLIB) -or -not (Test-Path $env:SHARED_LIB_ZLIB)) {
        $zlibBuildScript = Join-Path $PSScriptRoot "build-zlib.ps1"
        if (Test-Path $zlibBuildScript) {
            $zlibInstallDir = Join-Path $Rootlibxml2InstallDir "zlib"
            & $zlibBuildScript -workspacePath $Rootlibxml2WorkspacePath -zlibInstallDir $zlibInstallDir
        } else {
            Write-Error "CRITICAL: Cannot build zlib. zlib is missing and $zlibBuildScript was not found."
            return
        }
    }
}

# Load libiconv requirement
if ([string]::IsNullOrWhiteSpace($env:LIBICONV_LIBRARY_DIR) -or -not (Test-Path (Join-Path $env:LIBICONV_LIBRARY_DIR "iconv.lib"))) {
    $libiconvEnvScript = Join-Path $EnvironmentDir "env-libiconv.ps1"
    if (Test-Path $libiconvEnvScript) { . $libiconvEnvScript }
    if ([string]::IsNullOrWhiteSpace($env:LIBICONV_LIBRARY_DIR) -or -not (Test-Path (Join-Path $env:LIBICONV_LIBRARY_DIR "iconv.lib"))) {
        $deplibiconvEnvScript = Join-Path $PSScriptRoot "dep-libiconv.ps1"
        if (Test-Path $deplibiconvEnvScript) { . $deplibiconvEnvScript }
        else {
            Write-Error "CRITICAL: Cannot load libiconv environment. iconv is missing and $libiconvEnvScript was not found."
            return
        }
    }
}

# Load icu requirement
if ([string]::IsNullOrWhiteSpace($env:ICU_LIBRARY_DIR) -or -not (Test-Path (Join-Path $env:ICU_LIBRARY_DIR "icuuc.lib"))) {
    $icuEnvScript = Join-Path $EnvironmentDir "env-icu.ps1"
    if (Test-Path $icuEnvScript) { . $icuEnvScript }
    if ([string]::IsNullOrWhiteSpace($env:ICU_LIBRARY_DIR) -or -not (Test-Path (Join-Path $env:ICU_LIBRARY_DIR "icuuc.lib"))) {
        $depicuEnvScript = Join-Path $PSScriptRoot "dep-icu.ps1"
        if (Test-Path $depicuEnvScript) { . $depicuEnvScript }
        else {
            Write-Error "CRITICAL: Cannot load icu environment. iconv is missing and $icuEnvScript was not found."
            return
        }
    }
}

# Load python requirement
if (-not $env:PYTHON_PATH) {
    $pythonEnvScript = Join-Path $EnvironmentDir "env-python.ps1"
    if (Test-Path $pythonEnvScript) { . $pythonEnvScript }
    if (-not $env:PYTHON_PATH) {
        $deppythonEnvScript = Join-Path $PSScriptRoot "dep-python.ps1"
        if (Test-Path $deppythonEnvScript) { . $deppythonEnvScript }
        else {
            Write-Error "CRITICAL: Cannot load python environment. python is missing and $deppythonEnvScript was not found."
            return
        }
    }
}

$RootPath = $Rootlibxml2WorkspacePath

# --- 6. Path Resolution ---
Push-Location $RootPath

$Source         = Join-Path $RootPath "libxml2"
$BuildDirShared = Join-Path $Source "build_shared"
$BuildDirStatic = Join-Path $Source "build_static"
$RepoUrl        = $libxml2GitUrl
$Branch         = $libxml2GitBranch
$CMakeSource    = $Source
$tag_name       = $Branch
$url            = $RepoUrl

$libxml2EnvScript = Join-Path $EnvironmentDir "env-libxml2.ps1"
$libxml2MachineEnvScript = Join-Path $EnvironmentDir "machine-env-libxml2.ps1"

# --- 1. Cleanup Mechanism ---
function Invoke-libxml2VersionPurge {
    param ([string]$InstallPath)
    Write-Host "--- Initiating libxml2 Purge ---" -ForegroundColor Cyan

    if ($libxml2WithMachineEnvironment)
    {
        $libxml2CleanMachineEnvScript = Join-Path $env:TEMP "clean-machine-env-libxml2.ps1"

        # Generating Clean Machine Environment wich removes the persist registry machine Environment
        $CleanMachineEnvContent = @'
# libxml2 Clean Machine Environment Setup

# --- 0. Self-Elevation Logic ---
$IsAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$ScopeColor = "Cyan"

if (-not $IsAdmin) {
    Write-Host "Elevation required to clean libxml2 system variables. Relaunching as Administrator..." -ForegroundColor Yellow
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

$libxml2root = "VALUE_ROOT_PATH"

$TargetScope = if ($IsAdmin) { "Machine" } else { "User" }
$RegPath = if ($IsAdmin) { "System\CurrentControlSet\Control\Session Manager\Environment" } else { "Environment" }
$RegRoot = if ($IsAdmin) { "LocalMachine" } else { "CurrentUser" }

# 1. Registry Cleanup (EXTCOMPLIBS_PATH)
$RegKey = [Microsoft.Win32.Registry]::$RegRoot.OpenSubKey($RegPath, $true)

# Open the registry key directly to read the RAW (unexpanded) string
$RawPath = $RegKey.GetValue("EXTCOMPLIBS_PATH", "", [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)

# Cleanup: Remove empty strings, any path containing $libxml2root,
$CleanPath = ($RawPath -split ';' | Where-Object { $_ -notlike "*$libxml2root*" }) -join ";"

# Save as ExpandString
$RegKey.SetValue("EXTCOMPLIBS_PATH", $CleanPath, [Microsoft.Win32.RegistryValueKind]::ExpandString)
$env:EXTCOMPLIBS_PATH = $CleanPath

$RegKey.Close()

Write-Host "[REMOVED] ($TargetScope) all '*$libxml2root*' removed from EXTCOMPLIBS_PATH" -ForegroundColor $ScopeColor
'@  -replace "VALUE_ROOT_PATH", $InstallPath

        $CleanMachineEnvContent | Out-File -FilePath $libxml2CleanMachineEnvScript -Encoding utf8
        Write-Host "Created: $libxml2CleanMachineEnvScript" -ForegroundColor Gray
        
        # --- Interaction: Prompt to remove persistent changes ---
        Write-Host ""
        $choice = Read-Host "Administrator rights required to Clean Machine Environment libxml2 changes? (y/n)"
        if ($choice -eq 'y' -or $choice -eq 'Y') {
            Write-Host "Executing $libxml2CleanMachineEnvScript..." -ForegroundColor Yellow
            try {
                # Start the generated script. It handles its own elevation logic.
                & $libxml2CleanMachineEnvScript
            }
            catch {
                Write-Error "Failed to execute the Clean Machine Environment script: $($_.Exception.Message)"
                Pop-Location; return
            }
        }
        else {
            Write-Error "Skipped Clean Machine Environment libxml2 changes."
            Pop-Location; return
        }

        # Cleanup
        Remove-Item $libxml2CleanMachineEnvScript -Recurse -Force -ErrorAction SilentlyContinue
    }

    # 2. Filesystem Clean (Requires checking for locked files)
    # delete everithing we create don't fail later
    if (Test-Path $libxml2EnvScript) {
        Write-Host "  [DELETING] $libxml2EnvScript" -ForegroundColor Yellow
        Remove-Item $libxml2EnvScript -Recurse -Force -ErrorAction SilentlyContinue
    }
    if (Test-Path $libxml2MachineEnvScript) {
        Write-Host "  [DELETING] $libxml2MachineEnvScript" -ForegroundColor Yellow
        Remove-Item $libxml2MachineEnvScript -Recurse -Force -ErrorAction SilentlyContinue
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
    Get-ChildItem Env:\LIBXML2_PATH* | Remove-Item -ErrorAction SilentlyContinue
    Get-ChildItem Env:\LIBXML2_ROOT* | Remove-Item -ErrorAction SilentlyContinue
    Get-ChildItem Env:\LIBXML2_BIN* | Remove-Item -ErrorAction SilentlyContinue
    Get-ChildItem Env:\LIBXML2_INCLUDE_DIR* | Remove-Item -ErrorAction SilentlyContinue
    Get-ChildItem Env:\LIBXML2_LIBRARY_DIR* | Remove-Item -ErrorAction SilentlyContinue
    Get-ChildItem Env:\BINARY_LIB_LIBXML2* | Remove-Item -ErrorAction SilentlyContinue
    Get-ChildItem Env:\SHARED_LIB_LIBXML2* | Remove-Item -ErrorAction SilentlyContinue
    Get-ChildItem Env:\STATIC_LIB_LIBXML2* | Remove-Item -ErrorAction SilentlyContinue

    Write-Host "--- LIBXML2 Purge Complete ---" -ForegroundColor Green
}

if ($libxml2ForceCleanup) {
    Invoke-libxml2VersionPurge -InstallPath $libxml2InstallDir
}

# --- 7. Source Management ---
if (Test-Path $Source) {
    Write-Host "Syncing libxml2 ($Branch) at $Source..." -ForegroundColor Cyan
    Set-Location $Source
    git fetch --all
    git reset --hard "origin/$Branch"
    git pull --recurse-submodules --force
    $tagCommit = (& git rev-parse --verify HEAD).Trim()
} else {
    Write-Host "Cloning libxml2 ($Branch) into $Source..." -ForegroundColor Cyan
    git clone --recurse-submodules $RepoUrl $Source -b $Branch
    Set-Location $Source
    $tagCommit = (& git rev-parse --verify HEAD).Trim()
}

# --- 8. Clean Final Destination ---
if (Test-Path $libxml2InstallDir) {
    Write-Host "Wiping existing installation at $libxml2InstallDir..." -ForegroundColor Yellow
    Remove-Item $libxml2InstallDir -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "[INSTALL] Creating fresh directory: $libxml2InstallDir" -ForegroundColor Cyan
New-Item -Path $libxml2InstallDir -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null

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
    "-DLIBXML2_WITH_DOCS=OFF",
    "-DLIBXML2_WITH_HTML=ON",
    "-DLIBXML2_WITH_HTTP=OFF",
    "-DLIBXML2_WITH_ICONV=ON",
    "-DLIBXML2_WITH_ICU=ON",
    "-DLIBXML2_WITH_ISO8859X=ON",
    "-DLIBXML2_WITH_LEGACY=OFF",
    "-DLIBXML2_WITH_OUTPUT=ON",
    "-DLIBXML2_WITH_PATTERN=ON",
    "-DLIBXML2_WITH_PUSH=ON",
    "-DLIBXML2_WITH_REGEXPS=ON",
    "-DLIBXML2_WITH_SAX1=ON",
    "-DLIBXML2_WITH_TESTS=OFF",
    "-DLIBXML2_WITH_THREADS=ON",
    "-DLIBXML2_WITH_TLS=OFF",
    "-DLIBXML2_WITH_VALID=ON",
    "-DLIBXML2_WITH_WINPATH=ON",
    "-DLIBXML2_WITH_XINCLUDE=ON",
    "-DLIBXML2_WITH_XPATH=ON",
    "-DLIBXML2_WITH_ZLIB=ON",
    "-DLIBXML2_WITH_LZMA=ON",
    "-DLIBXML2_WITH_C14N=ON",
    "-DLIBXML2_WITH_READER=ON",
    "-DLIBXML2_WITH_SCHEMAS=ON",
    "-DLIBXML2_WITH_SCHEMATRON=OFF",
    "-DLIBXML2_WITH_THREAD_ALLOC=OFF",
    "-DLIBXML2_WITH_WRITER=ON",
    "-DLIBXML2_WITH_XPTR=ON",
    "-DLIBXML2_WITH_RELAXNG=ON"
)

# --- 9. STAGE 1: Build Static Libraries ---
Write-Host "Building Static (libxml2s.lib)..." -ForegroundColor Cyan
cmake $CommonCmakeArgs `
    -S "$CMakeSource" `
    -B "$BuildDirStatic" `
    -DCMAKE_INSTALL_PREFIX="$libxml2InstallDir" `
    -DBUILD_SHARED_LIBS=OFF `
    -DLIBXML2_WITH_CATALOG=OFF `
    -DLIBXML2_WITH_DEBUG=OFF `
    -DLIBXML2_WITH_MODULES=OFF `
    -DLIBXML2_WITH_PROGRAMS=OFF `
    -DLIBXML2_WITH_PYTHON=OFF `
    -DLIBXML2_WITH_READLINE=OFF `
    -DLIBXML2_WITH_HISTORY=OFF `
    -DCMAKE_C_FLAGS="-Wno-deprecated-declarations -D_CRT_SECURE_NO_WARNINGS=1" `
    -DCMAKE_CXX_FLAGS="-Wno-deprecated-declarations -D_CRT_SECURE_NO_WARNINGS=1" `
    --no-warn-unused-cli

if ($LASTEXITCODE -ne 0) { Write-Error "libxml2 CMake Static (libxml2s.lib) configuration failed."; Pop-Location; return }

Write-Host "Building and Installing static lib to $libxml2InstallDir..." -ForegroundColor Green
cmake --build "$BuildDirStatic" --target install --config Release --parallel

if ($LASTEXITCODE -ne 0) { Write-Error "libxml2 Static Build failed with exit code $LASTEXITCODE"; Pop-Location; return }

# --- 9.5. Rename Static Libraries (Suffix 's' Only) ---
Write-Host "Applying 's' suffix to static libs..." -ForegroundColor Gray
Get-ChildItem -Path "$libxml2InstallDir\lib\*.lib" | ForEach-Object {
    $newName = $_.BaseName + "s" + $_.Extension
    Move-Item -Path $_.FullName -Destination (Join-Path $_.DirectoryName $newName) -Force -ErrorAction SilentlyContinue
    Write-Host "  -> $newName" -ForegroundColor DarkGray
}

# --- 10. STAGE 2: Build Shared Libraries ---
Write-Host "Building Shared (DLL)..." -ForegroundColor Cyan
cmake $CommonCmakeArgs `
    -S "$CMakeSource" `
    -B "$BuildDirShared" `
    -DCMAKE_INSTALL_PREFIX="$libxml2InstallDir" `
    -DBUILD_SHARED_LIBS=ON `
    -DLIBXML2_WITH_CATALOG=ON `
    -DLIBXML2_WITH_DEBUG=ON `
    -DLIBXML2_WITH_MODULES=ON `
    -DLIBXML2_WITH_PROGRAMS=ON `
    -DLIBXML2_WITH_PYTHON=ON `
    -DLIBXML2_WITH_READLINE=OFF `
    -DLIBXML2_WITH_HISTORY=OFF `
    -DCMAKE_C_FLAGS="-Wno-deprecated-declarations -D_CRT_SECURE_NO_WARNINGS=1" `
    -DCMAKE_CXX_FLAGS="-Wno-deprecated-declarations -D_CRT_SECURE_NO_WARNINGS=1" `
    --no-warn-unused-cli
    
if ($LASTEXITCODE -ne 0) { Write-Error "libxml2 CMake Shared (DLL) configuration failed."; Pop-Location; return }

Write-Host "Building and Installing dynamic lib to $libxml2InstallDir..." -ForegroundColor Green
cmake --build "$BuildDirShared" --target install --config Release --parallel

if ($LASTEXITCODE -ne 0) { Write-Error "libxml2 Shared Build failed with exit code $LASTEXITCODE"; Pop-Location; return }

# --- 10.5. Relocate Dependency DLLs ---
<# Write-Host "Deploying dependency DLLs to bin folder..." -ForegroundColor Cyan
$DependencyBins = @(
    $env:ZLIB_BIN, 
    $env:LIBICONV_BIN, 
    $env:ICU_BIN, 
    $env:LZMA_BIN
) #>

#$DestBin = Join-Path $libxml2InstallDir "bin"

<# foreach ($BinPath in $DependencyBins) {
    if (-not [string]::IsNullOrWhitespace($BinPath) -and (Test-Path $BinPath)) {
        Write-Host "  -> Syncing DLLs from: $BinPath" -ForegroundColor Gray
        Get-ChildItem -Path $BinPath -Filter "*.dll" | Copy-Item -Destination $DestBin -Recurse -Force -ErrorAction SilentlyContinue
    } else {
        Write-Warning "Dependency bin path missing or invalid: $BinPath"
    }
} #>

Write-Host "Successfully built and installed libxml2 to $libxml2InstallDir!" -ForegroundColor Green

# Generate Environment Helper with Clean Paths
$GlobalBinDir = "$env:BINARIES_PATH"
$libxml2InstallDir = $libxml2InstallDir.TrimEnd('\')
$libxml2IncludeDir = Join-Path $libxml2InstallDir "include\libxml2"
$libxml2LibDir = Join-Path $libxml2InstallDir "lib"
$libxml2BinPath = Join-Path $libxml2InstallDir "bin"
$libxml2CMakePath = $libxml2InstallDir.Replace('\', '/')

$StaticLib = Join-Path $libxml2LibDir "libxml2static.lib"
$SharedLib = Join-Path $libxml2LibDir "libxml2.lib"
$BinaryLib = Join-Path $libxml2BinPath "libxml2.dll"
$versionFile = Join-Path $libxml2InstallDir "version.json"

# Fallback check for "z.lib" / "zs.lib" naming convention
if (-not (Test-Path $StaticLib)) { $StaticLib = Join-Path $libxml2LibDir "libxml2s.lib" }
#if (-not (Test-Path $SharedLib)) { $SharedLib = Join-Path $libxml2LibDir "libxml2.lib" }
#if (-not (Test-Path $BinaryLib)) { $BinaryLib = Join-Path $libxml2BinPath "libxml2.dll" }

# Save the xmlversion.h before removing build dirs
$libxml2Header = Join-Path $libxml2IncludeDir "libxml\xmlversion.h"
$libxml2xmlIncludeDir = Join-Path $libxml2IncludeDir "libxml"
$libxml2buildHeader = Join-Path $BuildDirShared "libxml\xmlversion.h"
if (-not (Test-Path $libxml2Header)) { Copy-Item -Path "$libxml2buildHeader" -Destination $libxml2xmlIncludeDir -Recurse -Force -ErrorAction SilentlyContinue }

# Cleanup temporary build debris
Remove-Item $BuildDirShared -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item $BuildDirStatic -Recurse -Force -ErrorAction SilentlyContinue

$libxml2tools = @("xmlcatalog.exe", "xmllint.exe")
foreach ($libxml2tool in $libxml2tools) {
    $target = Join-Path $GlobalBinDir $libxml2tool
    if (Test-Path $target) { Remove-Item $target -Force -ErrorAction SilentlyContinue }
}

if ((Test-Path $StaticLib) -or (Test-Path $SharedLib) -or (Test-Path $BinaryLib)) {
    $localVersion = "0.0.0"
    $rawVersion = $Branch

    if (Test-Path $libxml2Header) {
        # Extract version from #define LIBXML_DOTTED_VERSION "2.16.0"
        $headerContent = Get-Content $libxml2Header
        
        # Regex looks for the define and captures the content inside the quotes
        $versionMatch = ($headerContent | Select-String '#define\s+LIBXML_DOTTED_VERSION\s+"([^"]+)"').Matches.Groups[1].Value
    
        if ($versionMatch) {
            $localVersion = $versionMatch
            $rawVersion = $localVersion
            Write-Host "[VERSION] Detected libxml2: $localVersion" -ForegroundColor Cyan
        }
    }
    
    # Save new version state
    $libxml2Version = $localVersion
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
    
    # Create the Symbolic Link
    foreach ($toolName in $libxml2tools) {
        $newExePath    = Join-Path $libxml2BinPath $toolName
        $globalLinkPath = Join-Path $GlobalBinDir $toolName
        
        Write-Host "Creating global symlink: $globalLinkPath" -ForegroundColor Cyan

        if (Test-Path $newExePath) {
            if (Test-Path $globalLinkPath) { Remove-Item $globalLinkPath -Force -ErrorAction SilentlyContinue }
            try {
                New-Item -Path $globalLinkPath -ItemType SymbolicLink -Value $newExePath -ErrorAction Stop | Out-Null
                Write-Host "[LINKED] libxml2 (Global) -> $newExePath" -ForegroundColor Green
            }
            catch {
                New-Item -Path $globalLinkPath -ItemType HardLink -Value $newExePath | Out-Null
                Write-Host "[HARDLINKED] libxml2 (Global) -> $newExePath" -ForegroundColor Green
            }
        }
        else {
            Write-Error "CRITICAL: Could not find $toolName to symlink at $newExePath"
            if (Test-Path $globalLinkPath) {
                Write-Host "Cleaning up dead symlink at $globalLinkPath..." -ForegroundColor Yellow
                Remove-Item $globalLinkPath -Force -ErrorAction SilentlyContinue
            }
        }
    }

    Write-Host "[LINKED] libxml2 is now globally available via %BINARIES_PATH%" -ForegroundColor Green
    
    # --- 11. Create Environment Helper ---
    Write-Host "Generating environment helper script..." -ForegroundColor Cyan
    $EnvContent = @'
# LIBXML2 Environment Setup
$libxml2root = "VALUE_ROOT_PATH"
$libxml2include = "VALUE_INCLUDE_PATH"
$libxml2library = "VALUE_LIB_PATH"
$libxml2bin = "VALUE_BIN_PATH"
$libxml2version = "VALUE_VERSION"
$libxml2binary = "VALUE_BINARY"
$libxml2shared = "VALUE_SHARED"
$libxml2static = "VALUE_STATIC"
$libxml2cmakepath = "VALUE_CMAKE_PATH"
$env:LIBXML2_PATH = $libxml2root
$env:LIBXML2_ROOT = $libxml2root
$env:LIBXML2_BIN = $libxml2bin
$env:LIBXML2_INCLUDE_DIR = $libxml2include
$env:LIBXML2_LIBRARY_DIR = $libxml2library
$env:BINARY_LIB_LIBXML2 = $libxml2binary
$env:SHARED_LIB_LIBXML2 = $libxml2shared
$env:STATIC_LIB_LIBXML2 = $libxml2static
if ($env:CMAKE_PREFIX_PATH -notlike "*$libxml2cmakepath*") { $env:CMAKE_PREFIX_PATH = $libxml2cmakepath + ";" + $env:CMAKE_PREFIX_PATH; $env:CMAKE_PREFIX_PATH = ($env:CMAKE_PREFIX_PATH).Replace(";;", ";") }
if ($env:INCLUDE -notlike "*$libxml2include*") { $env:INCLUDE = $libxml2include + ";" + $env:INCLUDE; $env:INCLUDE = ($env:INCLUDE).Replace(";;", ";") }
if ($env:LIB -notlike "*$libxml2library*") { $env:LIB = $libxml2library + ";" + $env:LIB; $env:LIB = ($env:LIB).Replace(";;", ";") }
if ($env:PATH -notlike "*$libxml2bin*") { $env:PATH = $libxml2bin + ";" + $env:PATH; $env:PATH = ($env:PATH).Replace(";;", ";") }
Write-Host "libxml2 Environment Loaded (Version: $libxml2version) (Bin: $libxml2bin)" -ForegroundColor Green
Write-Host "LIBXML2_ROOT: $env:LIBXML2_ROOT" -ForegroundColor Gray
'@  -replace "VALUE_ROOT_PATH", $libxml2InstallDir `
    -replace "VALUE_INCLUDE_PATH", $libxml2IncludeDir `
    -replace "VALUE_LIB_PATH", $libxml2LibDir `
    -replace "VALUE_BIN_PATH", $libxml2BinPath `
    -replace "VALUE_VERSION", $libxml2Version `
    -replace "VALUE_SHARED", $SharedLib `
    -replace "VALUE_BINARY", $BinaryLib `
    -replace "VALUE_STATIC", $StaticLib `
    -replace "VALUE_CMAKE_PATH", $libxml2CMakePath

    $EnvContent | Out-File -FilePath $libxml2EnvScript -Encoding utf8
    Write-Host "Created: $libxml2EnvScript" -ForegroundColor Gray
    
    # Update Current Session
    if (Test-Path $libxml2EnvScript) { . $libxml2EnvScript } else {
        Write-Error "libxml2 build install finished but $libxml2EnvScript was not created."
        Pop-Location; return
    }
    
    if ($libxml2WithMachineEnvironment)
    {
        # Generating Machine Environment wich add to the persist registry machine Environment
        $MachineEnvContent = @'
# libxml2 Machine Environment Setup

# --- 0. Self-Elevation Logic ---
$IsAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$ScopeColor = "Cyan"

if (-not $IsAdmin) {
    Write-Host "Elevation required to set libxml2 system variables. Relaunching as Administrator..." -ForegroundColor Yellow
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

$libxml2root = "VALUE_ROOT_PATH"
$libxml2bin = "VALUE_BIN_PATH"
$libxml2version = "VALUE_VERSION"

$TargetScope = if ($IsAdmin) { "Machine" } else { "User" }
$RegPath = if ($IsAdmin) { "System\CurrentControlSet\Control\Session Manager\Environment" } else { "Environment" }
$RegRoot = if ($IsAdmin) { "LocalMachine" } else { "CurrentUser" }

# Open the registry key once
$RegKey = [Microsoft.Win32.Registry]::$RegRoot.OpenSubKey($RegPath, $true)

# Open the registry key directly to read the RAW (unexpanded) string
$CurrentRawPath = $RegKey.GetValue("EXTCOMPLIBS_PATH", "", [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)

# Cleanup: Remove empty strings, any path containing $libxml2root, and the current target (to avoid dups)
$CleanedPathList = $CurrentRawPath -split ';' | Where-Object { 
    -not [string]::IsNullOrWhitespace($_) -and 
    $_ -notlike "*$libxml2root*"
}

$NewRawPath = ($CleanedPathList -join ";").Replace(";;", ";")

$TargetPath = $libxml2bin

# Rebuild
$NewRawPath = ($NewRawPath + ";" + $TargetPath + ";").Replace(";;", ";")
Write-Host "[UPDATED] ($TargetScope) '$libxml2bin' synced in EXTCOMPLIBS_PATH" -ForegroundColor $ScopeColor

# Save as ExpandString
$RegKey.SetValue("EXTCOMPLIBS_PATH", $NewRawPath, [Microsoft.Win32.RegistryValueKind]::ExpandString)
$env:EXTCOMPLIBS_PATH = $NewRawPath

$RegKey.Close()

$env:LIBXML2_ROOT = $libxml2root
Write-Host "libxml2 Environment Loaded (Version: $libxml2version) (Bin: $libxml2bin)" -ForegroundColor Green
Write-Host "LIBXML2_ROOT: $env:LIBXML2_ROOT" -ForegroundColor Gray
'@  -replace "VALUE_ROOT_PATH", $libxml2InstallDir `
    -replace "VALUE_BIN_PATH", $libxml2BinPath `
    -replace "VALUE_VERSION", $libxml2Version

        $MachineEnvContent | Out-File -FilePath $libxml2MachineEnvScript -Encoding utf8
        Write-Host "Created: $libxml2MachineEnvScript" -ForegroundColor Gray
        
        # --- Interaction: Prompt to apply persistent changes ---
        Write-Host ""
        $choice = Read-Host "Do you want to run the Machine Environment script now to persist libxml2 changes to the Registry? (y/n)"
        if ($choice -eq 'y' -or $choice -eq 'Y') {
            Write-Host "Executing $libxml2MachineEnvScript..." -ForegroundColor Yellow
            try {
                # Start the generated script. It handles its own elevation logic.
                & $libxml2MachineEnvScript
            }
            catch {
                Write-Error "Failed to execute the Machine Environment script: $($_.Exception.Message)"
            }
        }
        else {
            Write-Host "Skipped persistent registry update. You can run it later at: $libxml2MachineEnvScript" -ForegroundColor Gray
        }
    }
    
    # --- Return to Start ---
    Pop-Location
    Write-Host "Successfully Done! and returned to: $(Get-Location)" -ForegroundColor DarkGreen
} else {
    Write-Error "libxml2.lib was not found in the $libxml2LibDir folder."
    $libxml2tools | ForEach-Object { 
        $globalLinkPath = Join-Path $GlobalBinDir $_
        if (Test-Path $globalLinkPath) {
            Write-Host "Cleaning up dead symlink at $globalLinkPath..." -ForegroundColor Yellow
            Remove-Item $globalLinkPath -Force -ErrorAction SilentlyContinue
        } 
    }
    Pop-Location; return
}
