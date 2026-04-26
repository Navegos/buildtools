# SPDX-FileCopyrightText: Copyright (c) 2026 Navegos. @DevelVitorF. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
# project: buildtools
# file: x64-windows/build-onetbb.ps1
# created: 2026-03-10
# lastModified: 2026-04-26

param (
    [Parameter(HelpMessage = "Base workspace path", Mandatory = $false)]
    [string]$workspacePath = $null,

    [Parameter(HelpMessage = "oneTBB git repo url", Mandatory = $false)]
    [string]$gitUrl = "https://github.com/uxlfoundation/oneTBB.git",
    
    [Parameter(HelpMessage = "oneTBB git branch to sync from", Mandatory = $false)]
    [string]$gitBranch = "master",

    [Parameter(HelpMessage = "Path for oneTBB library storage", Mandatory = $false)]
    [string]$oneTBBInstallDir = "$env:LIBRARIES_PATH\oneTBB",
    
    [Parameter(HelpMessage = "Force a full purge of the local oneTBB version before continuing", Mandatory = $false)]
    [switch]$forceCleanup,
    
    [Parameter(HelpMessage = "Add's oneTBB Machine Environment Variables. Requires Machine Administrator Rights.", Mandatory = $false)]
    [switch]$withMachineEnvironment
)

# Capture parameters
$oneTBBWorkspacePath = $workspacePath
$oneTBBGitUrl = $gitUrl
$oneTBBGitBranch = $gitBranch
$oneTBBForceCleanup = $forceCleanup
$oneTBBWithMachineEnvironment = $withMachineEnvironment

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

# --- Dependencies: ---
$RootoneTBBInstallDir = Split-Path -Path $oneTBBInstallDir -Parent
$RootoneTBBWorkspacePath = if ([string]::IsNullOrWhitespace($oneTBBWorkspacePath)) { Get-Location } else { $oneTBBWorkspacePath }

# Load hwloc requirement
if ([string]::IsNullOrWhiteSpace($env:SHARED_LIB_HWLOC) -or -not (Test-Path $env:SHARED_LIB_HWLOC)) {
    $hwlocEnvScript = Join-Path $EnvironmentDir "env-hwloc.ps1"
    if (Test-Path $hwlocEnvScript) { . $hwlocEnvScript }
    if ([string]::IsNullOrWhiteSpace($env:SHARED_LIB_HWLOC) -or -not (Test-Path $env:SHARED_LIB_HWLOC)) {
        $hwlocBuildScript = Join-Path $PSScriptRoot "build-hwloc.ps1"
        if (Test-Path $hwlocBuildScript) {
            $hwlocInstallDir = Join-Path $RootoneTBBInstallDir "hwloc"
            & $hwlocBuildScript -workspacePath $RootoneTBBWorkspacePath -hwlocInstallDir $hwlocInstallDir
        }
        else {
            Write-Error "CRITICAL: Cannot build hwloc. hwloc is missing and $hwlocBuildScript was not found."
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

$RootPath = $RootoneTBBWorkspacePath

# --- 6. Path Resolution ---
Push-Location $RootPath

$Source         = Join-Path $RootPath "oneTBB"
$BuildDir       = Join-Path $Source "build_dir"  # Nested inside source
$RepoUrl        = $oneTBBGitUrl
$Branch         = $oneTBBGitBranch
$CMakeSource    = $Source
$tag_name       = $Branch
$url            = $RepoUrl

$oneTBBEnvScript = Join-Path $EnvironmentDir "env-onetbb.ps1"
$oneTBBMachineEnvScript = Join-Path $EnvironmentDir "machine-env-onetbb.ps1"

# --- 1. Cleanup Mechanism ---
function Invoke-oneTBBVersionPurge {
    param ([string]$InstallPath)
    Write-Host "--- Initiating oneTBB Purge ---" -ForegroundColor Cyan

    if ($oneTBBWithMachineEnvironment) {
        $oneTBBCleanMachineEnvScript = Join-Path $env:TEMP "clean-machine-env-onetbb.ps1"

        # Generating Clean Machine Environment wich removes the persist registry machine Environment
        $CleanMachineEnvContent = @'
# oneTBB Clean Machine Environment Setup

# --- 0. Self-Elevation Logic ---
$IsAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$ScopeColor = "Cyan"

if (-not $IsAdmin) {
    Write-Host "Elevation required to clean oneTBB system variables. Relaunching as Administrator..." -ForegroundColor Yellow
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

$oneTBBroot = "VALUE_ROOT_PATH"

$TargetScope = if ($IsAdmin) { "Machine" } else { "User" }
$RegPath = if ($IsAdmin) { "System\CurrentControlSet\Control\Session Manager\Environment" } else { "Environment" }
$RegRoot = if ($IsAdmin) { "LocalMachine" } else { "CurrentUser" }

# 1. Registry Cleanup (EXTCOMPLIBS_PATH)
$RegKey = [Microsoft.Win32.Registry]::$RegRoot.OpenSubKey($RegPath, $true)

# Open the registry key directly to read the RAW (unexpanded) string
$RawPath = $RegKey.GetValue("EXTCOMPLIBS_PATH", "", [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)

# Cleanup: Remove empty strings, any path containing $oneTBBroot,
$CleanPath = ($RawPath -split ';' | Where-Object { $_ -notlike "*$oneTBBroot*" }) -join ";"

# Save as ExpandString
$RegKey.SetValue("EXTCOMPLIBS_PATH", $CleanPath, [Microsoft.Win32.RegistryValueKind]::ExpandString)
$env:EXTCOMPLIBS_PATH = $CleanPath

$RegKey.Close()

Write-Host "[REMOVED] ($TargetScope) all '*$oneTBBroot*' removed from EXTCOMPLIBS_PATH" -ForegroundColor $ScopeColor
'@  -replace "VALUE_ROOT_PATH", $InstallPath

        $CleanMachineEnvContent | Out-File -FilePath $oneTBBCleanMachineEnvScript -Encoding utf8
        Write-Host "Created: $oneTBBCleanMachineEnvScript" -ForegroundColor Gray
        
        # --- Interaction: Prompt to remove persistent changes ---
        Write-Host ""
        $choice = Read-Host "Administrator rights required to Clean Machine Environment oneTBB changes? (y/n)"
        if ($choice -eq 'y' -or $choice -eq 'Y') {
            Write-Host "Executing $oneTBBCleanMachineEnvScript..." -ForegroundColor Yellow
            try {
                # Start the generated script. It handles its own elevation logic.
                & $oneTBBCleanMachineEnvScript
            }
            catch {
                Write-Error "Failed to execute the Clean Machine Environment script: $($_.Exception.Message)"
                Pop-Location; return
            }
        }
        else {
            Write-Error "Skipped Clean Machine Environment oneTBB changes."
            Pop-Location; return
        }

        # Cleanup
        Remove-Item $oneTBBCleanMachineEnvScript -Recurse -Force -ErrorAction SilentlyContinue
    }

    # 2. Filesystem Clean (Requires checking for locked files)
    # delete everithing we create don't fail later
    if (Test-Path $oneTBBEnvScript) {
        Write-Host "  [DELETING] $oneTBBEnvScript" -ForegroundColor Yellow
        Remove-Item $oneTBBEnvScript -Recurse -Force -ErrorAction SilentlyContinue
    }
    if (Test-Path $oneTBBMachineEnvScript) {
        Write-Host "  [DELETING] $oneTBBMachineEnvScript" -ForegroundColor Yellow
        Remove-Item $oneTBBMachineEnvScript -Recurse -Force -ErrorAction SilentlyContinue
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
    Get-ChildItem Env:\TBB_PATH* | Remove-Item -ErrorAction SilentlyContinue
    Get-ChildItem Env:\TBB_ROOT* | Remove-Item -ErrorAction SilentlyContinue
    Get-ChildItem Env:\TBB_BIN* | Remove-Item -ErrorAction SilentlyContinue
    Get-ChildItem Env:\TBB_INCLUDE_DIR* | Remove-Item -ErrorAction SilentlyContinue
    Get-ChildItem Env:\TBB_LIBRARY_DIR* | Remove-Item -ErrorAction SilentlyContinue
    Get-ChildItem Env:\BINARY_LIB_TBB* | Remove-Item -ErrorAction SilentlyContinue
    Get-ChildItem Env:\SHARED_LIB_TBB* | Remove-Item -ErrorAction SilentlyContinue
    Get-ChildItem Env:\BINARY_LIB_TBB_MALLOC* | Remove-Item -ErrorAction SilentlyContinue
    Get-ChildItem Env:\SHARED_LIB_TBB_MALLOC* | Remove-Item -ErrorAction SilentlyContinue
    Get-ChildItem Env:\BINARY_LIB_TBB_MALLOC_PROXY* | Remove-Item -ErrorAction SilentlyContinue
    Get-ChildItem Env:\SHARED_LIB_TBB_MALLOC_PROXY* | Remove-Item -ErrorAction SilentlyContinue
    Get-ChildItem Env:\BINARY_LIB_TBB_BIND* | Remove-Item -ErrorAction SilentlyContinue
    Get-ChildItem Env:\SHARED_LIB_TBB_BIND* | Remove-Item -ErrorAction SilentlyContinue
    Get-ChildItem Env:\TBB_LIB_NAME* | Remove-Item -ErrorAction SilentlyContinue
    Get-ChildItem Env:\TBB_MALLOC_LIB_NAME* | Remove-Item -ErrorAction SilentlyContinue
    Get-ChildItem Env:\TBB_MALLOC_PROXY_LIB_NAME* | Remove-Item -ErrorAction SilentlyContinue
    Get-ChildItem Env:\TBB_BIND_LIB_NAME* | Remove-Item -ErrorAction SilentlyContinue
    Get-ChildItem Env:\TBB_VERSION* | Remove-Item -ErrorAction SilentlyContinue
    Get-ChildItem Env:\TBB_MAJOR* | Remove-Item -ErrorAction SilentlyContinue
    Get-ChildItem Env:\TBB_MINOR* | Remove-Item -ErrorAction SilentlyContinue
    Get-ChildItem Env:\TBB_PATCH* | Remove-Item -ErrorAction SilentlyContinue
    Get-ChildItem Env:\TBB_ABI_VERSION* | Remove-Item -ErrorAction SilentlyContinue
    Get-ChildItem Env:\TBB_SO_VERSION* | Remove-Item -ErrorAction SilentlyContinue
    Get-ChildItem Env:\TBBROOT* | Remove-Item -ErrorAction SilentlyContinue

    Write-Host "--- oneTBB Purge Complete ---" -ForegroundColor Green
}

if ($oneTBBForceCleanup) {
    Invoke-oneTBBVersionPurge -InstallPath $oneTBBInstallDir
}

# --- 7. Source Management ---
if (Test-Path $Source) {
    Write-Host "Syncing oneTBB ($Branch) at $Source..." -ForegroundColor Cyan
    Set-Location $Source
    git fetch --all
    git reset --hard "origin/$Branch"
    git pull --recurse-submodules --force
    $tagCommit = (& git rev-parse --verify HEAD).Trim()
} else {
    Write-Host "Cloning oneTBB ($Branch) into $Source..." -ForegroundColor Cyan
    git clone --recurse-submodules $RepoUrl $Source -b $Branch
    Set-Location $Source
    $tagCommit = (& git rev-parse --verify HEAD).Trim()
}

# --- Apply Patch some symbols are not exported and build fails linking shared lib ---
$PatchFile = Join-Path $PSScriptRoot "patch\oneTBB_unicode_windows.patch"
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
}

# --- 8. Clean & Build ---
if (Test-Path $oneTBBInstallDir) {
    Write-Host "Wiping existing installation at $oneTBBInstallDir..." -ForegroundColor Yellow
    Remove-Item $oneTBBInstallDir -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "[INSTALL] Creating fresh directory: $oneTBBInstallDir" -ForegroundColor Cyan
New-Item -Path $oneTBBInstallDir -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null

# Ensure fresh build directory
if (Test-Path $BuildDir) { Remove-Item $BuildDir -Recurse -Force -ErrorAction SilentlyContinue }
New-Item -Path $BuildDir -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null

$env:TBBROOT = $Source
$env:DISTUTILS_USE_SDK = "1"

Write-Host "Configuring with Clang/Ninja..." -ForegroundColor Cyan
cmake -G "Ninja" `
    -S "$CMakeSource" `
    -B "$BuildDir" `
    -DCMAKE_POLICY_DEFAULT_CMP0091=NEW `
    -DCMAKE_POLICY_DEFAULT_CMP0109=NEW `
    -DCMAKE_C_COMPILER="clang" `
    -DCMAKE_CXX_COMPILER="clang++" `
    -DCMAKE_INSTALL_PREFIX="$oneTBBInstallDir" `
    -DCMAKE_BUILD_TYPE=Release `
    -DTBB_TEST=OFF `
    -DTBB_EXAMPLES=OFF `
    -DTBB_DOC_EXAMPLES=OFF `
    -DTBB_BENCH=OFF `
    -DTBB_STRICT=OFF `
    -DTBB4PY_BUILD=ON `
    -DTBB_BUILD=ON `
    -DTBBMALLOC_BUILD=ON `
    -DTBBMALLOC_PROXY_BUILD=ON `
    -DTBB_CPF=ON `
    -DTBB_FIND_PACKAG=OFF `
    -DTBB_ENABLE_IPO=ON `
    -DTBB_CONTROL_FLOW_GUARD=OFF `
    -DTBB_FUZZ_TESTING=OFF `
    -DTBB_INSTALL=ON `
    -DTBB_FILE_TRIM=ON `
    -DTBB_VERIFY_DEPENDENCY_SIGNATURE=ON `
    -DBUILD_SHARED_LIBS=ON `
    -DTBB_INSTALL_VARS=ON `
    -DTBB_ENABLE_HWLOC_BINDING=ON `
    -DTBB_DISABLE_HWLOC_AUTOMATIC_SEARCH=ON `
    -DCMAKE_HWLOC_2_5_LIBRARY_PATH="$env:SHARED_LIB_HWLOC" `
    -DCMAKE_HWLOC_2_5_DLL_PATH="$env:BINARY_LIB_HWLOC" `
    -DCMAKE_HWLOC_2_5_INCLUDE_PATH="$env:HWLOC_INCLUDE_DIR" `
    -DCMAKE_CXX_STANDARD=20 `
    -DCMAKE_C_STANDARD=17 `
    -DCMAKE_C_FLAGS="-Wno-deprecated-declarations -D_CRT_SECURE_NO_WARNINGS=1 -D_WINDLL -D_UNICODE -DUNICODE -DWIN64 -DWIN32 -D_WINDOWS -D_WIN32_WINNT=0x0A00 -DUSE_WINTHREAD -DTBB_SUPPRESS_DEPRECATED_MESSAGES=1 -D_CRT_SECURE_NO_DEPRECATE -D__TBB_CPF_BUILD=1" `
    -DCMAKE_CXX_FLAGS="-Wno-deprecated-declarations -D_CRT_SECURE_NO_WARNINGS=1 -D_WINDLL -D_UNICODE -DUNICODE -DWIN64 -DWIN32 -D_WINDOWS -D_WIN32_WINNT=0x0A00 -DUSE_WINTHREAD -DTBB_SUPPRESS_DEPRECATED_MESSAGES=1 -D_CRT_SECURE_NO_DEPRECATE -D__TBB_CPF_BUILD=1" `
    --no-warn-unused-cli

if ($LASTEXITCODE -ne 0) { Write-Error "oneTBB CMake configuration failed."; Pop-Location; return }

Write-Host "Building and Installing to $oneTBBInstallDir..." -ForegroundColor Green
cmake --build "$BuildDir" --target install --config Release --parallel

if ($LASTEXITCODE -ne 0) { Write-Error "oneTBB Build failed with exit code $LASTEXITCODE"; Pop-Location; return }

Write-Host "Successfully built and installed oneTBB to $oneTBBInstallDir!" -ForegroundColor Green

# Cleanup temporary build debris
Remove-Item $BuildDir -Recurse -Force -ErrorAction SilentlyContinue

# Generate Environment Helper with Clean Paths
$oneTBBInstallDir = $oneTBBInstallDir.TrimEnd('\')
$oneTBBIncludeDir = Join-Path $oneTBBInstallDir "include"
$oneTBBLibDir = Join-Path $oneTBBInstallDir "lib"
$oneTBBBinPath = Join-Path $oneTBBInstallDir "bin"
$oneTBBCMakePath = $oneTBBInstallDir.Replace('\', '/')

$tbblibName = "tbb"
$tbbmalloclibName = "tbbmalloc"
$tbbmallocproxylibName = "tbbmalloc_proxy"
$tbbbindlibName = "tbbbind_2_5"

$SharedLib = Join-Path $oneTBBLibDir "$tbblibName.lib"
$BinaryLib = Join-Path $oneTBBBinPath "$tbblibName.dll"
$SharedMallocLib = Join-Path $oneTBBLibDir "$tbbmalloclibName.lib"
$BinaryMallocLib = Join-Path $oneTBBBinPath "$tbbmalloclibName.dll"
$SharedMallocProxyLib = Join-Path $oneTBBLibDir "$tbbmallocproxylibName.lib"
$BinaryMallocProxyLib = Join-Path $oneTBBBinPath "$tbbmallocproxylibName.dll"
$SharedBindLib = Join-Path $oneTBBLibDir "$tbbbindlibName.lib"
$BinaryBindLib = Join-Path $oneTBBBinPath "$tbbbindlibName.dll"
$versionFile = Join-Path $oneTBBInstallDir "version.json"

# Save the xmlversion.h before removing build dirs
$oneTBBHeader = Join-Path $oneTBBIncludeDir "oneapi\tbb\version.h"
if (-not (Test-Path $oneTBBHeader)) { $oneTBBHeader = Join-Path $Source "oneapi\tbb\version.h" }

$localVersion = "0.0.0"
$rawVersion = $Branch
$binaryversion = "0"

if (Test-Path $oneTBBHeader) {
    # Extract version from #define LIBXML_DOTTED_VERSION "2.16.0"
    $headerContent = Get-Content $oneTBBHeader
    
    # Extract Major, Minor, and Release versions
    $major = ($headerContent | Select-String '#define\s+TBB_VERSION_MAJOR\s+(\d+)').Matches.Groups[1].Value
    $minor = ($headerContent | Select-String '#define\s+TBB_VERSION_MINOR\s+(\d+)').Matches.Groups[1].Value
    $rel = ($headerContent | Select-String '#define\s+TBB_VERSION_PATCH\s+(\d+)').Matches.Groups[1].Value
    $binaryv = ($headerContent | Select-String '#define\s+__TBB_BINARY_VERSION\s+(\d+)').Matches.Groups[1].Value
    
    if ($major -and $minor -and $rel) {
        $localVersion = "$major.$minor.$rel"
        $rawVersion = $localVersion
        Write-Host "[VERSION] Detected oneTBB: $localVersion" -ForegroundColor Cyan
    }

    if ($binaryv) {
        $binaryversion = "$binaryv"
        Write-Host "[BINARY VERSION] Detected oneTBB BINARY: $binaryversion" -ForegroundColor Cyan
    }
}

# Fallback check for tbb naming convention
if ((-not (Test-Path $SharedLib)) -or (-not (Test-Path $BinaryLib))) {
    if ($binaryversion -ne "0") {
        $tbblibName = "tbb$binaryversion"
        $SharedLib = Join-Path $oneTBBLibDir "$tbblibName.lib"
        $BinaryLib = Join-Path $oneTBBBinPath "$tbblibName.dll"
    }
}

if ((Test-Path $SharedLib) -or (Test-Path $BinaryLib)) {
    
    # Save new version state
    $oneTBBVersion = $localVersion
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
    
    # --- 9. Create Environment Helper ---
    Write-Host "Generating environment helper script..." -ForegroundColor Cyan
    $EnvContent = @'
# TBB Environment Setup
$oneTBBroot = "VALUE_ROOT_PATH"
$oneTBBinclude = "VALUE_INCLUDE_PATH"
$oneTBBlibrary = "VALUE_LIB_PATH"
$oneTBBbin = "VALUE_BIN_PATH"
$oneTBBversion = "VALUE_VERSION"
$oneTBBabiversion = "VALUE_ABI_VERSION"
$oneTBBsoversion = "VALUE_SO_VERSION"
$oneTBBbinary = "VALUE_BINARY"
$oneTBBshared = "VALUE_SHARED"
$oneTBBmallocbinary = "VALUE_MALLOC_BINARY"
$oneTBBmallocshared = "VALUE_MALLOC_SHARED"
$oneTBBmallocproxybinary = "VALUE_MALLOC_PROXY_BINARY"
$oneTBBmallocproxyshared = "VALUE_MALLOC_PROXY_SHARED"
$oneTBBbindbinary = "VALUE_BIND_BINARY"
$oneTBBbindshared = "VALUE_BIND_SHARED"
$oneTBBlibname = "VALUE_LIB_NAME"
$oneTBBmalloclibname = "VALUE_MALLOC_LIB_NAME"
$oneTBBmallocproxylibname = "VALUE_MALLOC_PROXY_LIB_NAME"
$oneTBBbindlibname = "VALUE_BIND_LIB_NAME"
$oneTBBcmakepath = "VALUE_CMAKE_PATH"
$env:TBB_PATH = $oneTBBroot
$env:TBB_ROOT = $oneTBBroot
$env:TBB_BIN = $oneTBBbin
$env:TBB_INCLUDE_DIR = $oneTBBinclude
$env:TBB_LIBRARY_DIR = $oneTBBlibrary
$env:BINARY_LIB_TBB = $oneTBBbinary
$env:SHARED_LIB_TBB = $oneTBBshared
$env:BINARY_LIB_TBB_MALLOC = $oneTBBmallocbinary
$env:SHARED_LIB_TBB_MALLOC = $oneTBBmallocshared
$env:BINARY_LIB_TBB_MALLOC_PROXY = $oneTBBmallocproxybinary
$env:SHARED_LIB_TBB_MALLOC_PROXY = $oneTBBmallocproxyshared
$env:BINARY_LIB_TBB_BIND = $oneTBBbindbinary
$env:SHARED_LIB_TBB_BIND = $oneTBBbindshared
$env:TBB_LIB_NAME = $oneTBBlibname
$env:TBB_MALLOC_LIB_NAME = $oneTBBmalloclibname
$env:TBB_MALLOC_PROXY_LIB_NAME = $oneTBBmallocproxylibname
$env:TBB_BIND_LIB_NAME = $oneTBBbindlibname
$env:TBB_VERSION = $oneTBBversion
$env:TBB_MAJOR = ([version]$oneTBBversion).Major
$env:TBB_MINOR = ([version]$oneTBBversion).Minor
$env:TBB_PATCH = ([version]$oneTBBversion).Patch
$env:TBB_ABI_VERSION = $oneTBBabiversion
$env:TBB_SO_VERSION = $oneTBBsoversion
$env:TBBROOT = $oneTBBroot
if ($env:CMAKE_PREFIX_PATH -notlike "*$oneTBBcmakepath*") { $env:CMAKE_PREFIX_PATH = $oneTBBcmakepath + ";" + $env:CMAKE_PREFIX_PATH; $env:CMAKE_PREFIX_PATH = ($env:CMAKE_PREFIX_PATH).Replace(";;", ";") }
if ($env:INCLUDE -notlike "*$oneTBBinclude*") { $env:INCLUDE = $oneTBBinclude + ";" + $env:INCLUDE; $env:INCLUDE = ($env:INCLUDE).Replace(";;", ";") }
if ($env:LIB -notlike "*$oneTBBlibrary*") { $env:LIB = $oneTBBlibrary + ";" + $env:LIB; $env:LIB = ($env:LIB).Replace(";;", ";") }
if ($env:PATH -notlike "*$oneTBBbin*") { $env:PATH = $oneTBBbin + ";" + $env:PATH; $env:PATH = ($env:PATH).Replace(";;", ";") }
Write-Host "oneTBB Environment Loaded (Version: $oneTBBversion) (Bin: $oneTBBbin)" -ForegroundColor Green
Write-Host "TBB_ROOT: $env:TBB_ROOT" -ForegroundColor Gray
'@  -replace "VALUE_ROOT_PATH", $oneTBBInstallDir `
    -replace "VALUE_INCLUDE_PATH", $oneTBBIncludeDir `
    -replace "VALUE_LIB_PATH", $oneTBBLibDir `
    -replace "VALUE_BIN_PATH", $oneTBBBinPath `
    -replace "VALUE_VERSION", $oneTBBVersion `
    -replace "VALUE_ABI_VERSION", $binaryversion `
    -replace "VALUE_SO_VERSION", $binaryversion `
    -replace "VALUE_SHARED", $SharedLib `
    -replace "VALUE_BINARY", $BinaryLib `
    -replace "VALUE_MALLOC_SHARED", $SharedMallocLib `
    -replace "VALUE_MALLOC_BINARY", $BinaryMallocLib `
    -replace "VALUE_MALLOC_PROXY_SHARED", $SharedMallocProxyLib `
    -replace "VALUE_MALLOC_PROXY_BINARY", $BinaryMallocProxyLib `
    -replace "VALUE_BIND_SHARED", $SharedBindLib `
    -replace "VALUE_BIND_BINARY", $BinaryBindLib `
    -replace "VALUE_LIB_NAME", $tbblibName `
    -replace "VALUE_MALLOC_LIB_NAME", $tbbmalloclibName `
    -replace "VALUE_MALLOC_PROXY_LIB_NAME", $tbbmallocproxylibName `
    -replace "VALUE_BIND_LIB_NAME", $tbbbindlibName `
    -replace "VALUE_CMAKE_PATH", $oneTBBCMakePath

    $EnvContent | Out-File -FilePath $oneTBBEnvScript -Encoding utf8
    Write-Host "Created: $oneTBBEnvScript" -ForegroundColor Gray
    
    # Update Current Session
    if (Test-Path $oneTBBEnvScript) { . $oneTBBEnvScript } else {
        Write-Error "oneTBB build install finished but $oneTBBEnvScript was not created."
        Pop-Location; return
    }
    
    if ($oneTBBWithMachineEnvironment) {
        # Generating Machine Environment wich add to the persist registry machine Environment
        $MachineEnvContent = @'
# oneTBB Machine Environment Setup

# --- 0. Self-Elevation Logic ---
$IsAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$ScopeColor = "Cyan"

if (-not $IsAdmin) {
    Write-Host "Elevation required to set oneTBB system variables. Relaunching as Administrator..." -ForegroundColor Yellow
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

$oneTBBroot = "VALUE_ROOT_PATH"
$oneTBBbin = "VALUE_BIN_PATH"
$oneTBBversion = "VALUE_VERSION"

$TargetScope = if ($IsAdmin) { "Machine" } else { "User" }
$RegPath = if ($IsAdmin) { "System\CurrentControlSet\Control\Session Manager\Environment" } else { "Environment" }
$RegRoot = if ($IsAdmin) { "LocalMachine" } else { "CurrentUser" }

# Open the registry key once
$RegKey = [Microsoft.Win32.Registry]::$RegRoot.OpenSubKey($RegPath, $true)

# Open the registry key directly to read the RAW (unexpanded) string
$CurrentRawPath = $RegKey.GetValue("EXTCOMPLIBS_PATH", "", [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)

# Cleanup: Remove empty strings, any path containing $oneTBBroot, and the current target (to avoid dups)
$CleanedPathList = $CurrentRawPath -split ';' | Where-Object { 
    -not [string]::IsNullOrWhitespace($_) -and 
    $_ -notlike "*$oneTBBroot*"
}

$NewRawPath = ($CleanedPathList -join ";").Replace(";;", ";")

$TargetPath = $oneTBBbin

# Rebuild
$NewRawPath = ($NewRawPath + ";" + $TargetPath + ";").Replace(";;", ";")
Write-Host "[UPDATED] ($TargetScope) '$oneTBBbin' synced in EXTCOMPLIBS_PATH" -ForegroundColor $ScopeColor

# Save as ExpandString
$RegKey.SetValue("EXTCOMPLIBS_PATH", $NewRawPath, [Microsoft.Win32.RegistryValueKind]::ExpandString)
$env:EXTCOMPLIBS_PATH = $NewRawPath

$RegKey.Close()

$env:TBB_ROOT = $oneTBBroot
Write-Host "oneTBB Environment Loaded (Version: $oneTBBversion) (Bin: $oneTBBbin)" -ForegroundColor Green
Write-Host "TBB_ROOT: $env:TBB_ROOT" -ForegroundColor Gray
'@  -replace "VALUE_ROOT_PATH", $oneTBBInstallDir `
    -replace "VALUE_BIN_PATH", $oneTBBBinPath `
    -replace "VALUE_VERSION", $oneTBBVersion

        $MachineEnvContent | Out-File -FilePath $oneTBBMachineEnvScript -Encoding utf8
        Write-Host "Created: $oneTBBMachineEnvScript" -ForegroundColor Gray
        
        # --- Interaction: Prompt to apply persistent changes ---
        Write-Host ""
        $choice = Read-Host "Do you want to run the Machine Environment script now to persist oneTBB changes to the Registry? (y/n)"
        if ($choice -eq 'y' -or $choice -eq 'Y') {
            Write-Host "Executing $oneTBBMachineEnvScript..." -ForegroundColor Yellow
            try {
                # Start the generated script. It handles its own elevation logic.
                & $oneTBBMachineEnvScript
            }
            catch {
                Write-Error "Failed to execute the Machine Environment script: $($_.Exception.Message)"
            }
        }
        else {
            Write-Host "Skipped persistent registry update. You can run it later at: $oneTBBMachineEnvScript" -ForegroundColor Gray
        }
    }
    
    # --- Return to Start ---
    Pop-Location
    Write-Host "Successfully Done! and returned to: $(Get-Location)" -ForegroundColor DarkGreen

} else {
    Write-Error "tbb.lib was not found in the $oneTBBLibDir folder."
    Pop-Location; return
}
