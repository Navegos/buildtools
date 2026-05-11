# SPDX-FileCopyrightText: Copyright (c) 2026 Navegos. @DevelVitorF. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
# project: buildtools
# file: x64-windows/build-libtiff.ps1
# created: 2026-05-03
# lastModified: 2026-05-11

param (
    [Parameter(HelpMessage = "Base workspace path", Mandatory = $false)]
    [string]$workspacePath = $null,

    [Parameter(HelpMessage = "libtiff git repo url", Mandatory = $false)]
    [string]$gitUrl = "https://github.com/libsdl-org/libtiff.git",
    
    [Parameter(HelpMessage = "libtiff git branch to sync from", Mandatory = $false)]
    [string]$gitBranch = "master",

    [Parameter(HelpMessage = "Path for libtiff library storage", Mandatory = $false)]
    [string]$libtiffInstallDir = "$env:LIBRARIES_PATH\libtiff",
    
    [Parameter(HelpMessage = "Lib name, if it's building with a different name", Mandatory = $false)]
    [string]$libtiffLibName = "tiff",
    
    [Parameter(HelpMessage = "Force a full purge of the local libtiff version before continuing", Mandatory = $false)]
    [switch]$forceCleanup,
    
    [Parameter(HelpMessage = "Add's libtiff Machine Environment Variables.", Mandatory = $false)]
    [switch]$withMachineEnvironment
)

$libtiffWorkspacePath = $workspacePath
$libtiffGitUrl = $gitUrl
$libtiffGitBranch = $gitBranch
$libtiffForceCleanup = $forceCleanup
$libtiffWithMachineEnvironment = $withMachineEnvironment

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
$RootlibtiffInstallDir = Split-Path -Path $libtiffInstallDir -Parent
$RootlibtiffWorkspacePath = if ([string]::IsNullOrWhitespace($libtiffWorkspacePath)) { Get-Location } else { $libtiffWorkspacePath }

# Load Zlib requirement
if ([string]::IsNullOrWhiteSpace($env:SHARED_LIB_ZLIB) -or -not (Test-Path $env:SHARED_LIB_ZLIB)) {
    $zlibEnvScript = Join-Path $EnvironmentDir "env-zlib.ps1"
    if (Test-Path $zlibEnvScript) { . $zlibEnvScript }
    if ([string]::IsNullOrWhiteSpace($env:SHARED_LIB_ZLIB) -or -not (Test-Path $env:SHARED_LIB_ZLIB)) {
        $zlibBuildScript = Join-Path $PSScriptRoot "build-zlib.ps1"
        if (Test-Path $zlibBuildScript) {
            $zlibInstallDir = Join-Path $RootlibtiffInstallDir "zlib"
            . $zlibBuildScript -workspacePath $RootlibtiffWorkspacePath -zlibInstallDir $zlibInstallDir
        }
        else {
            Write-Error "CRITICAL: Cannot build zlib. zlib is missing and $zlibBuildScript was not found."
            return
        }
    }
}

# Load libdeflate requirement
if ([string]::IsNullOrWhiteSpace($env:SHARED_LIB_DEFLATE) -or -not (Test-Path $env:SHARED_LIB_DEFLATE)) {
    $libdeflateEnvScript = Join-Path $EnvironmentDir "env-libdeflate.ps1"
    if (Test-Path $libdeflateEnvScript) { . $libdeflateEnvScript }
    if ([string]::IsNullOrWhiteSpace($env:SHARED_LIB_DEFLATE) -or -not (Test-Path $env:SHARED_LIB_DEFLATE)) {
        $libdeflateBuildScript = Join-Path $PSScriptRoot "build-libdeflate.ps1"
        if (Test-Path $libdeflateBuildScript) {
            $libdeflateInstallDir = Join-Path $RootlibtiffInstallDir "libdeflate"
            . $libdeflateBuildScript -workspacePath $RootlibtiffWorkspacePath -libdeflateInstallDir $libdeflateInstallDir
        }
        else {
            Write-Error "CRITICAL: Cannot build libdeflate. libdeflate is missing and $libdeflateBuildScript was not found."
            return
        }
    }
}

# Load libjpeg requirement
if ([string]::IsNullOrWhiteSpace($env:SHARED_LIB_JPEG) -or -not (Test-Path $env:SHARED_LIB_JPEG)) {
    $libjpegEnvScript = Join-Path $EnvironmentDir "env-libjpeg.ps1"
    if (Test-Path $libjpegEnvScript) { . $libjpegEnvScript }
    if ([string]::IsNullOrWhiteSpace($env:SHARED_LIB_JPEG) -or -not (Test-Path $env:SHARED_LIB_JPEG)) {
        $libjpegBuildScript = Join-Path $PSScriptRoot "build-libjpeg.ps1"
        if (Test-Path $libjpegBuildScript) {
            $libjpegInstallDir = Join-Path $RootlibtiffInstallDir "libjpeg"
            . $libjpegBuildScript -workspacePath $RootlibtiffWorkspacePath -libjpegInstallDir $libjpegInstallDir
        }
        else {
            Write-Error "CRITICAL: Cannot build libjpeg. libjpeg is missing and $libjpegBuildScript was not found."
            return
        }
    }
}

# Load Lerc requirement
if ([string]::IsNullOrWhiteSpace($env:SHARED_LIB_LERC) -or -not (Test-Path $env:SHARED_LIB_LERC)) {
    $lercEnvScript = Join-Path $EnvironmentDir "env-lerc.ps1"
    if (Test-Path $lercEnvScript) { . $lercEnvScript }
    if ([string]::IsNullOrWhiteSpace($env:SHARED_LIB_LERC) -or -not (Test-Path $env:SHARED_LIB_LERC)) {
        $lercBuildScript = Join-Path $PSScriptRoot "build-lerc.ps1"
        if (Test-Path $lercBuildScript) {
            $lercInstallDir = Join-Path $RootlibtiffInstallDir "lerc"
            . $lercBuildScript -workspacePath $RootlibtiffWorkspacePath -lercInstallDir $lercInstallDir
        }
        else {
            Write-Error "CRITICAL: Cannot build lerc. lerc is missing and $lercBuildScript was not found."
            return
        }
    }
}

# Load Lzma requirement
if ([string]::IsNullOrWhiteSpace($env:SHARED_LIB_LZMA) -or -not (Test-Path $env:SHARED_LIB_LZMA)) {
    $lzmaEnvScript = Join-Path $EnvironmentDir "env-lzma.ps1"
    if (Test-Path $lzmaEnvScript) { . $lzmaEnvScript }
    if ([string]::IsNullOrWhiteSpace($env:SHARED_LIB_LZMA) -or -not (Test-Path $env:SHARED_LIB_LZMA)) {
        $lzmaBuildScript = Join-Path $PSScriptRoot "build-lzma.ps1"
        if (Test-Path $lzmaBuildScript) {
            $lzmaInstallDir = Join-Path $RootlibtiffInstallDir "lzma"
            . $lzmaBuildScript -workspacePath $RootlibtiffWorkspacePath -lzmaInstallDir $lzmaInstallDir
        }
        else {
            Write-Error "CRITICAL: Cannot build lzma. lzma is missing and $lzmaBuildScript was not found."
            return
        }
    }
}

# Load WebP requirement
if ([string]::IsNullOrWhiteSpace($env:SHARED_LIB_WEBP) -or -not (Test-Path $env:SHARED_LIB_WEBP)) {
    $libwebpEnvScript = Join-Path $EnvironmentDir "env-libwebp.ps1"
    if (Test-Path $libwebpEnvScript) { . $libwebpEnvScript }
    if ([string]::IsNullOrWhiteSpace($env:SHARED_LIB_WEBP) -or -not (Test-Path $env:SHARED_LIB_WEBP)) {
        $libwebpBuildScript = Join-Path $PSScriptRoot "build-libwebp.ps1"
        if (Test-Path $libwebpBuildScript) {
            $libwebpInstallDir = Join-Path $RootlibtiffInstallDir "libwebp"
            . $libwebpBuildScript -workspacePath $RootlibtiffWorkspacePath -libwebpInstallDir $libwebpInstallDir
        }
        else {
            Write-Error "CRITICAL: Cannot build libwebp. libwebp is missing and $libwebpBuildScript was not found."
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
            $zstdInstallDir = Join-Path $RootlibtiffInstallDir "zstd"
            . $zstdBuildScript -workspacePath $RootlibtiffWorkspacePath -zstdInstallDir $zstdInstallDir
        }
        else {
            Write-Error "CRITICAL: Cannot build zstd. zstd is missing and $zstdBuildScript was not found."
            return
        }
    }
}

$RootPath = if ([string]::IsNullOrWhitespace($RootlibtiffWorkspacePath)) { Get-Location } else { $RootlibtiffWorkspacePath }

Push-Location $RootPath

$Source         = Join-Path $RootPath "libtiff"
$BuildDirShared = Join-Path $Source "build_shared"
$BuildDirStatic = Join-Path $Source "build_static"
$RepoUrl        = $libtiffGitUrl
$Branch         = $libtiffGitBranch
$CMakeSource    = $Source
$tag_name       = $Branch
$url            = $RepoUrl

$libtiffEnvScript = Join-Path $EnvironmentDir "env-libtiff.ps1"
$libtiffMachineEnvScript = Join-Path $EnvironmentDir "machine-env-libtiff.ps1"

# --- 1. Cleanup Mechanism ---
function Invoke-libtiffVersionPurge {
    param ([string]$InstallPath)
    Write-Host "--- Initiating libtiff Purge ---" -ForegroundColor Cyan

    if ($libtiffWithMachineEnvironment) {
        $libtiffCleanMachineEnvScript = Join-Path $env:TEMP "clean-machine-env-libtiff.ps1"

        # Generating Clean Machine Environment wich removes the persist registry machine Environment
        $CleanMachineEnvContent = @'
# libtiff Clean Machine Environment Setup

# --- 0. Self-Elevation Logic ---
$IsAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$ScopeColor = "Cyan"

if (-not $IsAdmin) {
    Write-Host "Elevation required to clean libtiff system variables. Relaunching as Administrator..." -ForegroundColor Yellow
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

$libtiffroot = "VALUE_ROOT_PATH"

$TargetScope = if ($IsAdmin) { "Machine" } else { "User" }
$RegPath = if ($IsAdmin) { "System\CurrentControlSet\Control\Session Manager\Environment" } else { "Environment" }
$RegRoot = if ($IsAdmin) { "LocalMachine" } else { "CurrentUser" }

# 1. Registry Cleanup (EXTCOMPLIBS_PATH)
$RegKey = [Microsoft.Win32.Registry]::$RegRoot.OpenSubKey($RegPath, $true)

# Open the registry key directly to read the RAW (unexpanded) string
$RawPath = $RegKey.GetValue("EXTCOMPLIBS_PATH", "", [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)

# Cleanup: Remove empty strings, any path containing $libtiffroot,
$CleanPath = ($RawPath -split ';' | Where-Object { $_ -notlike "*$libtiffroot*" }) -join ";"

# Save as ExpandString
$RegKey.SetValue("EXTCOMPLIBS_PATH", $CleanPath, [Microsoft.Win32.RegistryValueKind]::ExpandString)
$env:EXTCOMPLIBS_PATH = $CleanPath

$RegKey.Close()

Write-Host "[REMOVED] ($TargetScope) all '*$libtiffroot*' removed from EXTCOMPLIBS_PATH" -ForegroundColor $ScopeColor
'@  -replace "VALUE_ROOT_PATH", $InstallPath

        $CleanMachineEnvContent | Out-File -FilePath $libtiffCleanMachineEnvScript -Encoding utf8
        Write-Host "Created: $libtiffCleanMachineEnvScript" -ForegroundColor Gray
        
        # --- Interaction: Prompt to remove persistent changes ---
        Write-Host ""
        $choice = Read-Host "Administrator rights required to Clean Machine Environment libtiff changes? (y/n)"
        if ($choice -eq 'y' -or $choice -eq 'Y') {
            Write-Host "Executing $libtiffCleanMachineEnvScript..." -ForegroundColor Yellow
            try {
                # Start the generated script. It handles its own elevation logic.
                & $libtiffCleanMachineEnvScript
            }
            catch {
                Write-Error "Failed to execute the Clean Machine Environment script: $($_.Exception.Message)"
                Pop-Location; return
            }
        }
        else {
            Write-Error "Skipped Clean Machine Environment libtiff changes."
            Pop-Location; return
        }

        # Cleanup
        Remove-Item $libtiffCleanMachineEnvScript -Recurse -Force -ErrorAction SilentlyContinue
    }

    # 2. Filesystem Clean (Requires checking for locked files)
    # delete everithing we create don't fail later
    if (Test-Path $libtiffEnvScript) {
        Write-Host "  [DELETING] $libtiffEnvScript" -ForegroundColor Yellow
        Remove-Item $libtiffEnvScript -Recurse -Force -ErrorAction SilentlyContinue
    }
    if (Test-Path $libtiffMachineEnvScript) {
        Write-Host "  [DELETING] $libtiffMachineEnvScript" -ForegroundColor Yellow
        Remove-Item $libtiffMachineEnvScript -Recurse -Force -ErrorAction SilentlyContinue
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
    Get-ChildItem Env:\LIBTIFF_* | ForEach-Object { Remove-Item Env:\$($_.Name) -ErrorAction SilentlyContinue }
    Get-ChildItem Env:\BINARY_LIB_TIFF* | ForEach-Object { Remove-Item Env:\$($_.Name) -ErrorAction SilentlyContinue }
    Get-ChildItem Env:\SHARED_LIB_TIFF* | ForEach-Object { Remove-Item Env:\$($_.Name) -ErrorAction SilentlyContinue }
    Get-ChildItem Env:\STATIC_LIB_TIFF* | ForEach-Object { Remove-Item Env:\$($_.Name) -ErrorAction SilentlyContinue }
    
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
    
    Write-Host "--- LIBTIFF Purge Complete ---" -ForegroundColor Green
}

if ($libtiffForceCleanup) {
    Invoke-libtiffVersionPurge -InstallPath $libtiffInstallDir
}

if (Test-Path $Source) {
    Write-Host "Syncing libtiff ($Branch) at $Source..." -ForegroundColor Cyan
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
    Write-Host "Cloning libtiff ($Branch) into $Source..." -ForegroundColor Cyan
    git clone --recurse-submodules $RepoUrl $Source -b $Branch
    if ($LASTEXITCODE -ne 0) { Write-Error "Git clone failed."; Pop-Location; return }
    Set-Location $Source
    $tagCommit = (& git rev-parse --verify HEAD).Trim()
}

# --- 8. Clean Final Destination ---
if (Test-Path $libtiffInstallDir) {
    Write-Host "Wiping existing installation..." -ForegroundColor Yellow
    Remove-Item $libtiffInstallDir -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "[INSTALL] Creating fresh directory: $libtiffInstallDir" -ForegroundColor Cyan
New-Item -Path $libtiffInstallDir -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null

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
    "-Dtiff-docs=OFF",
    "-Dtiff-tests=OFF",
    "-Dtiff-contrib=OFF",
    "-Dtiff-tools=OFF",
    "-Dtiff-install=ON",
    "-Dzlib=ON",
    "-Dlibdeflate=ON",
    "-Djpeg=ON",
    "-Dlzma=ON",
    "-Dlerc=ON",
    "-Dpixarlog=ON",
    "-Dwebp=ON",
    "-Dzstd=ON",
    "-DZSTD_HAVE_DECOMPRESS_STREAM=ON"
)

# --- STAGE 1: Build Static Libraries ---
Write-Host "Building Static..." -ForegroundColor Cyan
cmake $CommonCmakeArgs `
    -S "$CMakeSource" `
    -B "$BuildDirStatic" `
    -DCMAKE_INSTALL_PREFIX="$libtiffInstallDir" `
    -DBUILD_SHARED_LIBS=OFF `
    -DCMAKE_C_FLAGS="-DLZMA_API_STATIC -DZLIB_STATIC -Wno-deprecated-declarations -D_CRT_SECURE_NO_WARNINGS=1" `
    -DCMAKE_CXX_FLAGS="-DLZMA_API_STATIC -DZLIB_STATIC -Wno-deprecated-declarations -D_CRT_SECURE_NO_WARNINGS=1" `
    -DCMAKE_SHARED_LINKER_FLAGS="$($env:STATIC_LIB_SHARPYUV -replace '\\', '/')" `
    -DCMAKE_EXE_LINKER_FLAGS="$($env:STATIC_LIB_SHARPYUV -replace '\\', '/')" `
    -DZLIB_LIBRARY="$($env:STATIC_LIB_ZLIB -replace '\\', '/')" `
    -DDeflate_LIBRARY="$($env:STATIC_LIB_DEFLATE -replace '\\', '/')" `
    -DJPEG_LIBRARY="$($env:STATIC_LIB_JPEG -replace '\\', '/')" `
    -DLIBLZMA_LIBRARY="$($env:STATIC_LIB_LZMA -replace '\\', '/')" `
    -DLERC_LIBRARY="$($env:STATIC_LIB_LERC -replace '\\', '/')" `
    -DWebP_LIBRARY="$($env:STATIC_LIB_WEBP -replace '\\', '/')" `
    -DZSTD_LIBRARY="$($env:STATIC_LIB_ZSTD -replace '\\', '/')" `
    --no-warn-unused-cli
    
if ($LASTEXITCODE -ne 0) { Write-Error "libtiff CMake Static configuration failed."; Pop-Location; return }

Write-Host "Building and Installing static lib to $libtiffInstallDir..." -ForegroundColor Green
cmake --build "$BuildDirStatic" --target install --config Release --parallel

if ($LASTEXITCODE -ne 0) { Write-Error "libtiff Static Build failed with exit code $LASTEXITCODE"; Pop-Location; return }

# Rename static lib to libtiff_static.lib to avoid collision
Write-Host "Applying '_static' suffix to static libs..." -ForegroundColor Gray
Get-ChildItem -Path "$libtiffInstallDir\lib\*.lib" | ForEach-Object {
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
    -DCMAKE_INSTALL_PREFIX="$libtiffInstallDir" `
    -DBUILD_SHARED_LIBS=ON `
    -DCMAKE_C_FLAGS="-Wno-deprecated-declarations -D_CRT_SECURE_NO_WARNINGS=1" `
    -DCMAKE_CXX_FLAGS="-Wno-deprecated-declarations -D_CRT_SECURE_NO_WARNINGS=1" `
    -DCMAKE_SHARED_LINKER_FLAGS="$($env:SHARED_LIB_SHARPYUV -replace '\\', '/')" `
    -DCMAKE_EXE_LINKER_FLAGS="$($env:SHARED_LIB_SHARPYUV -replace '\\', '/')" `
    -DZLIB_LIBRARY="$($env:SHARED_LIB_ZLIB -replace '\\', '/')" `
    -DDeflate_LIBRARY="$($env:SHARED_LIB_DEFLATE -replace '\\', '/')" `
    -DJPEG_LIBRARY="$($env:SHARED_LIB_JPEG -replace '\\', '/')" `
    -DLIBLZMA_LIBRARY="$($env:SHARED_LIB_LZMA -replace '\\', '/')" `
    -DLERC_LIBRARY="$($env:SHARED_LIB_LERC -replace '\\', '/')" `
    -DWebP_LIBRARY="$($env:SHARED_LIB_WEBP -replace '\\', '/')" `
    -DZSTD_LIBRARY="$($env:SHARED_LIB_ZSTD -replace '\\', '/')" `
    --no-warn-unused-cli
    
if ($LASTEXITCODE -ne 0) { Write-Error "libtiff CMake Shared (DLL) configuration failed."; Pop-Location; return }

Write-Host "Building and Installing dynamic lib to $libtiffInstallDir..." -ForegroundColor Green
cmake --build "$BuildDirShared" --target install --config Release --parallel

if ($LASTEXITCODE -ne 0) { Write-Error "libtiff Shared Build failed with exit code $LASTEXITCODE"; Pop-Location; return }

Write-Host "Successfully built and installed libtiff to $libtiffInstallDir!" -ForegroundColor Green

# Cleanup temporary build debris
Remove-Item $BuildDirShared -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item $BuildDirStatic -Recurse -Force -ErrorAction SilentlyContinue

# Generate Environment Helper with Clean Paths
$libtiffInstallDir = $libtiffInstallDir.TrimEnd('\')
$libtiffIncludeDir = Join-Path $libtiffInstallDir "include"
$libtiffLibDir = Join-Path $libtiffInstallDir "lib"
$libtiffBinPath = Join-Path $libtiffInstallDir "bin"
$libtiffCMakePath = $libtiffInstallDir.Replace('\', '/')

$StaticLib = Join-Path $libtiffLibDir ("$libtiffLibName" + "_static.lib")
$SharedLib = Join-Path $libtiffLibDir "$libtiffLibName.lib"
$BinaryLib = Join-Path $libtiffBinPath "$libtiffLibName.dll"
$versionFile = Join-Path $libtiffInstallDir "version.json"

if ((Test-Path $StaticLib) -or (Test-Path $SharedLib) -or (Test-Path $BinaryLib)) {
    $localVersion = "0.0.0"
    $rawVersion = $Branch
    $binaryversion = "0"

    $srcVersionFile = Join-Path $Source "VERSION"
    if (Test-Path $srcVersionFile) {
        $fileContent = (Get-Content $srcVersionFile -Raw).Trim()
        if ($fileContent -match '^(\d+\.\d+\.\d+)') {
            $localVersion = $Matches[1]
            $rawVersion = $localVersion
            $binaryversion = ([version]$localVersion).Major
            Write-Host "[VERSION] Detected libtiff: $localVersion" -ForegroundColor Cyan
        }
    }

    # Save new version state
    $libtiffVersion = $localVersion
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
# LIBTIFF Environment Setup
$libtiffroot = "VALUE_ROOT_PATH"
$libtiffinclude = "VALUE_INCLUDE_PATH"
$libtifflibrary = "VALUE_LIB_PATH"
$libtiffbin = "VALUE_BIN_PATH"
$libtiffversion = "VALUE_VERSION"
$libtiffabiversion = "VALUE_ABI_VERSION"
$libtiffsoversion = "VALUE_SO_VERSION"
$libtiffbinary = "VALUE_BINARY"
$libtiffshared = "VALUE_SHARED"
$libtiffstatic = "VALUE_STATIC"
$libtifflibname = "VALUE_LIB_NAME"
$libtiffcmakepath = "VALUE_CMAKE_PATH"
$env:LIBTIFF_PATH = $libtiffroot
$env:LIBTIFF_ROOT = $libtiffroot
$env:LIBTIFF_BIN = $libtiffbin
$env:LIBTIFF_INCLUDE_DIR = $libtiffinclude
$env:LIBTIFF_LIBRARY_DIR = $libtifflibrary
$env:BINARY_LIB_TIFF = $libtiffbinary
$env:SHARED_LIB_TIFF = $libtiffshared
$env:STATIC_LIB_TIFF = $libtiffstatic
$env:LIBTIFF_LIB_NAME = $libtifflibname
$env:LIBTIFF_VERSION = $libtiffversion
$env:LIBTIFF_MAJOR = ([version]$libtiffversion).Major
$env:LIBTIFF_MINOR = ([version]$libtiffversion).Minor
$env:LIBTIFF_PATCH = ([version]$libtiffversion).Patch
$env:LIBTIFF_ABI_VERSION = $libtiffabiversion
$env:LIBTIFF_SO_VERSION = $libtiffsoversion
if ($env:CMAKE_PREFIX_PATH -notlike "*$libtiffcmakepath*") { $env:CMAKE_PREFIX_PATH = $libtiffcmakepath + ";" + $env:CMAKE_PREFIX_PATH; $env:CMAKE_PREFIX_PATH = ($env:CMAKE_PREFIX_PATH).Replace(";;", ";") }
if ($env:INCLUDE -notlike "*$libtiffinclude*") { $env:INCLUDE = $libtiffinclude + ";" + $env:INCLUDE; $env:INCLUDE = ($env:INCLUDE).Replace(";;", ";") }
if ($env:LIB -notlike "*$libtifflibrary*") { $env:LIB = $libtifflibrary + ";" + $env:LIB; $env:LIB = ($env:LIB).Replace(";;", ";") }
if ($env:PATH -notlike "*$libtiffbin*") { $env:PATH = $libtiffbin + ";" + $env:PATH; $env:PATH = ($env:PATH).Replace(";;", ";") }
Write-Host "libtiff Environment Loaded (Version: $libtiffversion) (Bin: $libtiffbin)" -ForegroundColor Green
Write-Host "LIBTIFF_ROOT: $env:LIBTIFF_ROOT" -ForegroundColor Gray
'@  -replace "VALUE_ROOT_PATH", $libtiffInstallDir `
    -replace "VALUE_INCLUDE_PATH", $libtiffIncludeDir `
    -replace "VALUE_LIB_PATH", $libtiffLibDir `
    -replace "VALUE_BIN_PATH", $libtiffBinPath `
    -replace "VALUE_VERSION", $libtiffVersion `
    -replace "VALUE_ABI_VERSION", $binaryversion `
    -replace "VALUE_SO_VERSION", $binaryversion `
    -replace "VALUE_SHARED", $SharedLib `
    -replace "VALUE_BINARY", $BinaryLib `
    -replace "VALUE_STATIC", $StaticLib `
    -replace "VALUE_LIB_NAME", $libtiffLibName `
    -replace "VALUE_CMAKE_PATH", $libtiffCMakePath

    $EnvContent | Out-File -FilePath $libtiffEnvScript -Encoding utf8
    Write-Host "Created: $libtiffEnvScript" -ForegroundColor Gray
    
    if (Test-Path $libtiffEnvScript) { . $libtiffEnvScript } else {
        Write-Error "libtiff build install finished but $libtiffEnvScript was not created."
        Pop-Location; return
    }
    
    if ($libtiffWithMachineEnvironment)
    {
        $MachineEnvContent = @'
# libtiff Machine Environment Setup
$IsAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$ScopeColor = "Cyan"

if (-not $IsAdmin) {
    Write-Host "Elevation required to set libtiff system variables. Relaunching as Administrator..." -ForegroundColor Yellow
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

$libtiffroot = "VALUE_ROOT_PATH"
$libtiffbin = "VALUE_BIN_PATH"
$libtiffversion = "VALUE_VERSION"

$TargetScope = if ($IsAdmin) { "Machine" } else { "User" }
$RegPath = if ($IsAdmin) { "System\CurrentControlSet\Control\Session Manager\Environment" } else { "Environment" }
$RegRoot = if ($IsAdmin) { "LocalMachine" } else { "CurrentUser" }

# Open the registry key once
$RegKey = [Microsoft.Win32.Registry]::$RegRoot.OpenSubKey($RegPath, $true)

# Open the registry key directly to read the RAW (unexpanded) string
$CurrentRawPath = $RegKey.GetValue("EXTCOMPLIBS_PATH", "", [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)

$CleanedPathList = $CurrentRawPath -split ';' | Where-Object { 
    -not [string]::IsNullOrWhitespace($_) -and 
    $_ -notlike "*$libtiffroot*"
}

$NewRawPath = ($CleanedPathList -join ";").Replace(";;", ";")

$TargetPath = $libtiffbin

# Rebuild
$NewRawPath = ($NewRawPath + ";" + $TargetPath + ";").Replace(";;", ";")
Write-Host "[UPDATED] ($TargetScope) '$libtiffbin' synced in EXTCOMPLIBS_PATH" -ForegroundColor $ScopeColor

# Save as ExpandString
$RegKey.SetValue("EXTCOMPLIBS_PATH", $NewRawPath, [Microsoft.Win32.RegistryValueKind]::ExpandString)
$env:EXTCOMPLIBS_PATH = $NewRawPath

$RegKey.Close()

$env:LIBTIFF_ROOT = $libtiffroot
Write-Host "libtiff Environment Loaded (Version: $libtiffversion) (Bin: $libtiffbin)" -ForegroundColor Green
Write-Host "LIBTIFF_ROOT: $env:LIBTIFF_ROOT" -ForegroundColor Gray
'@  -replace "VALUE_ROOT_PATH", $libtiffInstallDir `
    -replace "VALUE_BIN_PATH", $libtiffBinPath `
    -replace "VALUE_VERSION", $libtiffVersion

        $MachineEnvContent | Out-File -FilePath $libtiffMachineEnvScript -Encoding utf8
        Write-Host "Created: $libexpatMachineEnvScript" -ForegroundColor Gray
        
        # --- Interaction: Prompt to apply persistent changes ---
        Write-Host ""
        $choice = Read-Host "Do you want to run the Machine Environment script now to persist libtiff changes to the Registry? (y/n)"
        if ($choice -eq 'y' -or $choice -eq 'Y') {
            Write-Host "Executing $libtiffMachineEnvScript..." -ForegroundColor Yellow
            try {
                # Start the generated script. It handles its own elevation logic.
                & $libtiffMachineEnvScript
            }
            catch {
                Write-Error "Failed to execute the Machine Environment script: $($_.Exception.Message)"
            }
        }
        else {
            Write-Host "Skipped persistent registry update. You can run it later at: $libtiffMachineEnvScript" -ForegroundColor Gray
        }
    }
    
    # --- Return to Start ---
    Pop-Location
    Write-Host "Successfully Done! and returned to: $(Get-Location)" -ForegroundColor DarkGreen
} else {
    Write-Error "libtiff library was not found in the $libtiffLibDir folder."
    Pop-Location; return
}
