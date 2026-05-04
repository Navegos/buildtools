# SPDX-FileCopyrightText: Copyright (c) 2026 Navegos. @DevelVitorF. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
# project: buildtools
# file: x64-windows/build-openssl.ps1
# created: 2026-05-02
# lastModified: 2026-05-03

param (
    [Parameter(HelpMessage = "Base workspace path", Mandatory = $false)]
    [string]$workspacePath = $null,

    [Parameter(HelpMessage = "OpenSSL git repo url", Mandatory = $false)]
    [string]$gitUrl = "https://github.com/openssl/openssl.git",
    
    [Parameter(HelpMessage = "OpenSSL git branch to sync from", Mandatory = $false)]
    [string]$gitBranch = "master",

    [Parameter(HelpMessage = "Path for OpenSSL installation", Mandatory = $false)]
    [string]$opensslInstallDir = "$env:LIBRARIES_PATH\openssl",
    
    [Parameter(HelpMessage = "Path for OpenSSL configuration files directory", Mandatory = $false)]
    [string]$opensslConfigDir = "$env:LIBRARIES_PATH\ssl",

    [Parameter(HelpMessage = "Force a full purge of the local OpenSSL version before continuing", Mandatory = $false)]
    [switch]$forceCleanup,
    
    [Parameter(HelpMessage = "Add's OpenSSL Machine Environment Variables. Requires Machine Administrator Rights.", Mandatory = $false)]
    [switch]$withMachineEnvironment
)

# Capture parameters
$opensslWorkspacePath = $workspacePath
$opensslGitUrl = $gitUrl
$opensslGitBranch = $gitBranch
$opensslForceCleanup = $forceCleanup
$opensslWithMachineEnvironment = $withMachineEnvironment

if ([string]::IsNullOrWhitespace($env:ENVIRONMENT_PATH) -or -not (Test-Path $env:ENVIRONMENT_PATH) -or [string]::IsNullOrWhitespace($env:BINARIES_PATH) -or -not (Test-Path $env:BINARIES_PATH) -or [string]::IsNullOrWhitespace($env:LIBRARIES_PATH) -or -not (Test-Path $env:LIBRARIES_PATH)) {
    Write-Error "User Environment variables missing. With administrator privileges run adduserpaths.ps1 -LibrariesDir 'Path\for\Libraries' -BinariesDir 'Path\for\Binaries' -EnvironmentDir 'Path\for\Environment'"
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

# --- 4. Initialize Perl environment ---
if ([string]::IsNullOrWhitespace($env:BINARY_PERL) -or -not (Test-Path $env:BINARY_PERL)) {
    $perlEnvScript = Join-Path $EnvironmentDir "env-perl.ps1"
    if (Test-Path $perlEnvScript) { . $perlEnvScript }
    if ([string]::IsNullOrWhitespace($env:BINARY_PERL) -or -not (Test-Path $env:BINARY_PERL)) {
        $depperlEnvScript = Join-Path $PSScriptRoot "dep-perl.ps1"
        if (Test-Path $depperlEnvScript) { . $depperlEnvScript }
        else {
            Write-Error "CRITICAL: Cannot load perl environment. perl is missing and $depperlEnvScript was not found."
            return
        }
    }
}

# --- 5. Initialize NASM environment ---
if ([string]::IsNullOrWhitespace($env:BINARY_NASM) -or -not (Test-Path $env:BINARY_NASM)) {
    $nasmEnvScript = Join-Path $EnvironmentDir "env-nasm.ps1"
    if (Test-Path $nasmEnvScript) { . $nasmEnvScript }
    if ([string]::IsNullOrWhitespace($env:BINARY_NASM) -or -not (Test-Path $env:BINARY_NASM)) {
        $depnasmEnvScript = Join-Path $PSScriptRoot "dep-nasm.ps1"
        if (Test-Path $depnasmEnvScript) { . $depnasmEnvScript }
        else {
            Write-Error "CRITICAL: Cannot load nasm environment. nasm is missing and $depnasmEnvScript was not found."
            return
        }
    }
}

# --- 6. Initialize jom environment if missing ---
if ([string]::IsNullOrWhitespace($env:BINARY_JOM) -or -not (Test-Path $env:BINARY_JOM)) {
    $jomEnvScript = Join-Path $EnvironmentDir "env-jom.ps1"
    if (Test-Path $jomEnvScript) { . $jomEnvScript }
    if ([string]::IsNullOrWhitespace($env:BINARY_JOM) -or -not (Test-Path $env:BINARY_JOM)) {
        $depjomEnvScript = Join-Path $PSScriptRoot "dep-jom.ps1"
        if (Test-Path $depjomEnvScript) { . $depjomEnvScript }
        else {
            Write-Error "CRITICAL: Cannot load jom environment. jom is missing and $depjomEnvScript was not found."
            return
        }
    }
}

$RootopensslInstallDir = Split-Path -Path $opensslInstallDir -Parent
$RootopensslWorkspacePath = if ([string]::IsNullOrWhitespace($opensslWorkspacePath)) { Get-Location } else { $opensslWorkspacePath }
$RootPath = $RootopensslWorkspacePath

# Load Zlib requirement
if ([string]::IsNullOrWhiteSpace($env:SHARED_LIB_ZLIB) -or -not (Test-Path $env:SHARED_LIB_ZLIB)) {
    $zlibEnvScript = Join-Path $EnvironmentDir "env-zlib.ps1"
    if (Test-Path $zlibEnvScript) { . $zlibEnvScript }
    if ([string]::IsNullOrWhiteSpace($env:SHARED_LIB_ZLIB) -or -not (Test-Path $env:SHARED_LIB_ZLIB)) {
        $zlibBuildScript = Join-Path $PSScriptRoot "build-zlib.ps1"
        if (Test-Path $zlibBuildScript) {
            $zlibInstallDir = Join-Path $RootopensslInstallDir "zlib"
            . $zlibBuildScript -workspacePath $RootopensslWorkspacePath -zlibInstallDir $zlibInstallDir
        }
        else {
            Write-Error "CRITICAL: Cannot build zlib. zlib is missing and $zlibBuildScript was not found."
            return
        }
    }
}

# Load Zstd requirement
if ([string]::IsNullOrWhiteSpace($env:SHARED_LIB_ZSTD) -or -not (Test-Path $env:SHARED_LIB_ZSTD)) {
    $zstdEnvScript = Join-Path $EnvironmentDir "env-zstd.ps1"
    if (Test-Path $zstdEnvScript) { . $zstdEnvScript }
    if ([string]::IsNullOrWhiteSpace($env:SHARED_LIB_ZSTD) -or -not (Test-Path $env:SHARED_LIB_ZSTD)) {
        $zstdBuildScript = Join-Path $PSScriptRoot "build-zstd.ps1"
        if (Test-Path $zstdBuildScript) {
            $zstdInstallDir = Join-Path $RootopensslInstallDir "zstd"
            . $zstdBuildScript -workspacePath $RootopensslWorkspacePath -zstdInstallDir $zstdInstallDir
        }
        else {
            Write-Error "CRITICAL: Cannot build zstd. zstd is missing and $zstdBuildScript was not found."
            return
        }
    }
}

# Load Brotli requirement
if ([string]::IsNullOrWhiteSpace($env:SHARED_LIB_BROTLI_COMMON) -or -not (Test-Path $env:SHARED_LIB_BROTLI_COMMON)) {
    $brotliEnvScript = Join-Path $EnvironmentDir "env-brotli.ps1"
    if (Test-Path $brotliEnvScript) { . $brotliEnvScript }
    if ([string]::IsNullOrWhiteSpace($env:SHARED_LIB_BROTLI_COMMON) -or -not (Test-Path $env:SHARED_LIB_BROTLI_COMMON)) {
        $brotliBuildScript = Join-Path $PSScriptRoot "build-brotli.ps1"
        if (Test-Path $brotliBuildScript) {
            $brotliInstallDir = Join-Path $RootopensslInstallDir "brotli"
            . $brotliBuildScript -workspacePath $RootopensslWorkspacePath -brotliInstallDir $brotliInstallDir
        }
        else {
            Write-Error "CRITICAL: Cannot build brotli. brotli is missing and $brotliBuildScript was not found."
            return
        }
    }
}

Push-Location $RootPath

$Source         = Join-Path $RootPath "openssl"
$BuildDirShared = Join-Path $Source "build_shared"
$BuildDirStatic = Join-Path $Source "build_static"
$RepoUrl        = $opensslGitUrl
$Branch         = $opensslGitBranch
$Cores          = [int]$env:NUMBER_OF_PROCESSORS / 2
$tag_name       = $Branch
$url            = $RepoUrl

# if Symlink present delete
$GlobalBinDir = "$env:BINARIES_PATH"
$openssltools = @("openssl.exe")

$opensslEnvScript = Join-Path $EnvironmentDir "env-openssl.ps1"
$opensslMachineEnvScript = Join-Path $EnvironmentDir "machine-env-openssl.ps1"

# --- 1. Cleanup Mechanism (for existing installations) ---
function Invoke-OpenSSLVersionPurge {
    param ([string]$InstallPath)
    Write-Host "--- Initiating OpenSSL Purge ---" -ForegroundColor Cyan

    if ($opensslWithMachineEnvironment) {
        $opensslCleanMachineEnvScript = Join-Path $env:TEMP "clean-machine-env-openssl.ps1"

        # Generating Clean Machine Environment wich removes the persist registry machine Environment
        $CleanMachineEnvContent = @'
# OpenSSL Clean Machine Environment Setup

# --- 0. Self-Elevation Logic ---
$IsAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$ScopeColor = "Cyan"

if (-not $IsAdmin) {
    Write-Host "Elevation required to clean OpenSSL system variables. Relaunching as Administrator..." -ForegroundColor Yellow
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

$opensslroot = "VALUE_ROOT_PATH"

$TargetScope = if ($IsAdmin) { "Machine" } else { "User" }
$RegPath = if ($IsAdmin) { "System\CurrentControlSet\Control\Session Manager\Environment" } else { "Environment" }
$RegRoot = if ($IsAdmin) { "LocalMachine" } else { "CurrentUser" }

# 1. Registry Cleanup (EXTCOMPLIBS_PATH)
$RegKey = [Microsoft.Win32.Registry]::$RegRoot.OpenSubKey($RegPath, $true)
$RawPath = $RegKey.GetValue("EXTCOMPLIBS_PATH", "", [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)

# Cleanup: Remove empty strings, any path containing $opensslroot
$CleanPath = ($RawPath -split ';' | Where-Object { $_ -notlike "*$opensslroot*" }) -join ";"

$RegKey.SetValue("EXTCOMPLIBS_PATH", $CleanPath, [Microsoft.Win32.RegistryValueKind]::ExpandString)
$env:EXTCOMPLIBS_PATH = $CleanPath

$RegKey.Close()

Write-Host "[REMOVED] ($TargetScope) all '*$opensslroot*' removed from EXTCOMPLIBS_PATH" -ForegroundColor $ScopeColor
'@  -replace "VALUE_ROOT_PATH", $InstallPath

        $CleanMachineEnvContent | Out-File -FilePath $opensslCleanMachineEnvScript -Encoding utf8
        Write-Host "Created: $opensslCleanMachineEnvScript" -ForegroundColor Gray
        
        # --- Interaction: Prompt to remove persistent changes ---
        Write-Host ""
        $choice = Read-Host "Administrator rights required to Clean Machine Environment OpenSSL changes? (y/n)"
        if ($choice -eq 'y' -or $choice -eq 'Y') {
            Write-Host "Executing $opensslCleanMachineEnvScript..." -ForegroundColor Yellow
            try {
                & $opensslCleanMachineEnvScript
            }
            catch {
                Write-Error "Failed to execute the Clean Machine Environment script: $($_.Exception.Message)"
                Pop-Location; return
            }
        }
        else {
            Write-Error "Skipped Clean Machine Environment OpenSSL changes."
            Pop-Location; return
        }

        Remove-Item $opensslCleanMachineEnvScript -Recurse -Force -ErrorAction SilentlyContinue
    }

    # 2. Filesystem Clean (Requires checking for locked files)
    if (Test-Path $opensslEnvScript) {
        Write-Host "  [DELETING] $opensslEnvScript" -ForegroundColor Yellow
        Remove-Item $opensslEnvScript -Recurse -Force -ErrorAction SilentlyContinue
    }
    if (Test-Path $opensslMachineEnvScript) {
        Write-Host "  [DELETING] $opensslMachineEnvScript" -ForegroundColor Yellow
        Remove-Item $opensslMachineEnvScript -Recurse -Force -ErrorAction SilentlyContinue
    }
    if (Test-Path $InstallPath) {
        Write-Host "  [DELETING] $InstallPath" -ForegroundColor Yellow
        Remove-Item $InstallPath -Recurse -Force -ErrorAction SilentlyContinue
    }
    if (Test-Path $Source) {
        Write-Host "  [DELETING] $Source" -ForegroundColor Yellow
        Remove-Item $Source -Recurse -Force -ErrorAction SilentlyContinue
    }
    
    foreach ($openssltool in $openssltools) {
        $target = Join-Path $GlobalBinDir $openssltool
        if (Test-Path $target) { Remove-Item $target -Force -ErrorAction SilentlyContinue; Write-Host "  [REMOVED] Link: $openssltool" -ForegroundColor Gray }
    }
    
    # remove local Env variables for current session
    Get-ChildItem Env:\OPENSSL_* | ForEach-Object { Remove-Item Env:\$($_.Name) -ErrorAction SilentlyContinue }
    Get-ChildItem Env:\BINARY_LIB_CRYPTO* | ForEach-Object { Remove-Item Env:\$($_.Name) -ErrorAction SilentlyContinue }
    Get-ChildItem Env:\SHARED_LIB_CRYPTO* | ForEach-Object { Remove-Item Env:\$($_.Name) -ErrorAction SilentlyContinue }
    Get-ChildItem Env:\STATIC_LIB_CRYPTO* | ForEach-Object { Remove-Item Env:\$($_.Name) -ErrorAction SilentlyContinue }
    Get-ChildItem Env:\BINARY_LIB_SSL* | ForEach-Object { Remove-Item Env:\$($_.Name) -ErrorAction SilentlyContinue }
    Get-ChildItem Env:\SHARED_LIB_SSL* | ForEach-Object { Remove-Item Env:\$($_.Name) -ErrorAction SilentlyContinue }
    Get-ChildItem Env:\STATIC_LIB_SSL* | ForEach-Object { Remove-Item Env:\$($_.Name) -ErrorAction SilentlyContinue }

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
    
    Write-Host "--- OpenSSL Purge Complete ---" -ForegroundColor Green
}

if ($opensslForceCleanup) {
    Invoke-OpenSSLVersionPurge -InstallPath $opensslInstallDir
}

# --- 2. Source Management ---
if (Test-Path $Source) {
    Write-Host "Syncing OpenSSL ($Branch) at $Source..." -ForegroundColor Cyan
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
    Write-Host "Cloning OpenSSL ($Branch) into $Source..." -ForegroundColor Cyan
    git clone --recurse-submodules $RepoUrl $Source -b $Branch
    if ($LASTEXITCODE -ne 0) { Write-Error "Git clone failed."; Pop-Location; return }
    Set-Location $Source
    $tagCommit = (& git rev-parse --verify HEAD).Trim()
}

# --- 3. Clean Final Destination ---
if (Test-Path $opensslInstallDir) {
    Write-Host "[CLEANUP] Removing existing OpenSSL installation at $opensslInstallDir..." -ForegroundColor Yellow
    Remove-Item -Path $opensslInstallDir -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "[INSTALL] Creating fresh directory: $opensslInstallDir" -ForegroundColor Cyan
New-Item -Path $opensslInstallDir -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null

# we don't whant to erase configs if they exist, but we want to ensure the folder is there
if (-not (Test-Path $opensslConfigDir)) {
    Write-Host "[CONFIG] Creating OpenSSL config directory: $opensslConfigDir" -ForegroundColor Cyan
    New-Item -Path $opensslConfigDir -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null
}

# Ensure fresh build directory
if (Test-Path $BuildDirShared) { Remove-Item $BuildDirShared -Recurse -Force -ErrorAction SilentlyContinue }
if (Test-Path $BuildDirStatic) { Remove-Item $BuildDirStatic -Recurse -Force -ErrorAction SilentlyContinue }
New-Item -Path $BuildDirShared -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null
New-Item -Path $BuildDirStatic -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null

# Workaround for OpenSSL out-of-tree build bug when no-apps is specified
New-Item -Path (Join-Path $BuildDirShared "apps\include") -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null
New-Item -Path (Join-Path $BuildDirStatic "apps\include") -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null

$CommonConfigureArgs = @(
    "VC-WIN64A",
    "CC=clang-cl",
    "CXX=clang-cl",
    "AR=llvm-lib",
    "/MD",
    "-D_CRT_SECURE_NO_WARNINGS=1",
    "zlib", "enable-zlib", "enable-zlib-dynamic",
    "enable-zstd", "enable-zstd-dynamic",
    "enable-brotli", "enable-brotli-dynamic",
    "enable-fips", "enable-acvp-tests",
    "threads",
    "no-tests", "no-docs",
    "--with-rand-seed=os,rdcpu",
    "--with-zlib-include=$($env:ZLIB_INCLUDE_DIR -replace '\\', '/')",
    "--with-zlib-lib=$($env:SHARED_LIB_ZLIB -replace '\\', '/')",
    "--with-brotli-include=$($env:BROTLI_INCLUDE_DIR -replace '\\', '/')",
    "--with-brotli-lib=$($env:BROTLI_LIBRARY_DIR -replace '\\', '/')",
    "--with-zstd-include=$($env:ZSTD_INCLUDE_DIR -replace '\\', '/')",
    "--with-zstd-lib=$($env:SHARED_LIB_ZSTD -replace '\\', '/')",
    "--release",
    "--prefix=$($opensslInstallDir -replace '\\', '/')",
    "--openssldir=$($opensslConfigDir -replace '\\', '/')"
)

# --- 9. STAGE 1: Build Static Libraries ---
Write-Host "Building OpenSSL Static..." -ForegroundColor Cyan
Set-Location $BuildDirStatic

$StaticConfigureArgs = $CommonConfigureArgs + @(
    "no-shared",
    "no-apps"
)

perl (("$Source\Configure") -replace '\\', '/') @StaticConfigureArgs

if ($LASTEXITCODE -ne 0) { Write-Error "OpenSSL Static configuration failed."; Pop-Location; return }

Write-Host "Resolving dependencies sequentially to avoid parallel build race conditions..." -ForegroundColor Gray
# Touch makefile to prevent reconfigure race condition in jom
if (Test-Path "makefile") { (Get-Item "makefile").LastWriteTime = (Get-Date) }
jom -j 1 depend

Write-Host "Building static lib..." -ForegroundColor Green
jom -j $Cores

if ($LASTEXITCODE -ne 0) { Write-Error "OpenSSL Static Build failed with exit code $LASTEXITCODE"; Pop-Location; return }

Write-Host "Installing static lib to $opensslInstallDir..." -ForegroundColor Green
# Install must be sequential
jom -j 1 install

if ($LASTEXITCODE -ne 0) { Write-Error "OpenSSL Static Install failed with exit code $LASTEXITCODE"; Pop-Location; return }

# --- 9.5. Rename Static Libraries (Suffix '_static') ---
Write-Host "Applying '_static' suffix to static libs..." -ForegroundColor Gray
Get-ChildItem -Path "$opensslInstallDir\lib\*.lib" | Where-Object { $_.BaseName -notlike "*_static" } | ForEach-Object {
    $newName = $_.BaseName + "_static" + $_.Extension
    Move-Item -Path $_.FullName -Destination (Join-Path $_.DirectoryName $newName) -Force -ErrorAction SilentlyContinue
    Write-Host "  -> $newName" -ForegroundColor DarkGray
}

# --- 10. STAGE 2: Build Shared Libraries (DLLs + Programs) ---
Write-Host "Building OpenSSL Shared (DLL)..." -ForegroundColor Cyan
Set-Location $BuildDirShared

$SharedConfigureArgs = $CommonConfigureArgs + @(
    "shared",
    "LD=lld-link"
)

perl (("$Source\Configure") -replace '\\', '/') @SharedConfigureArgs

if ($LASTEXITCODE -ne 0) { Write-Error "OpenSSL Shared configuration failed."; Pop-Location; return }

Write-Host "Resolving dependencies sequentially to avoid parallel build race conditions..." -ForegroundColor Gray
# Touch makefile to prevent reconfigure race condition in jom
if (Test-Path "makefile") { (Get-Item "makefile").LastWriteTime = (Get-Date) }
jom -j 1 depend

Write-Host "Building dynamic lib and apps..." -ForegroundColor Green
jom -j $Cores

if ($LASTEXITCODE -ne 0) { Write-Error "OpenSSL Shared Build failed with exit code $LASTEXITCODE"; Pop-Location; return }

Write-Host "Installing dynamic lib and apps to $opensslInstallDir..." -ForegroundColor Green
# Install must be sequential
jom -j 1 install

if ($LASTEXITCODE -ne 0) { Write-Error "OpenSSL Shared Install failed with exit code $LASTEXITCODE"; Pop-Location; return }

Write-Host "Successfully built and installed OpenSSL to $opensslInstallDir!" -ForegroundColor Green

# Cleanup temporary build debris
Set-Location $Source
Remove-Item $BuildDirShared -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item $BuildDirStatic -Recurse -Force -ErrorAction SilentlyContinue

# Generate Environment Helper with Clean Paths
$opensslInstallDir = $opensslInstallDir.TrimEnd('\')
$opensslIncludeDir = Join-Path $opensslInstallDir "include"
$opensslLibDir = Join-Path $opensslInstallDir "lib"
$opensslBinPath = Join-Path $opensslInstallDir "bin"
$opensslCMakePath = $opensslInstallDir.Replace('\', '/')

$opensslExePath = Join-Path $opensslBinPath "openssl.exe"

$StaticLibCrypto = Join-Path $opensslLibDir "libcrypto_static.lib"
$SharedLibCrypto = Join-Path $opensslLibDir "libcrypto.lib"
$BinaryLibCrypto = Join-Path $opensslBinPath "libcrypto.dll"

$StaticLibSSL = Join-Path $opensslLibDir "libssl_static.lib"
$SharedLibSSL = Join-Path $opensslLibDir "libssl.lib"
$BinaryLibSSL = Join-Path $opensslBinPath "libssl.dll"
$versionFile = Join-Path $opensslInstallDir "version.json"

foreach ($openssltool in $openssltools) {
    $target = Join-Path $GlobalBinDir $openssltool
    if (Test-Path $target) { Remove-Item $target -Force -ErrorAction SilentlyContinue }
}

if ((Test-Path $StaticLibCrypto) -or (Test-Path $SharedLibCrypto) -or (Test-Path $BinaryLibCrypto)) {
    $localVersion = "0.0.0"
    $rawVersion = $Branch
    $binaryversion = "0"
    $major = "0"
    $minor = "0"
    $patch = "0"

    $versionOutput = $null
    $cmdExitCode = 1
    if (Test-Path $opensslExePath) {
        $versionOutput = & $opensslExePath version 2>&1
        $cmdExitCode = $LASTEXITCODE
        if ($null -ne $versionOutput) { $versionOutput = ($versionOutput -join "`n").Trim() }
    }

    if ($cmdExitCode -eq 0 -and -not [string]::IsNullOrWhiteSpace($versionOutput) -and $versionOutput -match 'OpenSSL\s+([\d\.]+)') {
        $rawVersion = $versionOutput.Split("`n")[0].Trim()
        $localVersion = $Matches[1]
        $versionParts = $localVersion -split '\.'
        if ($versionParts.Count -ge 3) {
            $major = $versionParts[0]
            $minor = $versionParts[1]
            $patch = $versionParts[2]
            $binaryversion = $major
            Write-Host "[VERSION] Detected OpenSSL (Binary): $rawVersion" -ForegroundColor Cyan
        }
    }

    if ($localVersion -eq "0.0.0") {
        # Determine binary version from include/openssl/opensslv.h
        $opensslHeader = Join-Path $opensslIncludeDir "openssl\opensslv.h"
        if (Test-Path $opensslHeader) {
            $headerContent = Get-Content $opensslHeader
            $majorMatch = $headerContent | Select-String '#\s*define\s+OPENSSL_VERSION_MAJOR\s+(\d+)' | Select-Object -First 1
            $minorMatch = $headerContent | Select-String '#\s*define\s+OPENSSL_VERSION_MINOR\s+(\d+)' | Select-Object -First 1
            $patchMatch = $headerContent | Select-String '#\s*define\s+OPENSSL_VERSION_PATCH\s+(\d+)' | Select-Object -First 1
        
            if ($majorMatch -and $minorMatch -and $patchMatch) {
                $major = $majorMatch.Matches.Groups[1].Value
                $minor = $minorMatch.Matches.Groups[1].Value
                $patch = $patchMatch.Matches.Groups[1].Value
                $localVersion = "$major.$minor.$patch"
                $rawVersion = $localVersion
                $binaryversion = $major
                Write-Host "[VERSION] Detected OpenSSL (Header): $localVersion" -ForegroundColor Cyan
            }
        }
    }
    
    $FindCryptoDll = Get-ChildItem -Path $opensslBinPath -Filter "libcrypto*.dll" | Select-Object -First 1
    if ($FindCryptoDll) { $BinaryLibCrypto = $FindCryptoDll.FullName }

    $FindSSLDll = Get-ChildItem -Path $opensslBinPath -Filter "libssl*.dll" | Select-Object -First 1
    if ($FindSSLDll) { $BinaryLibSSL = $FindSSLDll.FullName }

    $opensslVersion = $localVersion
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

$EnvContent = @'
# OPENSSL Environment Setup
$opensslroot = "VALUE_ROOT_PATH"
$opensslbin = "VALUE_BIN_PATH"
$opensslexe = "VALUE_EXE_PATH"
$opensslversion = "VALUE_VERSION"
$opensslinclude = "VALUE_INCLUDE_PATH"
$openssllibrary = "VALUE_LIB_PATH"
$opensslabiversion = "VALUE_ABI_VERSION"
$opensslsoversion = "VALUE_SO_VERSION"
$cryptobinary = "VALUE_CRYPTO_BINARY"
$cryptoshared = "VALUE_CRYPTO_SHARED"
$cryptostatic = "VALUE_CRYPTO_STATIC"
$sslbinary = "VALUE_SSL_BINARY"
$sslshared = "VALUE_SSL_SHARED"
$sslstatic = "VALUE_SSL_STATIC"
$opensslcmakepath = "VALUE_CMAKE_PATH"
$env:OPENSSL_PATH = $opensslroot
$env:OPENSSL_ROOT_DIR = $opensslroot
$env:OPENSSL_ROOT = $opensslroot
$env:OPENSSL_BIN = $opensslbin
$env:OPENSSL_INCLUDE_DIR = $opensslinclude
$env:OPENSSL_LIBRARY_DIR = $openssllibrary
$env:BINARY_OPENSSL = $opensslexe
$env:BINARY_LIB_CRYPTO = $cryptobinary
$env:SHARED_LIB_CRYPTO = $cryptoshared
$env:STATIC_LIB_CRYPTO = $cryptostatic
$env:BINARY_LIB_SSL = $sslbinary
$env:SHARED_LIB_SSL = $sslshared
$env:STATIC_LIB_SSL = $sslstatic
$env:OPENSSL_VERSION = $opensslversion
$env:OPENSSL_MAJOR = "VALUE_MAJOR"
$env:OPENSSL_MINOR = "VALUE_MINOR"
$env:OPENSSL_PATCH = "VALUE_PATCH"
$env:OPENSSL_ABI_VERSION = $opensslabiversion
$env:OPENSSL_SO_VERSION = $opensslsoversion
if ($env:CMAKE_PREFIX_PATH -notlike "*$opensslcmakepath*") { $env:CMAKE_PREFIX_PATH = $opensslcmakepath + ";" + $env:CMAKE_PREFIX_PATH; $env:CMAKE_PREFIX_PATH = ($env:CMAKE_PREFIX_PATH).Replace(";;", ";") }
if ($env:INCLUDE -notlike "*$opensslinclude*") { $env:INCLUDE = $opensslinclude + ";" + $env:INCLUDE; $env:INCLUDE = ($env:INCLUDE).Replace(";;", ";") }
if ($env:LIB -notlike "*$openssllibrary*") { $env:LIB = $openssllibrary + ";" + $env:LIB; $env:LIB = ($env:LIB).Replace(";;", ";") }
if ($env:PATH -notlike "*$opensslbin*") { $env:PATH = $opensslbin + ";" + $env:PATH; $env:PATH = ($env:PATH).Replace(";;", ";") }
Write-Host "OpenSSL Environment Loaded (Version: $opensslversion) (Bin: $opensslbin)" -ForegroundColor Green
Write-Host "OPENSSL_ROOT: $env:OPENSSL_ROOT" -ForegroundColor Gray
'@  -replace "VALUE_BIN_PATH", $opensslBinPath `
    -replace "VALUE_EXE_PATH", $opensslExePath `
    -replace "VALUE_ROOT_PATH", $opensslInstallDir `
    -replace "VALUE_VERSION", $opensslVersion `
    -replace "VALUE_INCLUDE_PATH", $opensslIncludeDir `
    -replace "VALUE_LIB_PATH", $opensslLibDir `
    -replace "VALUE_ABI_VERSION", $binaryversion `
    -replace "VALUE_SO_VERSION", $binaryversion `
    -replace "VALUE_CRYPTO_SHARED", $SharedLibCrypto `
    -replace "VALUE_CRYPTO_BINARY", $BinaryLibCrypto `
    -replace "VALUE_CRYPTO_STATIC", $StaticLibCrypto `
    -replace "VALUE_SSL_SHARED", $SharedLibSSL `
    -replace "VALUE_SSL_BINARY", $BinaryLibSSL `
    -replace "VALUE_SSL_STATIC", $StaticLibSSL `
    -replace "VALUE_CMAKE_PATH", $opensslCMakePath `
    -replace "VALUE_MAJOR", $major `
    -replace "VALUE_MINOR", $minor `
    -replace "VALUE_PATCH", $patch

    $EnvContent | Out-File -FilePath $opensslEnvScript -Encoding utf8
    Write-Host "Created: $opensslEnvScript" -ForegroundColor Gray

    if (Test-Path $opensslEnvScript) { . $opensslEnvScript } else {
        Write-Error "OpenSSL build install finished but $opensslEnvScript was not created."
        Pop-Location; return
    }

    Write-Host "Creating global symlink to: $GlobalBinDir..." -ForegroundColor Cyan

    foreach ($openssltool in $openssltools) {
        $source = Join-Path $opensslBinPath $openssltool
        $target = Join-Path $GlobalBinDir $openssltool

        if (Test-Path $source) {
            if (Test-Path $target) { Remove-Item $target -Force -ErrorAction SilentlyContinue }
            try {
                New-Item -Path $target -ItemType SymbolicLink -Value $source -ErrorAction Stop | Out-Null
                Write-Host "[LINKED] $openssltool" -ForegroundColor Gray
            }
            catch {
                New-Item -Path $target -ItemType HardLink -Value $source | Out-Null
                Write-Host "[HARDLINKED] $openssltool (Global) -> $source" -ForegroundColor Gray
            }
        }
    }

    Write-Host "[LINKED] OpenSSL is now globally available via %BINARIES_PATH%" -ForegroundColor Green
    Write-Host "OpenSSL Version: $(& $opensslExePath version)" -ForegroundColor Gray

    if ($opensslWithMachineEnvironment)
    {
        # Generating Machine Environment wich add to the persist registry machine Environment
        $MachineEnvContent = @'
# OpenSSL Machine Environment Setup

# --- 0. Self-Elevation Logic ---
$IsAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$ScopeColor = "Cyan"

if (-not $IsAdmin) {
    Write-Host "Elevation required to set OpenSSL system variables. Relaunching as Administrator..." -ForegroundColor Yellow
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

$opensslroot = "VALUE_ROOT_PATH"
$opensslbin = "VALUE_BIN_PATH"
$opensslversion = "VALUE_VERSION"

$TargetScope = if ($IsAdmin) { "Machine" } else { "User" }
$RegPath = if ($IsAdmin) { "System\CurrentControlSet\Control\Session Manager\Environment" } else { "Environment" }
$RegRoot = if ($IsAdmin) { "LocalMachine" } else { "CurrentUser" }

$RegKey = [Microsoft.Win32.Registry]::$RegRoot.OpenSubKey($RegPath, $true)
$CurrentRawPath = $RegKey.GetValue("EXTCOMPLIBS_PATH", "", [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)

$CleanedPathList = $CurrentRawPath -split ';' | Where-Object { 
    -not [string]::IsNullOrWhitespace($_) -and 
    $_ -notlike "*$opensslroot*"
}

$NewRawPath = ($CleanedPathList -join ";").Replace(";;", ";")
$NewRawPath = ($NewRawPath + ";" + $opensslbin + ";").Replace(";;", ";")

Write-Host "[UPDATED] ($TargetScope) OpenSSL path synced in EXTCOMPLIBS_PATH" -ForegroundColor $ScopeColor

$RegKey.SetValue("EXTCOMPLIBS_PATH", $NewRawPath, [Microsoft.Win32.RegistryValueKind]::ExpandString)
$env:EXTCOMPLIBS_PATH = $NewRawPath

$RegKey.Close()

$env:OPENSSL_ROOT = $opensslroot
Write-Host "OpenSSL Environment Loaded (Version: $opensslversion) (Bin: $opensslbin)" -ForegroundColor Green
Write-Host "OPENSSL_ROOT: $env:OPENSSL_ROOT" -ForegroundColor Gray
'@  -replace "VALUE_ROOT_PATH", $opensslInstallDir `
    -replace "VALUE_BIN_PATH", $opensslBinPath `
    -replace "VALUE_VERSION", $opensslVersion

        $MachineEnvContent | Out-File -FilePath $opensslMachineEnvScript -Encoding utf8
        Write-Host "Created: $opensslMachineEnvScript" -ForegroundColor Gray
        
        Write-Host ""
        $choice = Read-Host "Do you want to run the Machine Environment script now to persist OpenSSL changes to the Registry? (y/n)"
        if ($choice -eq 'y' -or $choice -eq 'Y') {
            Write-Host "Executing $opensslMachineEnvScript..." -ForegroundColor Yellow
            try {
                & $opensslMachineEnvScript
            }
            catch {
                Write-Error "Failed to execute the Machine Environment script: $($_.Exception.Message)"
            }
        }
        else {
            Write-Host "Skipped persistent registry update. You can run it later at: $opensslMachineEnvScript" -ForegroundColor Gray
        }
    }

    # --- Return to Start ---
    Pop-Location
    Write-Host "Successfully Done! and returned to: $(Get-Location)" -ForegroundColor DarkGreen
} else {
    Write-Error "OpenSSL libraries were not found in the $opensslLibDir folder."
    $openssltools | ForEach-Object { 
        $globalLinkPath = Join-Path $GlobalBinDir $_
        if (Test-Path $globalLinkPath) {
            Write-Host "Cleaning up dead symlink at $globalLinkPath..." -ForegroundColor Yellow
            Remove-Item $globalLinkPath -Force -ErrorAction SilentlyContinue
        } 
    }
    Pop-Location; return
}
