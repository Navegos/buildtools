# SPDX-FileCopyrightText: Copyright (c) 2026 Navegos. @DevelVitorF. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
# project: buildtools
# file: x64-windows/build-boost.ps1
# created: 2026-03-05
# lastModified: 2026-04-26

param (
    [Parameter(HelpMessage = "Base workspace path", Mandatory = $false)]
    [string]$workspacePath = $null,

    [Parameter(HelpMessage = "boost git repo url", Mandatory = $false)]
    [string]$gitUrl = "https://github.com/boostorg/boost.git",
    
    [Parameter(HelpMessage = "boost branch/tag (e.g. boost-1.84.0)", Mandatory = $false)]
    [string]$gitBranch = "master",

    [Parameter(HelpMessage = "Path for boost library storage", Mandatory = $false)]
    [string]$boostInstallDir = "$env:LIBRARIES_PATH\boost",
    
    [Parameter(HelpMessage = "Lib name, if it's building with a different name (fixit by changing it's default name beforehand)", Mandatory = $false)]
    [string]$boostLibName = "boost",
    
    [Parameter(HelpMessage = "Force a full purge of the local boost version before continuing", Mandatory = $false)]
    [switch]$forceCleanup,
    
    [Parameter(HelpMessage = "Add's boost Machine Environment Variables. Requires Machine Administrator Rights.", Mandatory = $false)]
    [switch]$withMachineEnvironment
)

# Capture parameters
$boostWorkspacePath = $workspacePath
$boostGitUrl = $gitUrl
$boostGitBranch = $gitBranch
$boostForceCleanup = $forceCleanup
$boostWithMachineEnvironment = $withMachineEnvironment

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

# --- 3. Initialize clang environment if missing ---
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
$RootlibboostInstallDir = Split-Path -Path $boostInstallDir -Parent
$RootboostWorkspacePath = if ([string]::IsNullOrWhitespace($boostWorkspacePath)) { Get-Location } else { $boostWorkspacePath }

# Load Lzma requirement
if ([string]::IsNullOrWhiteSpace($env:SHARED_LIB_LZMA) -or -not (Test-Path $env:SHARED_LIB_LZMA)) {
    $lzmaEnvScript = Join-Path $EnvironmentDir "env-lzma.ps1"
    if (Test-Path $lzmaEnvScript) { . $lzmaEnvScript }
    if ([string]::IsNullOrWhiteSpace($env:SHARED_LIB_LZMA) -or -not (Test-Path $env:SHARED_LIB_LZMA)) {
        $lzmaBuildScript = Join-Path $PSScriptRoot "build-lzma.ps1"
        if (Test-Path $lzmaBuildScript) {
            $lzmaInstallDir = Join-Path $RootlibboostInstallDir "lzma"
            & $lzmaBuildScript -workspacePath $RootboostWorkspacePath -lzmaInstallDir $lzmaInstallDir
        } else {
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
            $zlibInstallDir = Join-Path $RootlibboostInstallDir "zlib"
            & $zlibBuildScript -workspacePath $RootboostWorkspacePath -zlibInstallDir $zlibInstallDir
        } else {
            Write-Error "CRITICAL: Cannot build zlib. zlib is missing and $zlibBuildScript was not found."
            return
        }
    }
}

# Load zstd requirement
if ([string]::IsNullOrWhiteSpace($env:SHARED_LIB_ZSTD) -or -not (Test-Path $env:SHARED_LIB_ZSTD)) {
    $zstdEnvScript = Join-Path $EnvironmentDir "env-zstd.ps1"
    if (Test-Path $zstdEnvScript) { . $zstdEnvScript }
    if ([string]::IsNullOrWhiteSpace($env:SHARED_LIB_ZSTD) -or -not (Test-Path $env:SHARED_LIB_ZSTD)) {
        $zstdBuildScript = Join-Path $PSScriptRoot "build-zstd.ps1"
        if (Test-Path $zstdBuildScript) {
            $zstdInstallDir = Join-Path $RootlibboostInstallDir "zstd"
            & $zstdBuildScript -workspacePath $RootboostWorkspacePath -zstdInstallDir $zstdInstallDir
        } else {
            Write-Error "CRITICAL: Cannot build zstd. zstd is missing and $zstdBuildScript was not found."
            return
        }
    }
}

# Load expat requirement
if ([string]::IsNullOrWhiteSpace($env:SHARED_LIB_EXPAT) -or -not (Test-Path $env:SHARED_LIB_EXPAT)) {
    $libexpatEnvScript = Join-Path $EnvironmentDir "env-libexpat.ps1"
    if (Test-Path $libexpatEnvScript) { . $libexpatEnvScript }
    if ([string]::IsNullOrWhiteSpace($env:SHARED_LIB_EXPAT) -or -not (Test-Path $env:SHARED_LIB_EXPAT)) {
        $libexpatBuildScript = Join-Path $PSScriptRoot "build-libexpat.ps1"
        if (Test-Path $libexpatBuildScript) {
            $libexpatInstallDir = Join-Path $RootlibboostInstallDir "libexpat"
            & $libexpatBuildScript -workspacePath $RootboostWorkspacePath -libexpatInstallDir $libexpatInstallDir
        } else {
            Write-Error "CRITICAL: Cannot build libexpat. libexpat is missing and $libexpatBuildScript was not found."
            return
        }
    }
}

# Load icu requirement
if ([string]::IsNullOrWhiteSpace($env:SHARED_LIB_ICUUC) -or -not (Test-Path $env:SHARED_LIB_ICUUC)) {
    $icuEnvScript = Join-Path $EnvironmentDir "env-icu.ps1"
    if (Test-Path $icuEnvScript) { . $icuEnvScript }
    if ([string]::IsNullOrWhiteSpace($env:SHARED_LIB_ICUUC) -or -not (Test-Path $env:SHARED_LIB_ICUUC)) {
        $depicuEnvScript = Join-Path $PSScriptRoot "dep-icu.ps1"
        if (Test-Path $depicuEnvScript) { . $depicuEnvScript }
        else {
            Write-Error "CRITICAL: Cannot load icu environment. icu is missing and $depicuEnvScript was not found."
            return
        }
    }
}

# Load libiconv requirement
if ([string]::IsNullOrWhiteSpace($env:SHARED_LIB_ICONV) -or -not (Test-Path $env:SHARED_LIB_ICONV)) {
    $libiconvEnvScript = Join-Path $EnvironmentDir "env-libiconv.ps1"
    if (Test-Path $libiconvEnvScript) { . $libiconvEnvScript }
    if ([string]::IsNullOrWhiteSpace($env:SHARED_LIB_ICONV) -or -not (Test-Path $env:SHARED_LIB_ICONV)) {
        $deplibiconvEnvScript = Join-Path $PSScriptRoot "dep-libiconv.ps1"
        if (Test-Path $deplibiconvEnvScript) { . $deplibiconvEnvScript }
        else {
            Write-Error "CRITICAL: Cannot load libiconv environment. iconv is missing and $libiconvEnvScript was not found."
            return
        }
    }
}

# Load bzip2 requirement
if ([string]::IsNullOrWhiteSpace($env:SHARED_LIB_BZIP2) -or -not (Test-Path $env:SHARED_LIB_BZIP2)) {
    $bzip2EnvScript = Join-Path $EnvironmentDir "env-bzip2.ps1"
    if (Test-Path $bzip2EnvScript) { . $bzip2EnvScript }
    if ([string]::IsNullOrWhiteSpace($env:SHARED_LIB_BZIP2) -or -not (Test-Path $env:SHARED_LIB_BZIP2)) {
        $depbzip2EnvScript = Join-Path $PSScriptRoot "dep-bzip2.ps1"
        if (Test-Path $depbzip2EnvScript) { . $depbzip2EnvScript }
        else {
            Write-Error "CRITICAL: Cannot load bzip2 environment. bzip2 is missing and $depbzip2EnvScript was not found."
            return
        }
    }
}

# Load oneTBB requirement
if ([string]::IsNullOrWhiteSpace($env:SHARED_LIB_TBB) -or -not (Test-Path $env:SHARED_LIB_TBB)) {
    $oneTBBEnvScript = Join-Path $EnvironmentDir "env-onetbb.ps1"
    if (Test-Path $oneTBBEnvScript) { . $oneTBBEnvScript }
    if ([string]::IsNullOrWhiteSpace($env:SHARED_LIB_TBB) -or -not (Test-Path $env:SHARED_LIB_TBB)) {
        $oneTBBBuildScript = Join-Path $PSScriptRoot "build-onetbb.ps1"
        if (Test-Path $oneTBBBuildScript) {
            $oneTBBInstallDir = Join-Path $RootlibboostInstallDir "oneTBB"
            & $oneTBBBuildScript -workspacePath $RootboostWorkspacePath -oneTBBInstallDir $oneTBBInstallDir
        } else {
            Write-Error "CRITICAL: Cannot build oneTBB. oneTBB is missing and $oneTBBBuildScript was not found."
            return
        }
    }
}

# Load python requirement
if ([string]::IsNullOrWhitespace($env:BINARY_PYTHON) -or -not (Test-Path $env:BINARY_PYTHON)) {
    $pythonEnvScript = Join-Path $EnvironmentDir "env-python.ps1"
    if (Test-Path $pythonEnvScript) { . $pythonEnvScript }
    if ([string]::IsNullOrWhitespace($env:BINARY_PYTHON) -or -not (Test-Path $env:BINARY_PYTHON)) {
        $deppythonEnvScript = Join-Path $PSScriptRoot "dep-python.ps1"
        if (Test-Path $deppythonEnvScript) { . $deppythonEnvScript }
        else {
            Write-Error "CRITICAL: Cannot load python environment. python is missing and $deppythonEnvScript was not found."
            return
        }
    }
}

# Load pkgconf requirement
<# if ([string]::IsNullOrWhitespace($env:BINARY_PKGCONF) -or -not (Test-Path $env:BINARY_PKGCONF)) {
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
} #>

# --- 2. Path Resolution ---
$RootPath = $RootboostWorkspacePath

# --- 6. Path Resolution ---
Push-Location $RootPath

$Source         = Join-Path $RootPath "boost"
$BuildDirShared = Join-Path $Source "build_shared"
$BuildDirStatic = Join-Path $Source "build_static"
$StageDir       = Join-Path $Source "stage_dir"
$RepoUrl        = $boostGitUrl
$Branch         = $boostGitBranch
$Cores          = [int]$env:NUMBER_OF_PROCESSORS / 2
$tag_name       = $Branch
$url            = $RepoUrl

$boostEnvScript = Join-Path $EnvironmentDir "env-boost.ps1"
$boostMachineEnvScript = Join-Path $EnvironmentDir "machine-env-boost.ps1"

# --- 1. Cleanup Mechanism ---
function Invoke-boostVersionPurge {
    param ([string]$InstallPath)
    Write-Host "--- Initiating boost Purge ---" -ForegroundColor Cyan

    if ($boostWithMachineEnvironment)
    {
        $boostCleanMachineEnvScript = Join-Path $env:TEMP "clean-machine-env-boost.ps1"

        # Generating Clean Machine Environment wich removes the persist registry machine Environment
        $CleanMachineEnvContent = @'
# boost Clean Machine Environment Setup

# --- 0. Self-Elevation Logic ---
$IsAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$ScopeColor = "Cyan"

if (-not $IsAdmin) {
    Write-Host "Elevation required to clean boost system variables. Relaunching as Administrator..." -ForegroundColor Yellow
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

$boostroot = "VALUE_ROOT_PATH"

$TargetScope = if ($IsAdmin) { "Machine" } else { "User" }
$RegPath = if ($IsAdmin) { "System\CurrentControlSet\Control\Session Manager\Environment" } else { "Environment" }
$RegRoot = if ($IsAdmin) { "LocalMachine" } else { "CurrentUser" }

# 1. Registry Cleanup (EXTCOMPLIBS_PATH)
$RegKey = [Microsoft.Win32.Registry]::$RegRoot.OpenSubKey($RegPath, $true)

# Open the registry key directly to read the RAW (unexpanded) string
$RawPath = $RegKey.GetValue("EXTCOMPLIBS_PATH", "", [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)

# Cleanup: Remove empty strings, any path containing $boostroot,
$CleanPath = ($RawPath -split ';' | Where-Object { $_ -notlike "*$boostroot*" }) -join ";"

# Save as ExpandString
$RegKey.SetValue("EXTCOMPLIBS_PATH", $CleanPath, [Microsoft.Win32.RegistryValueKind]::ExpandString)
$env:EXTCOMPLIBS_PATH = $CleanPath

$RegKey.Close()

Write-Host "[REMOVED] ($TargetScope) all '*$boostroot*' removed from EXTCOMPLIBS_PATH" -ForegroundColor $ScopeColor
'@  -replace "VALUE_ROOT_PATH", $InstallPath

        $CleanMachineEnvContent | Out-File -FilePath $boostCleanMachineEnvScript -Encoding utf8
        Write-Host "Created: $boostCleanMachineEnvScript" -ForegroundColor Gray
        
        # --- Interaction: Prompt to remove persistent changes ---
        Write-Host ""
        $choice = Read-Host "Administrator rights required to Clean Machine Environment boost changes? (y/n)"
        if ($choice -eq 'y' -or $choice -eq 'Y') {
            Write-Host "Executing $boostCleanMachineEnvScript..." -ForegroundColor Yellow
            try {
                # Start the generated script. It handles its own elevation logic.
                & $boostCleanMachineEnvScript
            }
            catch {
                Write-Error "Failed to execute the Clean Machine Environment script: $($_.Exception.Message)"
                Pop-Location; return
            }
        }
        else {
            Write-Error "Skipped Clean Machine Environment boost changes."
            Pop-Location; return
        }

        # Cleanup
        Remove-Item $boostCleanMachineEnvScript -Recurse -Force -ErrorAction SilentlyContinue
    }

    # 2. Filesystem Clean (Requires checking for locked files)
    # delete everithing we create don't fail later
    if (Test-Path $boostEnvScript) {
        Write-Host "  [DELETING] $boostEnvScript" -ForegroundColor Yellow
        Remove-Item $boostEnvScript -Recurse -Force -ErrorAction SilentlyContinue
    }
    if (Test-Path $boostMachineEnvScript) {
        Write-Host "  [DELETING] $boostMachineEnvScript" -ForegroundColor Yellow
        Remove-Item $boostMachineEnvScript -Recurse -Force -ErrorAction SilentlyContinue
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
    Get-ChildItem Env:\BOOST_PATH* | Remove-Item -ErrorAction SilentlyContinue
    Get-ChildItem Env:\BOOST_ROOT* | Remove-Item -ErrorAction SilentlyContinue
    Get-ChildItem Env:\BOOST_BIN* | Remove-Item -ErrorAction SilentlyContinue
    Get-ChildItem Env:\BOOST_INCLUDE_DIR* | Remove-Item -ErrorAction SilentlyContinue
    Get-ChildItem Env:\BOOST_LIBRARY_DIR* | Remove-Item -ErrorAction SilentlyContinue
    Get-ChildItem Env:\BOOST_VERSION* | Remove-Item -ErrorAction SilentlyContinue
    Get-ChildItem Env:\BOOST_MAJOR* | Remove-Item -ErrorAction SilentlyContinue
    Get-ChildItem Env:\BOOST_MINOR* | Remove-Item -ErrorAction SilentlyContinue
    Get-ChildItem Env:\BOOST_PATCH* | Remove-Item -ErrorAction SilentlyContinue
    Get-ChildItem Env:\BOOST_ABI_VERSION* | Remove-Item -ErrorAction SilentlyContinue
    Get-ChildItem Env:\BOOST_SO_VERSION* | Remove-Item -ErrorAction SilentlyContinue
    
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
    
    Write-Host "--- BOOST Purge Complete ---" -ForegroundColor Green
}

if ($boostForceCleanup) {
    Invoke-boostVersionPurge -InstallPath $boostInstallDir
}

# --- 3. Source Management ---
if (Test-Path $Source) {
    Write-Host "Syncing Boost ($Branch) at $Source..." -ForegroundColor Cyan
    Set-Location $Source
    git fetch --all
    git reset --hard "origin/$Branch"
    git pull --recurse-submodules --force
    $tagCommit = (& git rev-parse --verify HEAD).Trim()
} else {
    Write-Host "Cloning Boost ($Branch)..." -ForegroundColor Cyan
    git clone --recursive $RepoUrl $Source -b $Branch
    Set-Location $Source
    $tagCommit = (& git rev-parse --verify HEAD).Trim()
}

# --- 4. Bootstrap B2 ---
$bootstrapPath = Join-Path $Source "bootstrap.bat"
Write-Host "Bootstrapping Boost Build Engine..." -ForegroundColor Yellow
cmd /c $bootstrapPath

$b2Path = Join-Path $Source "b2.exe"
if (-not (Test-Path $b2Path)) {
    Write-Error "Boost bootstrap failed. b2.exe not found."
    Pop-Location; return
}

# --- 5. Clean Final Destination ---
if (Test-Path $boostInstallDir) {
    Write-Host "Wiping existing installation..." -ForegroundColor Yellow
    Remove-Item $boostInstallDir -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "[INSTALL] Creating fresh directory: $boostInstallDir" -ForegroundColor Cyan
New-Item -Path $boostInstallDir -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null

# Ensure fresh build directory
if (Test-Path $BuildDirShared) { Remove-Item $BuildDirShared -Recurse -Force -ErrorAction SilentlyContinue }
if (Test-Path $BuildDirStatic) { Remove-Item $BuildDirStatic -Recurse -Force -ErrorAction SilentlyContinue }
if (Test-Path $StageDir) { Remove-Item $StageDir -Recurse -Force -ErrorAction SilentlyContinue }
if (Test-Path $StageDir) { Remove-Item $StageDir -Recurse -Force -ErrorAction SilentlyContinue }
New-Item -Path $BuildDirShared -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null
New-Item -Path $BuildDirStatic -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null
New-Item -Path $StageDir -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null
New-Item -Path $StageDir -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null

# --- 6. Build Execution ---
# Note: Using address-model=64 for Win64
$CommonArgs = "-j$Cores", "address-model=64", "architecture=x86", "threading=multi", "runtime-link=shared", "--build-type=minimal", "stage", "install"
$Toolset = "clang-win"  # Changed from msvc

# --- Mapping Dependencies ---
$AdittionalArgs = @(
    # Compression (Iostreams)
    "-sZLIB_INCLUDE=$env:ZLIB_INCLUDE_DIR", "-sZLIB_LIBPATH=$env:ZLIB_LIBRARY_DIR", "-sZLIB_BINARY=$env:ZLIB_LIB_NAME",
    "-sBZIP2_INCLUDE=$env:BZIP2_INCLUDE_DIR", "-sBZIP2_LIBPATH=$env:BZIP2_LIBRARY_DIR", "-sBZIP2_BINARY=$env:BZIP2_LIB_NAME",
    "-sLZMA_INCLUDE=$env:LZMA_INCLUDE_DIR", "-sLZMA_LIBPATH=$env:LZMA_LIBRARY_DIR", "-sLZMA_BINARY=$env:LZMA_LIB_NAME",
    "-sZSTD_INCLUDE=$env:ZSTD_INCLUDE_DIR", "-sZSTD_LIBPATH=$env:ZSTD_LIBRARY_DIR", "-sZSTD_BINARY=$env:ZSTD_LIB_NAME",
    
    # Internationalization (Regex / Locale)
    "-sICU_PATH=$env:ICU_PATH", 
    "-sICONV_PATH=$env:ICONV_PATH",
    
    # XML Parsing (PropertyTree)
    "-sEXPAT_INCLUDE=$env:EXPAT_INCLUDE_DIR", "-sEXPAT_LIBPATH=$env:EXPAT_LIBRARY_DIR", "-sEXPAT_BINARY=$env:LIBEXPAT_LIB_NAME",
    
    # Parallelism (Context / Fiber / Thread)
    "-sTBB_INCLUDE=$env:TBB_INCLUDE_DIR", "-sTBB_LIBPATH=$env:TBB_LIBRARY_DIR", "-sTBB_BINARY=$env:TBB_LIB_NAME",
    
    # Python Support
    "--with-python",
    "-sPYTHON_ROOT=$env:PYTHON_PATH",
    "-sPYTHON_VERSION=$env:PYTHON_ABI_VERSION"
)

# STAGE 1: Static Libraries (staged to stage/lib)
Write-Host "Building Boost Static Libraries..." -ForegroundColor Cyan
cmd /c $b2Path $CommonArgs cstd=17 cxxstd=20 toolset=$Toolset link=static --build-dir="$BuildDirStatic" --stagedir="$StageDir" --prefix="$boostInstallDir" $AdittionalArgs
if ($LASTEXITCODE -ne 0) { 
    Write-Warning "Boost Static build finished with exit code $LASTEXITCODE. Checking for output..."
    if (-not (Test-Path "$boostInstallDir\lib")) { Write-Error "Static Build Failed"; Pop-Location; return }
}

# STAGE 2: Shared Libraries (DLLs)
Write-Host "Building Boost Shared Libraries (DLLs)..." -ForegroundColor Cyan
cmd /c $b2Path $CommonArgs cstd=17 cxxstd=20 toolset=$Toolset link=shared --build-dir="$BuildDirShared" --stagedir="$StageDir" --prefix="$boostInstallDir" $AdittionalArgs
if ($LASTEXITCODE -ne 0) { 
    Write-Warning "Boost Shared build finished with exit code $LASTEXITCODE. Checking for output..."
    if (-not (Test-Path "$boostInstallDir\lib")) { Write-Error "Shared Build Failed"; Pop-Location; return }
}

Write-Host "Successfully built and installed boost to $boostInstallDir!" -ForegroundColor Green

# Cleanup temporary build debris
<# Remove-Item $BuildDirShared -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item $BuildDirStatic -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item $StageDir -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item $StageDir -Recurse -Force -ErrorAction SilentlyContinue #>

# --- 6.5. Post-Build: Migrate DLLs to \bin ---
# Generate Environment Helper with Clean Paths
$boostInstallDir = $boostInstallDir.TrimEnd('\')
$boostIncludeDir = Join-Path $boostInstallDir "include"
$boostLibDir = Join-Path $boostInstallDir "lib"
$boostBinPath = Join-Path $boostInstallDir "bin"
$boostCMakePath  = $boostInstallDir.Replace('\', '/')

$libs = Get-ChildItem -Path $boostLibDir -Filter "*.lib"
$dlls = Get-ChildItem -Path $boostLibDir -Filter "*.dll"
$pdbs = Get-ChildItem -Path $boostLibDir -Filter "*.pdb"
$versionFile = Join-Path $boostInstallDir "version.json"

if (($libs.Count -gt 0) -or ($dlls.Count -gt 0) -or ($pdbs.Count -gt 0)) {
    $boostJamFile = Join-Path $Source "Jamroot"
    $boostCMakeFile = Join-Path $Source "CMakeLists.txt"
    $localVersion = "0.0.0"
    $rawVersion = $Branch
    $binaryversion = "0"

    if (Test-Path $boostJamFile) {
        # Extract version from: constant BOOST_VERSION : 1.91.0 ;
        $content = Get-Content $boostJamFile
        
        # Regex breakdown:
        # constant BOOST_VERSION  -> matches literal text
        # \s+:\s+                 -> matches the colon surrounded by spaces
        # ([\d\.]+)               -> captures digits and dots (the version)
        # \s+;                    -> matches trailing space and semicolon
        $versionMatch = ($content | Select-String 'constant\s+BOOST_VERSION\s+:\s+([\d\.]+)\s+;').Matches.Groups[1].Value
    
        if ($versionMatch) {
            $localVersion = $versionMatch
            $rawVersion = $localVersion
            Write-Host "[VERSION] Detected Boost: $localVersion" -ForegroundColor Cyan
        }
    } elseif (Test-Path $boostCMakeFile) {
        # Extract version from: project(Boost VERSION 1.91.0 LANGUAGES CXX)
        $content = Get-Content $boostCMakeFile
        
        # Regex Breakdown:
        # project\(Boost  -> Matches literal 'project(Boost'
        # .*?VERSION\s+  -> Non-greedy match until it hits 'VERSION' followed by space
        # ([\d\.]+)      -> Captures the version digits and dots
        # [^\d\.]        -> Stop capturing when hitting a non-digit/non-dot (like a space or closing paren)
        $versionMatch = ($content | Select-String 'project\(Boost.*?VERSION\s+([\d\.]+)').Matches.Groups[1].Value
    
        if ($versionMatch) {
            $localVersion = $versionMatch
            $rawVersion = $localVersion
            $binaryversion = ([version]$localVersion).Major
            Write-Host "[VERSION] Detected Boost (CMake): $localVersion" -ForegroundColor Cyan
        }
    }
    
    # Save new version state
    $boostVersion = $localVersion
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

    # Construct the include path based on version
    if ($localVersion -match '^(\d+)\.(\d+)') {
        $major = $Matches[1]
        $minor = $Matches[2]
        
        # Construct the folder segment: boost-1_91
        $boostFolderName = "boost-$major`_$minor"
        
        # Final path: *\boost\include\boost-1_91
        $boostIncludeDir = Join-Path $boostInstallDir "include\$boostFolderName"
        
        Write-Host "[PATHS] Boost-style include set to: $boostIncludeDir" -ForegroundColor Cyan
    } else {
        Write-Error "Could not parse Major.Minor from version: $localVersion"
    }

    if (-not (Test-Path $boostBinPath)) { New-Item -Path $boostBinPath -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null }

    Write-Host "Migrating Boost DLLs from \lib to \bin..." -ForegroundColor Cyan

    if ($dlls.Count -gt 0) {
        foreach ($dll in $dlls) {
            Move-Item -Path $dll.FullName -Destination $boostBinPath -Force -ErrorAction SilentlyContinue
        }
    } else {
        Write-Host "No DLLs found in \lib. They may already be in \bin or build failed." -ForegroundColor Yellow
    }

    if ($pdbs.Count -gt 0) {
        foreach ($pdb in $pdbs) {
            Move-Item -Path $pdb.FullName -Destination $boostBinPath -Force -ErrorAction SilentlyContinue
        }
    } else {
        Write-Host "No PDBs found in \lib. They may already be in \bin or build failed." -ForegroundColor Yellow
    }

    # --- 7. Create Environment Helper ---
    Write-Host "Generating environment helper script..." -ForegroundColor Cyan
    $EnvContent = @'
# Boost Environment Setup
$boostroot = "VALUE_ROOT_PATH"
$boostinclude = "VALUE_INCLUDE_PATH"
$boostlibrary = "VALUE_LIB_PATH"
$boostbin = "VALUE_BIN_PATH"
$boostversion = "VALUE_VERSION"
$boostabiversion = "VALUE_ABI_VERSION"
$boostsoversion = "VALUE_SO_VERSION"
$boostlibname = "VALUE_LIB_NAME"
$boostcmakepath = "VALUE_CMAKE_PATH"
$env:BOOST_PATH = $boostroot
$env:BOOST_ROOT = $boostroot
$env:BOOST_BIN = $boostbin
$env:BOOST_INCLUDE_DIR = $boostinclude
$env:BOOST_LIBRARY_DIR = $boostlibrary
$env:BOOST_LIB_NAME = $boostlibname
$env:BOOST_VERSION = $boostversion
$env:BOOST_MAJOR = ([version]$boostversion).Major
$env:BOOST_MINOR = ([version]$boostversion).Minor
$env:BOOST_PATCH = ([version]$boostversion).Patch
$env:BOOST_ABI_VERSION = $boostabiversion
$env:BOOST_SO_VERSION = $boostsoversion
if ($env:CMAKE_PREFIX_PATH -notlike "*$boostcmakepath*") { $env:CMAKE_PREFIX_PATH = $boostcmakepath + ";" + $env:CMAKE_PREFIX_PATH; $env:CMAKE_PREFIX_PATH = ($env:CMAKE_PREFIX_PATH).Replace(";;", ";") }
if ($env:INCLUDE -notlike "*$boostinclude*") { $env:INCLUDE = $boostinclude + ";" + $env:INCLUDE; $env:INCLUDE = ($env:INCLUDE).Replace(";;", ";") }
if ($env:LIB -notlike "*$boostlibrary*") { $env:LIB = $boostlibrary + ";" + $env:LIB; $env:LIB = ($env:LIB).Replace(";;", ";") }
if ($env:PATH -notlike "*$boostbin*") { $env:PATH = $boostbin + ";" + $env:PATH; $env:PATH = ($env:PATH).Replace(";;", ";") }
Write-Host "boost Environment Loaded (Version: $boostversion) (Bin: $boostbin)" -ForegroundColor Green
Write-Host "BOOST_ROOT: $env:BOOST_ROOT" -ForegroundColor Gray
'@  -replace "VALUE_ROOT_PATH", $boostInstallDir `
    -replace "VALUE_INCLUDE_PATH", $boostIncludeDir `
    -replace "VALUE_LIB_PATH", $boostLibDir `
    -replace "VALUE_BIN_PATH", $boostBinPath `
    -replace "VALUE_VERSION", $boostVersion `
    -replace "VALUE_ABI_VERSION", $binaryversion `
    -replace "VALUE_SO_VERSION", $binaryversion `
    -replace "VALUE_LIB_NAME", $boostLibName `
    -replace "VALUE_CMAKE_PATH", $boostCMakePath

    $EnvContent | Out-File -FilePath $boostEnvScript -Encoding utf8
    Write-Host "Created: $boostEnvScript" -ForegroundColor Gray
    
    # Update Current Session
    if (Test-Path $boostEnvScript) { . $boostEnvScript } else {
        Write-Error "boost build install finished but $boostEnvScript was not created."
        Pop-Location; return
    }
    
    if ($boostWithMachineEnvironment)
    {
        # Generating Machine Environment wich add to the persist registry machine Environment
        $MachineEnvContent = @'
# boost Machine Environment Setup

# --- 0. Self-Elevation Logic ---
$IsAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$ScopeColor = "Cyan"

if (-not $IsAdmin) {
    Write-Host "Elevation required to set boost system variables. Relaunching as Administrator..." -ForegroundColor Yellow
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

$boostroot = "VALUE_ROOT_PATH"
$boostbin = "VALUE_BIN_PATH"
$boostversion = "VALUE_VERSION"

$TargetScope = if ($IsAdmin) { "Machine" } else { "User" }
$RegPath = if ($IsAdmin) { "System\CurrentControlSet\Control\Session Manager\Environment" } else { "Environment" }
$RegRoot = if ($IsAdmin) { "LocalMachine" } else { "CurrentUser" }

# Open the registry key once
$RegKey = [Microsoft.Win32.Registry]::$RegRoot.OpenSubKey($RegPath, $true)

# Open the registry key directly to read the RAW (unexpanded) string
$CurrentRawPath = $RegKey.GetValue("EXTCOMPLIBS_PATH", "", [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)

# Cleanup: Remove empty strings, any path containing $boostroot, and the current target (to avoid dups)
$CleanedPathList = $CurrentRawPath -split ';' | Where-Object { 
    -not [string]::IsNullOrWhitespace($_) -and 
    $_ -notlike "*$boostroot*"
}

$NewRawPath = ($CleanedPathList -join ";").Replace(";;", ";")

$TargetPath = $boostbin

# Rebuild
$NewRawPath = ($NewRawPath + ";" + $TargetPath + ";").Replace(";;", ";")
Write-Host "[UPDATED] ($TargetScope) '$boostbin' synced in EXTCOMPLIBS_PATH" -ForegroundColor $ScopeColor

# Save as ExpandString
$RegKey.SetValue("EXTCOMPLIBS_PATH", $NewRawPath, [Microsoft.Win32.RegistryValueKind]::ExpandString)
$env:EXTCOMPLIBS_PATH = $NewRawPath

$RegKey.Close()

$env:BOOST_ROOT = $boostroot
Write-Host "boost Environment Loaded (Version: $boostversion) (Bin: $boostbin)" -ForegroundColor Green
Write-Host "BOOST_ROOT: $env:BOOST_ROOT" -ForegroundColor Gray
'@  -replace "VALUE_ROOT_PATH", $boostInstallDir `
    -replace "VALUE_BIN_PATH", $boostBinPath `
    -replace "VALUE_VERSION", $boostVersion

        $MachineEnvContent | Out-File -FilePath $boostMachineEnvScript -Encoding utf8
        Write-Host "Created: $boostMachineEnvScript" -ForegroundColor Gray
        
        # --- Interaction: Prompt to apply persistent changes ---
        Write-Host ""
        $choice = Read-Host "Do you want to run the Machine Environment script now to persist boost changes to the Registry? (y/n)"
        if ($choice -eq 'y' -or $choice -eq 'Y') {
            Write-Host "Executing $boostMachineEnvScript..." -ForegroundColor Yellow
            try {
                # Start the generated script. It handles its own elevation logic.
                & $boostMachineEnvScript
            }
            catch {
                Write-Error "Failed to execute the Machine Environment script: $($_.Exception.Message)"
            }
        }
        else {
            Write-Host "Skipped persistent registry update. You can run it later at: $boostMachineEnvScript" -ForegroundColor Gray
        }
    }
    
    # --- Return to Start ---
    Pop-Location
    Write-Host "Successfully Done! and returned to: $(Get-Location)" -ForegroundColor DarkGreen
} else {
    Write-Error "boost *.libs was not found in the $boostLibDir folder."
    Pop-Location; return
}
