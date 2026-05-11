# SPDX-FileCopyrightText: Copyright (c) 2026 Navegos. @DevelVitorF. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
# project: buildtools
# file: x64-windows/build-zstd.ps1
# created: 2026-02-28
# lastModified: 2026-05-11

param (
    [Parameter(HelpMessage = "Base workspace path", Mandatory = $false)]
    [string]$workspacePath = $null,

    [Parameter(HelpMessage = "zstd git repo url", Mandatory = $false)]
    [string]$gitUrl = "https://github.com/facebook/zstd.git",
    
    [Parameter(HelpMessage = "zstd git branch to sync from", Mandatory = $false)]
    [string]$gitBranch = "dev",

    [Parameter(HelpMessage = "Lib name, if it's building with a different name (fixit by changing it's default name beforehand)", Mandatory = $false)]
    [string]$zstdLibName = "zstd",
    
    [Parameter(HelpMessage = "Path for zstd library storage", Mandatory = $false)]
    [string]$zstdInstallDir = $null,
    
    [Parameter(HelpMessage = "Target Build Type to build for", Mandatory = $false)]
    [string]$targetBuildType = "Release",
    
    [Parameter(HelpMessage = "Force a full purge of the local zstd version before continuing", Mandatory = $false)]
    [switch]$forceCleanup,
    
    [Parameter(HelpMessage = "Add's zstd Machine Environment Variables. Requires Machine Administrator Rights.", Mandatory = $false)]
    [switch]$withMachineEnvironment
)

# Get the correct list separator for the current OS (; on Win, : on Linux)
$Sep = [IO.Path]::PathSeparator

# Get the correct folder separator (\ on Win, / on Linux)
$DirSep = [IO.Path]::DirectorySeparatorChar

# Capture parameters
$zstdWorkspacePath = $workspacePath
$zstdGitUrl = $gitUrl
$zstdGitBranch = $gitBranch
$zstdArch = $env:TARGET_ARCH
$zstdPlatform = $env:TARGET_PLATFORM
if ($targetBuildType.ToLower() -eq "release")
{
    $zstdBuildType = "Release"
    $zstdStaticRuntimeLib = "MultiThreaded"
    $zstdSharedRuntimeLib = "MultiThreadedDLL"
}
elseif ($targetBuildType.ToLower() -eq "debug")
{
    $zstdBuildType = "Debug"
    $zstdStaticRuntimeLib = "MultiThreadedDebug"
    $zstdSharedRuntimeLib = "MultiThreadedDebugDLL"
}
elseif ($targetBuildType.ToLower() -eq "relwithdebinfo")
{
    $zstdBuildType = "RelWithDebInfo"
    $zstdStaticRuntimeLib = "MultiThreaded"
    $zstdSharedRuntimeLib = "MultiThreadedDLL"
}
elseif ($targetBuildType.ToLower() -eq "minsizerel")
{
    $zstdBuildType = "MinSizeRel"
    $zstdStaticRuntimeLib = "MultiThreaded"
    $zstdSharedRuntimeLib = "MultiThreadedDLL"
}
else
{
    Write-Error "Unsupported build type: $targetBuildType. Supported: Debug, Release, RelWithDebInfo, MinSizeRel"
    return
}
$zstdTarget = $env:TARGET_TRIPLET
$zstdForceCleanup = $forceCleanup
$zstdWithMachineEnvironment = $withMachineEnvironment

# 1. Bootstrap Environment if variables are missing
if ([string]::IsNullOrWhitespace($env:ENVIRONMENT_PATH) -or -not (Test-Path $env:ENVIRONMENT_PATH) -or [string]::IsNullOrWhitespace($env:BINARIES_PATH) -or -not (Test-Path $env:BINARIES_PATH) -or [string]::IsNullOrWhitespace($env:LIBRARIES_PATH) -or -not (Test-Path $env:LIBRARIES_PATH) -or [string]::IsNullOrWhitespace($env:BUILDTOOLS_PATH) -or -not (Test-Path $env:BUILDTOOLS_PATH)) {
    Write-Error "User Environment variables missing. Please run add-user-paths.ps1 -LibrariesDir 'Path/for/Libraries' -BinariesDir 'Path/for/Binaries' -EnvironmentDir 'Path/for/Environment' -BuildToolsDir 'Path/for/BuildTools'"
    return
}

#$zstdtargetUsr = "usr$dirSep$zstdLibName"

if ($env:IS_TOOLCHAIN) {
    if ([string]::IsNullOrWhitespace($zstdInstallDir)) { $zstdInstallDir = Join-Path $env:TARGET_USR_SYSROOT $zstdLibName }
    $targetEnvironmentDir = Join-Path $env:TARGET_SYSROOT "env"
}
else {
    if ([string]::IsNullOrWhitespace($zstdInstallDir)) { $zstdInstallDir = Join-Path $env:LIBRARIES_PATH ("$zstdTarget$DirSep" + "zstd") }
    $targetEnvironmentDir = Join-Path $env:ENVIRONMENT_PATH $zstdTarget
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
$RootzstdInstallDir = Split-Path -Path $zstdInstallDir -Parent
$RootzstdWorkspacePath = if ([string]::IsNullOrWhitespace($zstdWorkspacePath)) { Get-Location } else { $zstdWorkspacePath }

# Load Lzma requirement
if ([string]::IsNullOrWhiteSpace($env:SHARED_LIB_LZMA) -or -not (Test-Path $env:SHARED_LIB_LZMA)) {
    $lzmaEnvScript = Join-Path $targetEnvironmentDir "env-lzma.ps1"
    if (Test-Path $lzmaEnvScript) { . $lzmaEnvScript }
    if ([string]::IsNullOrWhiteSpace($env:SHARED_LIB_LZMA) -or -not (Test-Path $env:SHARED_LIB_LZMA)) {
        $lzmaBuildScript = Join-Path $PSScriptRoot "build-lzma.ps1"
        if (Test-Path $lzmaBuildScript) {
            $lzmaInstallDir = Join-Path $RootzstdInstallDir "lzma"
            . $lzmaBuildScript -workspacePath $RootzstdWorkspacePath -targetArch $zstdArch -targetPlatform $zstdPlatform -targetBuildType $zstdBuildType -lzmaInstallDir $lzmaInstallDir
        } else {
            Write-Error "CRITICAL: Cannot build lzma. lzma is missing and $lzmaBuildScript was not found."
            return
        }
    }
}

# Load Lz4 requirement
if ([string]::IsNullOrWhiteSpace($env:SHARED_LIB_LZ4) -or -not (Test-Path $env:SHARED_LIB_LZ4)) {
    $lz4EnvScript = Join-Path $targetEnvironmentDir "env-lz4.ps1"
    if (Test-Path $lz4EnvScript) { . $lz4EnvScript }
    if ([string]::IsNullOrWhiteSpace($env:SHARED_LIB_LZ4) -or -not (Test-Path $env:SHARED_LIB_LZ4)) {
        $lz4BuildScript = Join-Path $PSScriptRoot "build-lz4.ps1"
        if (Test-Path $lz4BuildScript) {
            $lz4InstallDir = Join-Path $RootzstdInstallDir "lz4"
            . $lz4BuildScript -workspacePath $RootzstdWorkspacePath -targetArch $zstdArch -targetPlatform $zstdPlatform -targetBuildType $zstdBuildType -lz4InstallDir $lz4InstallDir
        } else {
            Write-Error "CRITICAL: Cannot build lz4. lz4 is missing and $lz4BuildScript was not found."
            return
        }
    }
}

# Load Zlib requirement
if ([string]::IsNullOrWhiteSpace($env:SHARED_LIB_ZLIB) -or -not (Test-Path $env:SHARED_LIB_ZLIB)) {
    $zlibEnvScript = Join-Path $targetEnvironmentDir "env-zlib.ps1"
    if (Test-Path $zlibEnvScript) { . $zlibEnvScript }
    if ([string]::IsNullOrWhiteSpace($env:SHARED_LIB_ZLIB) -or -not (Test-Path $env:SHARED_LIB_ZLIB)) {
        $zlibBuildScript = Join-Path $PSScriptRoot "build-zlib.ps1"
        if (Test-Path $zlibBuildScript) {
            $zlibInstallDir = Join-Path $RootzstdInstallDir "zlib"
            . $zlibBuildScript -workspacePath $RootzstdWorkspacePath -targetArch $zstdArch -targetPlatform $zstdPlatform -targetBuildType $zstdBuildType -zlibInstallDir $zlibInstallDir
        } else {
            Write-Error "CRITICAL: Cannot build zlib. zlib is missing and $zlibBuildScript was not found."
            return
        }
    }
}

$RootPath = $RootzstdWorkspacePath

# --- 6. Path Resolution ---
Push-Location $RootPath

$Source         = Join-Path $RootPath "zstd"
$BuildDirShared = Join-Path $Source "build_shared"
$BuildDirStatic = Join-Path $Source "build_static"
$RepoUrl        = $zstdGitUrl
$Branch         = $zstdGitBranch
$CMakeSource    = Join-Path $Source "build/cmake"
$tag_name       = $Branch
$url            = $RepoUrl

$zstdTargetEnvironmentDir = $targetEnvironmentDir

if (-not (Test-Path $zstdTargetEnvironmentDir)) {
    New-Item -Path $zstdTargetEnvironmentDir -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null
}

#$zstdEnvScript = Join-Path $zstdTargetEnvironmentDir "env-zstd.ps1"
$zstdTargetEnvScript = Join-Path $zstdTargetEnvironmentDir "env-zstd.ps1"
#$zstdMachineEnvScript = Join-Path $zstdTargetEnvironmentDir "machine-env-zstd.ps1"
$zstdTargetMachineEnvScript = Join-Path $zstdTargetEnvironmentDir "machine-env-zstd.ps1"

# --- 1. Cleanup Mechanism ---
function Invoke-zstdVersionPurge {
    param ([string]$InstallPath)
    Write-Host "--- Initiating zstd Purge ---" -ForegroundColor Cyan

    # Generate the purge script content independently of host platform, as it will be only executed in the target platform environment
    if ($zstdWithMachineEnvironment -and $env:TARGET_HOST_IS_X64_WINDOWS)
    {
        if ($env:IS_TOOLCHAIN)
        {
            $zstdTargetPurgenvDir = Join-Path $zstdTargetEnvironmentDir "purgeenv"
            if (-not (Test-Path $zstdTargetPurgenvDir)) {
                New-Item -Path $zstdTargetPurgenvDir -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null
            }
            $zstdCleanMachineEnvScript = Join-Path $zstdTargetPurgenvDir "clean-machine-env-zstd.ps1"
        }
        else
        {
            $zstdCleanMachineEnvScript = Join-Path $env:TEMP "clean-machine-env-zstd.ps1"
        }

        # Generating Clean Machine Environment wich removes the persist registry machine Environment
        if ($env:IS_TOOLCHAIN) {
            $CleanMachineEnvContent = @'
# zstd Clean Machine Environment Setup

$Sep = [IO.Path]::PathSeparator
$DirSep = [IO.Path]::DirectorySeparatorChar

$zstdtargetUsr = "usr${DirSep}VALUE_LIB_NAME"
$zstdroot = Join-Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) $zstdtargetUsr

'@ -replace "VALUE_LIB_NAME", $zstdLibName
        }
        else {
            $CleanMachineEnvContent = @'
# zstd Clean Machine Environment Setup

$Sep = [IO.Path]::PathSeparator
$DirSep = [IO.Path]::DirectorySeparatorChar

$zstdroot = "VALUE_ROOT_PATH"

'@ -replace "VALUE_ROOT_PATH", $InstallPath
        }

        $CleanMachineEnvContent += @'
if (-not $env:HOST_IS_X64_WINDOWS) {
    Write-Error "This script is intended to run on x64 Windows. Detected Arch OS does not match."
    return
}

# --- 0. Self-Elevation Logic ---
$IsAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$ScopeColor = "Cyan"

if (-not $IsAdmin) {
    Write-Host "Elevation required to clean zstd system variables. Relaunching as Administrator..." -ForegroundColor Yellow
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

$TargetScope = if ($IsAdmin) { "Machine" } else { "User" }
$RegPath = if ($IsAdmin) { "System\CurrentControlSet\Control\Session Manager\Environment" } else { "Environment" }
$RegRoot = if ($IsAdmin) { "LocalMachine" } else { "CurrentUser" }

# 1. Registry Cleanup (EXTCOMPLIBS_PATH)
$RegKey = [Microsoft.Win32.Registry]::$RegRoot.OpenSubKey($RegPath, $true)

# Open the registry key directly to read the RAW (unexpanded) string
$RawPath = $RegKey.GetValue("EXTCOMPLIBS_PATH", "", [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)

# Cleanup: Remove empty strings, any path containing $zstdroot,
$CleanPath = ($RawPath -split "$Sep" | Where-Object { $_ -notlike "*$zstdroot*" }) -join "$Sep"

# Save as ExpandString
$RegKey.SetValue("EXTCOMPLIBS_PATH", $CleanPath, [Microsoft.Win32.RegistryValueKind]::ExpandString)
$env:EXTCOMPLIBS_PATH = $CleanPath

$RegKey.Close()

Write-Host "[REMOVED] ($TargetScope) all '*$zstdroot*' removed from EXTCOMPLIBS_PATH" -ForegroundColor $ScopeColor
'@

        $CleanMachineEnvContent | Out-File -FilePath $zstdCleanMachineEnvScript -Encoding utf8
        Write-Host "Created: $zstdCleanMachineEnvScript" -ForegroundColor Gray

        # don't execute the cclean machine env script if we are in a toolchain environment, as it will be only executed in the target platform environment, and executing it here would cause issues with the current host environment
        if (-not $env:IS_TOOLCHAIN) {
            # --- Interaction: Prompt to remove persistent changes ---
            Write-Host ""
            $choice = Read-Host "Administrator rights required to Clean Machine Environment zstd changes? (y/n)"
            if ($choice -eq 'y' -or $choice -eq 'Y') {
                Write-Host "Executing $zstdCleanMachineEnvScript..." -ForegroundColor Yellow
                try {
                    # Start the generated script. It handles its own elevation logic.
                    & $zstdCleanMachineEnvScript
                }
                catch {
                    Write-Error "Failed to execute the Clean Machine Environment script: $($_.Exception.Message)"
                    Pop-Location; return
                }
            }
            else {
                Write-Error "Skipped Clean Machine Environment zstd changes."
                Pop-Location; return
            }

            # Cleanup
            Remove-Item $zstdCleanMachineEnvScript -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    # 2. Filesystem Clean (Requires checking for locked files)
    # delete everithing we create don't fail later
    if (Test-Path $zstdTargetEnvScript) {
        Write-Host "  [DELETING] $zstdTargetEnvScript" -ForegroundColor Yellow
        Remove-Item $zstdTargetEnvScript -Recurse -Force -ErrorAction SilentlyContinue
    }
    if (Test-Path $zstdTargetMachineEnvScript) {
        Write-Host "  [DELETING] $zstdTargetMachineEnvScript" -ForegroundColor Yellow
        Remove-Item $zstdTargetMachineEnvScript -Recurse -Force -ErrorAction SilentlyContinue
    }
    if (Test-Path $InstallPath) {
        Write-Host "  [DELETING] $InstallPath" -ForegroundColor Yellow
        Remove-Item $InstallPath -Recurse -Force -ErrorAction SilentlyContinue
    }
    if (Test-Path $Source) {
        Write-Host "  [DELETING] $Source" -ForegroundColor Yellow
        Remove-Item $Source -Recurse -Force -ErrorAction SilentlyContinue
    }
    
    Get-ChildItem Env:/ZSTD_* | ForEach-Object { Remove-Item Env:/$($_.Name) -ErrorAction SilentlyContinue }
    Get-ChildItem Env:/BINARY_LIB_ZSTD* | ForEach-Object { Remove-Item Env:/$($_.Name) -ErrorAction SilentlyContinue }
    Get-ChildItem Env:/SHARED_LIB_ZSTD* | ForEach-Object { Remove-Item Env:/$($_.Name) -ErrorAction SilentlyContinue }
    Get-ChildItem Env:/STATIC_LIB_ZSTD* | ForEach-Object { Remove-Item Env:/$($_.Name) -ErrorAction SilentlyContinue }

    $CurrentCMakePrefixPath = $env:CMAKE_PREFIX_PATH
    $CleanedCMakePrefixPathList = $CurrentCMakePrefixPath -split "$Sep" | Where-Object { 
        -not [string]::IsNullOrWhitespace($_) -and 
        $_ -notlike "*$InstallPath*"
    }
    $NewCMakePrefixPath = ($CleanedCMakePrefixPathList -join "$Sep").Replace("$Sep$Sep", "$Sep")
    $NewCMakePrefixPath = ($NewCMakePrefixPath + "$Sep").Replace("$Sep$Sep", "$Sep")
    $env:CMAKE_PREFIX_PATH = $NewCMakePrefixPath
    
    $CurrentIncludePath = $env:INCLUDE
    $CleanedIncludePathList = $CurrentIncludePath -split "$Sep" | Where-Object { 
        -not [string]::IsNullOrWhitespace($_) -and 
        $_ -notlike "*$InstallPath*"
    }
    $NewIncludePath = ($CleanedIncludePathList -join "$Sep").Replace("$Sep$Sep", "$Sep")
    $NewIncludePath = ($NewIncludePath + "$Sep").Replace("$Sep$Sep", "$Sep")
    $env:INCLUDE = $NewIncludePath
    
    $CurrentLibPath = $env:LIB
    $CleanedLibPathList = $CurrentLibPath -split "$Sep" | Where-Object { 
        -not [string]::IsNullOrWhitespace($_) -and 
        $_ -notlike "*$InstallPath*"
    }
    $NewLibPath = ($CleanedLibPathList -join "$Sep").Replace("$Sep$Sep", "$Sep")
    $NewLibPath = ($NewLibPath + "$Sep").Replace("$Sep$Sep", "$Sep")
    $env:LIB = $NewLibPath
    
    # cross-compiling builds should not modify the host PATH, as it can cause issues with the host environment, and the changes won't have any effect on the target environment, which is where the new PATH entries would be needed
    if (-not $env:TARGET_CROSS_COMPILING) {
        $CurrentPath = $env:PATH
        $CleanedPathList = $CurrentPath -split "$Sep" | Where-Object { 
            -not [string]::IsNullOrWhitespace($_) -and 
            $_ -notlike "*$InstallPath*"
        }
        $NewPath = ($CleanedPathList -join "$Sep").Replace("$Sep$Sep", "$Sep")
        $NewPath = ($NewPath + "$Sep").Replace("$Sep$Sep", "$Sep")
        $env:PATH = $NewPath
    }

    Write-Host "--- ZSTD Purge Complete ---" -ForegroundColor Green
}

if ($zstdForceCleanup) {
    Invoke-zstdVersionPurge -InstallPath $zstdInstallDir
}

# --- 7. Source Management ---
if (Test-Path $Source) {
    Write-Host "Syncing zstd ($Branch) at $Source..." -ForegroundColor Cyan
    Set-Location $Source
    git fetch --all
    if ($LASTEXITCODE -ne 0) { Write-Error "Git fetch failed."; Pop-Location; return }
    git reset --hard "origin/$Branch"
    git clean -xdf
    git pull --recurse-submodules --force
    if ($LASTEXITCODE -ne 0) { Write-Error "Git pull failed."; Pop-Location; return }
    $tagCommit = (& git rev-parse --verify HEAD).Trim()
} else {
    Write-Host "Cloning zstd ($Branch) into $Source..." -ForegroundColor Cyan
    git clone --recurse-submodules $RepoUrl $Source -b $Branch
    if ($LASTEXITCODE -ne 0) { Write-Error "Git clone failed."; Pop-Location; return }
    Set-Location $Source
    $tagCommit = (& git rev-parse --verify HEAD).Trim()
}

# --- Apply Patch some symbols are not exported and build fails linking shared lib ---
<# $PatchFile = Join-Path $PSScriptRoot ("patch" + "$DirSep" + "zstd_cmake.patch")
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
    } else {
        # The check failed, which usually means the repo has changed 
        # or the patch was already partially applied (unlikely after git reset --hard)
        Write-Warning "[PATCH] Patch verification failed. The source may have changed upstream."
        Write-Host "Check the patch file for conflicts or update the patch." -ForegroundColor Yellow
        
        # In a strict build-chain, you might want to stop here:
        Pop-Location; return
    }
} #>

# --- 8. Clean Final Destination ---
if (Test-Path $zstdInstallDir) {
    Write-Host "Wiping existing installation at $zstdInstallDir..." -ForegroundColor Yellow
    Remove-Item $zstdInstallDir -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "[INSTALL] Creating fresh directory: $zstdInstallDir" -ForegroundColor Cyan
New-Item -Path $zstdInstallDir -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null

# Ensure fresh build directory
if (Test-Path $BuildDirShared) { Remove-Item $BuildDirShared -Recurse -Force -ErrorAction SilentlyContinue }
if (Test-Path $BuildDirStatic) { Remove-Item $BuildDirStatic -Recurse -Force -ErrorAction SilentlyContinue }
New-Item -Path $BuildDirShared -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null
New-Item -Path $BuildDirStatic -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null

# --- Apply On-The-Fly CMake Patch ---
# Fix CMake CXX Compiler Flag Check Error in recent CMake versions
$zstdCMakeFile = Join-Path $CMakeSource "CMakeLists.txt"
if (Test-Path $zstdCMakeFile) {
    Write-Host "[PATCH] Enabling CXX language in CMakeLists.txt on the fly..." -ForegroundColor Cyan
    $cmakeContent = Get-Content $zstdCMakeFile -Raw
    if ($cmakeContent -match 'LANGUAGES C\b' -and $cmakeContent -notmatch 'LANGUAGES C CXX') {
        $cmakeContent = $cmakeContent -replace 'LANGUAGES C\b', 'LANGUAGES C CXX'
        $cmakeContent | Out-File -FilePath $zstdCMakeFile -Encoding utf8 -Force
    }
}

<# $clangTarget = if ($zstdArch -eq "arm64") { "aarch64-pc-windows-msvc" } else { "x86_64-pc-windows-msvc" }
$sysProcessor = if ($zstdArch -eq "arm64") { "ARM64" } else { "AMD64" } #>
if ($env:TARGET_CROSS_COMPILING) {

 }

# Common CMake Flags 
$CommonCmakeArgs = @(
    "-G", "Ninja",
    "-DZSTD_LEGACY_SUPPORT=ON",
    "-DZSTD_MULTITHREAD_SUPPORT=ON",
    "-DZSTD_ENABLE_CXX=ON",
    "-DZSTD_BUILD_COMPRESSION=ON",
    "-DZSTD_BUILD_DECOMPRESSION=ON",
    "-DZSTD_BUILD_DICTBUILDER=ON",
    "-DZSTD_BUILD_DEPRECATED=ON",
    "-DZSTD_BUILD_PROGRAMS=OFF",
    "-DZSTD_BUILD_TESTS=OFF",
    "-DZSTD_BUILD_TOOLS=OFF",
    "-DZSTD_BUILD_CONTRIB=OFF",
    "-DZSTD_BUILD_EXAMPLES=OFF",
    "-DZSTD_BUILD_DOCS=OFF"
)

$CommonCmakeArgs += @(
    "-DCMAKE_POLICY_DEFAULT_CMP0091=NEW",
    "-DCMAKE_POLICY_DEFAULT_CMP0109=NEW",
    "-DCMAKE_ADDR2LINE=$env:LLVM_BIN/llvm-addr2line",
    "-DCMAKE_AR=$env:LLVM_BIN/llvm-lib",
    "-DCMAKE_ASM_COMPILER=$env:LLVM_BIN/clang",
    "-DCMAKE_ASM_COMPILER_AR=$env:LLVM_BIN/llvm-lib",
    "-DCMAKE_ASM_COMPILER_CLANG_SCAN_DEPS=$env:LLVM_BIN/clang-scan-deps",
    "-DCMAKE_ASM_COMPILER_RANLIB=$env:LLVM_BIN/llvm-ranlib",
    "-DCMAKE_ASM_MASM_COMPILER=$env:LLVM_BIN/llvm-ml64",
    "-DCMAKE_ASM_MASM_COMPILER_AR=$env:LLVM_BIN/llvm-lib",
    "-DCMAKE_ASM_MASM_COMPILER_CLANG_SCAN_DEPS=$env:LLVM_BIN/clang-scan-deps",
    "-DCMAKE_ASM_MASM_COMPILER_RANLIB=$env:LLVM_BIN/llvm-ranlib",
    "-DCMAKE_BUILD_TYPE=$zstdBuildType",
    "-DCMAKE_C_COMPILER=$env:LLVM_BIN/clang-cl",
    "-DCMAKE_C_COMPILER_AR=$env:LLVM_BIN/llvm-lib",
    "-DCMAKE_C_COMPILER_CLANG_SCAN_DEPS=$env:LLVM_BIN/clang-scan-deps",
    "-DCMAKE_C_STANDARD_LIBRARIES='-lkernel32 -luser32 -lgdi32 -lwinspool -lshell32 -lole32 -loleaut32 -luuid -lcomdlg32 -ladvapi32 -loldnames'",
    "-DCMAKE_C_COMPILER_RANLIB=$env:LLVM_BIN/llvm-ranlib",
    "-DCMAKE_CXX_COMPILER=$env:LLVM_BIN/clang-cl",
    "-DCMAKE_CXX_COMPILER_AR=$env:LLVM_BIN/llvm-lib",
    "-DCMAKE_CXX_COMPILER_CLANG_SCAN_DEPS=$env:LLVM_BIN/clang-scan-deps",
    "-DCMAKE_CXX_COMPILER_RANLIB=$env:LLVM_BIN/llvm-ranlib",
    "-DCMAKE_CXX_STANDARD_LIBRARIES='-lkernel32 -luser32 -lgdi32 -lwinspool -lshell32 -lole32 -loleaut32 -luuid -lcomdlg32 -ladvapi32 -loldnames'",
    "-DCMAKE_DLLTOOL=$env:LLVM_BIN/llvm-dlltool",
    "-DCMAKE_INSTALL_PREFIX=$zstdInstallDir",
    "-DCMAKE_LINKER=$env:LLVM_BIN/lld-link",
    "-DCMAKE_NM=$env:LLVM_BIN/llvm-nm",
    "-DCMAKE_OBJCOPY=$env:LLVM_BIN/llvm-objcopy",
    "-DCMAKE_OBJDUMP=$env:LLVM_BIN/llvm-objdump",
    "-DCMAKE_RANLIB=$env:LLVM_BIN/llvm-ranlib",
    "-DCMAKE_RC_COMPILER=$env:LLVM_BIN/llvm-rc",
    "-DCMAKE_READELF=$env:LLVM_BIN/llvm-readelf",
    "-DCMAKE_STRIP=$env:LLVM_BIN/llvm-strip",
    "-DCOVERAGE_COMMAND=$env:LLVM_BIN/llvm-cov",
    "-DCOVERAGE_EXTRA_FLAGS='gcov -l'"
)

    <# "-DCMAKE_ASM_NASM_COMPILER=$env:NASM_BIN/nasm",
    "-DCMAKE_ASM_NASM_COMPILER_AR=$env:LLVM_BIN/llvm-lib",
    "-DCMAKE_ASM_NASM_COMPILER_CLANG_SCAN_DEPS=$env:LLVM_BIN/clang-scan-deps",
    "-DCMAKE_ASM_NASM_COMPILER_RANLIB=$env:LLVM_BIN/llvm-ranlib",
    "-DCMAKE_MT=$env:LLVM_BIN/llvm-mt.exe", #>

if ($env:TARGET_CROSS_COMPILING) {
    $CommonCmakeArgs += @(
        "-DCMAKE_CROSSCOMPILING=TRUE",
        "-DCMAKE_SYSTEM_NAME=$env:TARGET_SYSPROG",
        "-DCMAKE_SYSTEM_PROCESSOR=$env:TARGET_SYSARCH",
        "-DCMAKE_C_COMPILER_TARGET=$env:TARGET_TRIPLE",
        "-DCMAKE_CXX_COMPILER_TARGET=$env:TARGET_TRIPLE",
        "-DCMAKE_ASM_COMPILER_TARGET=$env:TARGET_TRIPLE",
        "-DCMAKE_ASM_MASM_COMPILER_TARGET=$env:TARGET_TRIPLE",
        "-DCMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY",
        "-DCMAKE_SYSROOT=$env:TARGET_SYSROOT",
        "-DCMAKE_FIND_ROOT_PATH=$env:TARGET_SYSROOT",
        "-DCMAKE_FIND_ROOT_PATH_MODE_PROGRAM=NEVER",
        "-DCMAKE_FIND_ROOT_PATH_MODE_LIBRARY=ONLY",
        "-DCMAKE_FIND_ROOT_PATH_MODE_INCLUDE=ONLY",
        "-DCMAKE_FIND_ROOT_PATH_MODE_PACKAGE=ONLY"
    )
}

# --- 9. STAGE 1: Build Static Libraries ---
Write-Host "Building Static $zstdStaticRuntimeLib (zstd_static.lib)..." -ForegroundColor Cyan
cmake $CommonCmakeArgs `
    -S "$CMakeSource" `
    -B "$BuildDirStatic" `
    -DBUILD_SHARED_LIBS=OFF `
    -DZSTD_BUILD_SHARED=OFF `
    -DZSTD_BUILD_STATIC=ON `^
    -DCMAKE_MSVC_RUNTIME_LIBRARY=$zstdStaticRuntimeLib `
    -DCMAKE_C_FLAGS="-DLZMA_API_STATIC -DLZ4_DLL_IMPORT=0 -DZLIB_STATIC -Wno-deprecated-declarations -D_CRT_SECURE_NO_WARNINGS=1" `
    -DCMAKE_CXX_FLAGS="-DLZMA_API_STATIC -DLZ4_DLL_IMPORT=0 -DZLIB_STATIC -Wno-deprecated-declarations -D_CRT_SECURE_NO_WARNINGS=1" `
    --no-warn-unused-cli

if ($LASTEXITCODE -ne 0) { Write-Error "zstd CMake Static (zstd_static.lib) configuration failed."; Pop-Location; return }

Write-Host "Building and Installing static lib to $zstdInstallDir..." -ForegroundColor Green
cmake --build "$BuildDirStatic" --target install --config $zstdBuildType --parallel

if ($LASTEXITCODE -ne 0) { Write-Error "zstd Static Build failed with exit code $LASTEXITCODE"; Pop-Location; return }

# Rename static lib to zstd_static.lib to avoid collision
$StaticLibPath = Join-Path $zstdInstallDir "lib/zstd.lib"
$NewStaticName = Join-Path $zstdInstallDir "lib/zstd_static.lib"
if (Test-Path $StaticLibPath) {
    Move-Item -Path $StaticLibPath -Destination $NewStaticName -Force -ErrorAction SilentlyContinue
    Write-Host "Static library renamed to zstd_static.lib" -ForegroundColor Gray
}

# --- 10. STAGE 2: Build Shared Libraries ---
Write-Host "Building Shared $zstdSharedRuntimeLib (DLL)..." -ForegroundColor Cyan
cmake $CommonCmakeArgs `
    -S "$CMakeSource" `
    -B "$BuildDirShared" `
    -DBUILD_SHARED_LIBS=ON `
    -DZSTD_BUILD_SHARED=ON `
    -DZSTD_BUILD_STATIC=OFF `
    -DCMAKE_MSVC_RUNTIME_LIBRARY=$zstdSharedRuntimeLib `
    -DCMAKE_C_FLAGS="-DZSTD_DLL_EXPORT=1 -Wno-deprecated-declarations -D_CRT_SECURE_NO_WARNINGS=1" `
    -DCMAKE_CXX_FLAGS="-DZSTD_DLL_EXPORT=1 -Wno-deprecated-declarations -D_CRT_SECURE_NO_WARNINGS=1" `
    --no-warn-unused-cli

if ($LASTEXITCODE -ne 0) { Write-Error "zstd CMake Shared (DLL) configuration failed."; Pop-Location; return }

Write-Host "Building and Installing dynamic lib to $zstdInstallDir..." -ForegroundColor Green
cmake --build "$BuildDirShared" --target install --config $zstdBuildType --parallel

if ($LASTEXITCODE -ne 0) { Write-Error "zstd Shared Build failed with exit code $LASTEXITCODE"; Pop-Location; return }

Write-Host "Successfully built and installed zstd to $zstdInstallDir!" -ForegroundColor Green

# Cleanup temporary build debris
Remove-Item $BuildDirShared -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item $BuildDirStatic -Recurse -Force -ErrorAction SilentlyContinue

# Generate Environment Helper with Clean Paths
$zstdInstallDir = $zstdInstallDir.TrimEnd("$DirSep")

$zstdIncludeDir = Join-Path $zstdInstallDir "include"
$zstdLibDir = Join-Path $zstdInstallDir "lib"
$zstdBinPath = Join-Path $zstdInstallDir "bin"
$zstdCMakePath = $zstdInstallDir.Replace('\\', '\').Replace('\', '/')

$StaticLib = Join-Path $zstdLibDir ("$zstdLibName" + "_static.lib")
$SharedLib = Join-Path $zstdLibDir "$zstdLibName.lib"
$BinaryLib = Join-Path $zstdBinPath "$zstdLibName.dll"
$versionFile = Join-Path $zstdInstallDir "version.json"

# Fallback check for "z.lib" / "z_static.lib" naming convention
#if (-not (Test-Path $StaticLib)) { $StaticLib = Join-Path $zstdLibDir ("$zstdLibName" + "_static.lib") }
#if (-not (Test-Path $SharedLib)) { $SharedLib = Join-Path $zstdLibDir "zstd.lib" }
#if (-not (Test-Path $BinaryLib)) { $BinaryLib = Join-Path $zstdBinPath "zstd.dll" }

if ((Test-Path $StaticLib) -or (Test-Path $SharedLib) -or (Test-Path $BinaryLib)) {
    $zstdHeader = Join-Path $zstdIncludeDir "zstd.h"
    $zstdSourceHeader = Join-Path $Source ("lib" + $DirSep + "zstd.h")

    if (-not (Test-Path $zstdHeader)) { $zstdHeader = Join-Path $Source $zstdSourceHeader }
    $localVersion = "0.0.0"
    $rawVersion = $Branch
    $binaryversion = "0"
    
    if (Test-Path $zstdHeader) {
        # Extract version from #define #define ZSTD_VERSION_MAJOR  #define ZSTD_VERSION_MINOR #define ZSTD_VERSION_RELEASE
        $headerContent = Get-Content $zstdHeader
        
        # Extract Major, Minor, and Release versions
        $major = ($headerContent | Select-String '#define\s+ZSTD_VERSION_MAJOR\s+(\d+)').Matches.Groups[1].Value
        $minor = ($headerContent | Select-String '#define\s+ZSTD_VERSION_MINOR\s+(\d+)').Matches.Groups[1].Value
        $rel   = ($headerContent | Select-String '#define\s+ZSTD_VERSION_RELEASE\s+(\d+)').Matches.Groups[1].Value

        if ($major -and $minor -and $rel) {
            $localVersion = "$major.$minor.$rel"
            $rawVersion = $localVersion
            $binaryversion = ([version]$localVersion).Major
            Write-Host "[VERSION] Detected zstd: $localVersion" -ForegroundColor Cyan
        }
    }

    # Save new version state
    $zstdVersion = $localVersion
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
    if ($env:IS_TOOLCHAIN) {
        $TargetEnvContent = @'
# ZSTD Environment Setup

$Sep = [IO.Path]::PathSeparator
$DirSep = [IO.Path]::DirectorySeparatorChar

$zstdtargetUsr = "usr${DirSep}VALUE_LIB_NAME"

$zstdroot = Join-Path (Split-Path -Path $PSScriptRoot -Parent) $zstdtargetUsr
$zstdinclude = Join-Path $zstdroot "include"
$zstdlibrary = Join-Path $zstdroot "lib"
$zstdbin = Join-Path $zstdroot "bin"
$zstdversion = "VALUE_VERSION"
$zstdversionfile = Join-Path $zstdroot "version.json"
$zstdabiversion = "VALUE_ABI_VERSION"
$zstdsoversion = "VALUE_SO_VERSION"
$zstdbinary = Join-Path $zstdbin "VALUE_LIB_NAME.dll"
$zstdshared = Join-Path $zstdLibDir "VALUE_LIB_NAME.lib"
$zstdstatic = Join-Path $zstdLibDir ("VALUE_LIB_NAME" + "_static.lib")
$zstdlibname = "VALUE_LIB_NAME"
$zstdcmakepath = "VALUE_LIB_NAME"

'@ -replace "VALUE_LIB_NAME", $zstdLibName `
   -replace "VALUE_VERSION", $zstdVersion `
   -replace "VALUE_ABI_VERSION", $binaryversion `
   -replace "VALUE_SO_VERSION", $binaryversion
    }
    else {
        $TargetEnvContent = @'
# ZSTD Environment Setup

$Sep = [IO.Path]::PathSeparator
$DirSep = [IO.Path]::DirectorySeparatorChar

$zstdroot = "VALUE_ROOT_PATH"
$zstdinclude = "VALUE_INCLUDE_PATH"
$zstdlibrary = "VALUE_LIB_PATH"
$zstdbin = "VALUE_BIN_PATH"
$zstdversion = "VALUE_VERSION"
$zstdversionfile = "VALUE_VERSION_FILE"
$zstdabiversion = "VALUE_ABI_VERSION"
$zstdsoversion = "VALUE_SO_VERSION"
$zstdbinary = "VALUE_BINARY"
$zstdshared = "VALUE_SHARED"
$zstdstatic = "VALUE_STATIC"
$zstdlibname = "VALUE_LIB_NAME"
$zstdcmakepath = "/VALUE_CMAKE_PATH"

'@ -replace "VALUE_ROOT_PATH", $zstdInstallDir `
   -replace "VALUE_INCLUDE_PATH", $zstdIncludeDir `
   -replace "VALUE_LIB_PATH", $zstdLibDir `
   -replace "VALUE_BIN_PATH", $zstdBinPath `
   -replace "VALUE_VERSION", $zstdVersion `
   -replace "VALUE_VERSION_FILE", $versionFile `
   -replace "VALUE_ABI_VERSION", $binaryversion `
   -replace "VALUE_SO_VERSION", $binaryversion `
   -replace "VALUE_BINARY", $BinaryLib `
   -replace "VALUE_SHARED", $SharedLib `
   -replace "VALUE_STATIC", $StaticLib `
   -replace "VALUE_LIB_NAME", $zstdLibName `
   -replace "VALUE_CMAKE_PATH", $zstdCMakePath
    }

    $TargetEnvContent += @'
$env:ZSTD_PATH = $zstdroot
$env:ZSTD_ROOT = $zstdroot
$env:ZSTD_BIN = $zstdbin
$env:ZSTD_INCLUDE_DIR = $zstdinclude
$env:ZSTD_LIBRARY_DIR = $zstdlibrary
$env:BINARY_LIB_ZSTD = $zstdbinary
$env:SHARED_LIB_ZSTD = $zstdshared
$env:STATIC_LIB_ZSTD = $zstdstatic
$env:ZSTD_LIB_NAME = $zstdlibname
$env:ZSTD_VERSION = $zstdversion
$env:ZSTD_VERSION_FILE = $zstdversionfile
$env:ZSTD_MAJOR = ([version]$zstdversion).Major
$env:ZSTD_MINOR = ([version]$zstdversion).Minor
$env:ZSTD_PATCH = ([version]$zstdversion).Patch
$env:ZSTD_ABI_VERSION = $zstdabiversion
$env:ZSTD_SO_VERSION = $zstdsoversion
$Sep = [IO.Path]::PathSeparator
if ($env:CMAKE_PREFIX_PATH -notlike "*$zstdcmakepath*") { $env:CMAKE_PREFIX_PATH = $zstdcmakepath + "$Sep" + $env:CMAKE_PREFIX_PATH; $env:CMAKE_PREFIX_PATH = ($env:CMAKE_PREFIX_PATH).Replace("$DirSep$DirSep", "$DirSep").Replace("$Sep$Sep", "$Sep") }
if ($env:INCLUDE -notlike "*$zstdinclude*") { $env:INCLUDE = $zstdinclude + "$Sep" + $env:INCLUDE$Sep $env:INCLUDE = ($env:INCLUDE).Replace("$Sep$Sep", "$Sep") }
if ($env:LIB -notlike "*$zstdlibrary*") { $env:LIB = $zstdlibrary + "$Sep" + $env:LIB$Sep $env:LIB = ($env:LIB).Replace("$Sep$Sep", "$Sep") }
f (-not $env:TARGET_CROSS_COMPILING) {
    if ($env:PATH -notlike "*$zstdbin*") { $env:PATH = $zstdbin + "$Sep" + $env:PATH$Sep $env:PATH = ($env:PATH).Replace("$Sep$Sep", "$Sep") }
}
Write-Host "zstd Environment Loaded (Version: $zstdversion) (Bin: $zstdbin)" -ForegroundColor Green
Write-Host "ZSTD_ROOT: $env:ZSTD_ROOT" -ForegroundColor Gray
'@

    $TargetEnvContent | Out-File -FilePath $zstdTargetEnvScript -Encoding utf8
    Write-Host "Created: $zstdTargetEnvScript" -ForegroundColor Gray
    
    # Update Current Session
    if (Test-Path $zstdTargetEnvScript) { . $zstdTargetEnvScript } else {
        Write-Error "zstd build install finished but $zstdTargetEnvScript was not created."
        Pop-Location; return
    }
    
    if ($zstdWithMachineEnvironment -and $env:TARGET_HOST_IS_X64_WINDOWS)
    {
        # Generating Machine Environment wich add to the persist registry machine Environment
        if ($env:IS_TOOLCHAIN) {
            $TargetMachineEnvContent = @'
# zstd Machine Environment Setup

$Sep = [IO.Path]::PathSeparator
$DirSep = [IO.Path]::DirectorySeparatorChar

$zstdtargetUsr = "usr${DirSep}VALUE_LIB_NAME"

$zstdroot = Join-Path (Split-Path -Path $PSScriptRoot -Parent) $zstdtargetUsr
$zstdbin = Join-Path $zstdroot "bin"
$zstdversion = "VALUE_VERSION"

'@ -replace "VALUE_LIB_NAME", $zstdLibName `
   -replace "VALUE_VERSION", $zstdVersion
        }
        else {
            $TargetMachineEnvContent = @'
# zstd Machine Environment Setup

$Sep = [IO.Path]::PathSeparator
$DirSep = [IO.Path]::DirectorySeparatorChar

$zstdroot = "VALUE_ROOT_PATH"
$zstdbin = "VALUE_BIN_PATH"
$zstdversion = "VALUE_VERSION"

'@ -replace "VALUE_ROOT_PATH", $zstdInstallDir `
   -replace "VALUE_BIN_PATH", $zstdBinPath `
   -replace "VALUE_VERSION", $zstdVersion
        }

        $TargetMachineEnvContent = @'
if (-not $env:HOST_IS_X64_WINDOWS) {
    Write-Error "This script is intended to run on x64 Windows. Detected Arch OS does not match."
    return
}

# --- 0. Self-Elevation Logic ---
$IsAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$ScopeColor = "Cyan"

if (-not $IsAdmin) {
    Write-Host "Elevation required to set zstd system variables. Relaunching as Administrator..." -ForegroundColor Yellow
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

$TargetScope = if ($IsAdmin) { "Machine" } else { "User" }
$RegPath = if ($IsAdmin) { "System\CurrentControlSet\Control\Session Manager\Environment" } else { "Environment" }
$RegRoot = if ($IsAdmin) { "LocalMachine" } else { "CurrentUser" }

# Open the registry key once
$RegKey = [Microsoft.Win32.Registry]::$RegRoot.OpenSubKey($RegPath, $true)

# Open the registry key directly to read the RAW (unexpanded) string
$CurrentRawPath = $RegKey.GetValue("EXTCOMPLIBS_PATH", "", [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)

# Cleanup: Remove empty strings, any path containing $zstdroot, and the current target (to avoid dups)
$CleanedPathList = $CurrentRawPath -split "$Sep" | Where-Object { 
    -not [string]::IsNullOrWhitespace($_) -and 
    $_ -notlike "*$zstdroot*"
}

$NewRawPath = ($CleanedPathList -join "$Sep").Replace("$Sep$Sep", "$Sep")

$TargetPath = $zstdbin

# Rebuild
$NewRawPath = ($NewRawPath + "$Sep" + $TargetPath + "$Sep").Replace("$Sep$Sep", "$Sep")
Write-Host "[UPDATED] ($TargetScope) '$zstdbin' synced in EXTCOMPLIBS_PATH" -ForegroundColor $ScopeColor

# Save as ExpandString
$RegKey.SetValue("EXTCOMPLIBS_PATH", $NewRawPath, [Microsoft.Win32.RegistryValueKind]::ExpandString)
$env:EXTCOMPLIBS_PATH = $NewRawPath

$RegKey.Close()

if (-not $env:ZSTD_ROOT) { $env:ZSTD_ROOT = $zstdroot }
Write-Host "zstd Environment Loaded (Version: $zstdversion) (Bin: $zstdbin)" -ForegroundColor Green
Write-Host "ZSTD_ROOT: $env:ZSTD_ROOT" -ForegroundColor Gray
'@

        $TargetMachineEnvContent | Out-File -FilePath $zstdTargetMachineEnvScript -Encoding utf8
        Write-Host "Created: $zstdTargetMachineEnvScript" -ForegroundColor Gray
    }

    if (-not $env:TARGET_CROSS_COMPILING)
    {
        # --- Interaction: Prompt to apply persistent changes ---
        Write-Host ""
        $choice = Read-Host "Do you want to run the Machine Environment script now to persist zstd changes to the Registry? (y/n)"
        if ($choice -eq 'y' -or $choice -eq 'Y') {
            Write-Host "Executing $zstdTargetMachineEnvScript..." -ForegroundColor Yellow
            try {
                # Start the generated script. It handles its own elevation logic.
                & $zstdTargetMachineEnvScript
            }
            catch {
                Write-Error "Failed to execute the Machine Environment script: $($_.Exception.Message)"
            }
        }
        else {
            Write-Host "Skipped persistent registry update. You can run it later at: $zstdTargetMachineEnvScript" -ForegroundColor Gray
        }
    }
    
    # --- Return to Start ---
    Pop-Location
    Write-Host "Successfully Done! and returned to: $(Get-Location)" -ForegroundColor DarkGreen
} else {
    Write-Error "zstd.lib was not found in the $zstdLibDir folder."
    Pop-Location; return
}
