# SPDX-FileCopyrightText: Copyright (c) 2026 Navegos. @DevelVitorF. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
# project: buildtools
# file: x64-windows/build-hwloc.ps1
# created: 2026-03-14
# lastModified: 2026-04-26

param (
    [Parameter(HelpMessage = "Base workspace path", Mandatory = $false)]
    [string]$workspacePath = $null,

    [Parameter(HelpMessage = "hwloc git repo url", Mandatory = $false)]
    [string]$gitUrl = "https://github.com/open-mpi/hwloc.git",
    
    [Parameter(HelpMessage = "hwloc git branch to sync from", Mandatory = $false)]
    [string]$gitBranch = "master",

    [Parameter(HelpMessage = "Path for hwloc library storage", Mandatory = $false)]
    [string]$hwlocInstallDir = "$env:LIBRARIES_PATH\hwloc",
    
    [Parameter(HelpMessage = "Lib name, if it's building with a different name (fixit by changing it's default name beforehand)", Mandatory = $false)]
    [string]$hwlocLibName = "hwloc",
    
    [Parameter(HelpMessage = "Force a full purge of the local hwloc version before continuing", Mandatory = $false)]
    [switch]$forceCleanup,
    
    [Parameter(HelpMessage = "Add's hwloc Machine Environment Variables. Requires Machine Administrator Rights.", Mandatory = $false)]
    [switch]$withMachineEnvironment
)

# Capture parameters
$hwlocWorkspacePath = $workspacePath
$hwlocGitUrl = $gitUrl
$hwlocGitBranch = $gitBranch
$hwlocForceCleanup = $forceCleanup
$hwlocWithMachineEnvironment = $withMachineEnvironment

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
$RoothwlocInstallDir = Split-Path -Path $hwlocInstallDir -Parent
$RoothwlocWorkspacePath = if ([string]::IsNullOrWhitespace($hwlocWorkspacePath)) { Get-Location } else { $hwlocWorkspacePath }

# Load libxml2 requirement
if ([string]::IsNullOrWhiteSpace($env:SHARED_LIB_XML2) -or -not (Test-Path $env:SHARED_LIB_XML2)) {
    $libxml2EnvScript = Join-Path $EnvironmentDir "env-libxml2.ps1"
    if (Test-Path $libxml2EnvScript) { . $libxml2EnvScript }
    if ([string]::IsNullOrWhiteSpace($env:SHARED_LIB_XML2) -or -not (Test-Path $env:SHARED_LIB_XML2)) {
        $libxml2BuildScript = Join-Path $PSScriptRoot "build-libxml2.ps1"
        if (Test-Path $libxml2BuildScript) {
            $libxml2InstallDir = Join-Path $RoothwlocInstallDir "libxml2"
            & $libxml2BuildScript -workspacePath $RoothwlocWorkspacePath -libxml2InstallDir $libxml2InstallDir
        } else {
            Write-Error "CRITICAL: Cannot build libxml2. libxml2 is missing and $libxml2BuildScript was not found."
            return
        }
    }
}

# Load cuda requirement
if ([string]::IsNullOrWhitespace($env:BINARY_NVCC) -or -not (Test-Path $env:BINARY_NVCC)) {
    $cudaEnvScript = Join-Path $EnvironmentDir "env-cuda.ps1"
    if (Test-Path $cudaEnvScript) { . $cudaEnvScript }
    if ([string]::IsNullOrWhitespace($env:BINARY_NVCC) -or -not (Test-Path $env:BINARY_NVCC)) {
        $depcudaEnvScript = Join-Path $PSScriptRoot "dep-cuda.ps1"
        if (Test-Path $depcudaEnvScript) { . $depcudaEnvScript }
        else {
            Write-Error "CRITICAL: Cannot load cuda environment. cuda is missing and $cudaEnvScript was not found."
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

$RootPath = $RoothwlocWorkspacePath

# --- 6. Path Resolution ---
Push-Location $RootPath

$Source         = Join-Path $RootPath "hwloc"
$BuildDirShared = Join-Path $Source "build_shared"
$BuildDirStatic = Join-Path $Source "build_static"
$RepoUrl        = $hwlocGitUrl
$Branch         = $hwlocGitBranch
$CMakeSource    = Join-Path $Source "contrib/windows-cmake"
$tag_name       = $Branch
$url            = $RepoUrl

$hwlocEnvScript = Join-Path $EnvironmentDir "env-hwloc.ps1"
$hwlocMachineEnvScript = Join-Path $EnvironmentDir "machine-env-hwloc.ps1"

# --- 1. Cleanup Mechanism ---
function Invoke-hwlocVersionPurge {
    param ([string]$InstallPath)
    Write-Host "--- Initiating hwloc Purge ---" -ForegroundColor Cyan

    if ($hwlocWithMachineEnvironment)
    {
        $hwlocCleanMachineEnvScript = Join-Path $env:TEMP "clean-machine-env-hwloc.ps1"

        # Generating Clean Machine Environment wich removes the persist registry machine Environment
        $CleanMachineEnvContent = @'
# hwloc Clean Machine Environment Setup

# --- 0. Self-Elevation Logic ---
$IsAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$ScopeColor = "Cyan"

if (-not $IsAdmin) {
    Write-Host "Elevation required to clean hwloc system variables. Relaunching as Administrator..." -ForegroundColor Yellow
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

$hwlocroot = "VALUE_ROOT_PATH"

$TargetScope = if ($IsAdmin) { "Machine" } else { "User" }
$RegPath = if ($IsAdmin) { "System\CurrentControlSet\Control\Session Manager\Environment" } else { "Environment" }
$RegRoot = if ($IsAdmin) { "LocalMachine" } else { "CurrentUser" }

# 1. Registry Cleanup (EXTCOMPLIBS_PATH)
$RegKey = [Microsoft.Win32.Registry]::$RegRoot.OpenSubKey($RegPath, $true)

# Open the registry key directly to read the RAW (unexpanded) string
$RawPath = $RegKey.GetValue("EXTCOMPLIBS_PATH", "", [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)

# Cleanup: Remove empty strings, any path containing $hwlocroot,
$CleanPath = ($RawPath -split ';' | Where-Object { $_ -notlike "*$hwlocroot*" }) -join ";"

# Save as ExpandString
$RegKey.SetValue("EXTCOMPLIBS_PATH", $CleanPath, [Microsoft.Win32.RegistryValueKind]::ExpandString)
$env:EXTCOMPLIBS_PATH = $CleanPath

$RegKey.Close()

Write-Host "[REMOVED] ($TargetScope) all '*$hwlocroot*' removed from EXTCOMPLIBS_PATH" -ForegroundColor $ScopeColor
'@  -replace "VALUE_ROOT_PATH", $InstallPath

        $CleanMachineEnvContent | Out-File -FilePath $hwlocCleanMachineEnvScript -Encoding utf8
        Write-Host "Created: $hwlocCleanMachineEnvScript" -ForegroundColor Gray
        
        # --- Interaction: Prompt to remove persistent changes ---
        Write-Host ""
        $choice = Read-Host "Administrator rights required to Clean Machine Environment hwloc changes? (y/n)"
        if ($choice -eq 'y' -or $choice -eq 'Y') {
            Write-Host "Executing $hwlocCleanMachineEnvScript..." -ForegroundColor Yellow
            try {
                # Start the generated script. It handles its own elevation logic.
                & $hwlocCleanMachineEnvScript
            }
            catch {
                Write-Error "Failed to execute the Clean Machine Environment script: $($_.Exception.Message)"
                Pop-Location; return
            }
        }
        else {
            Write-Error "Skipped Clean Machine Environment hwloc changes."
            Pop-Location; return
        }
        
        # Cleanup
        Remove-Item $hwlocCleanMachineEnvScript -Recurse -Force -ErrorAction SilentlyContinue
    }

    # 2. Filesystem Clean (Requires checking for locked files)
    # delete everithing we create don't fail later
    if (Test-Path $hwlocEnvScript) {
        Write-Host "  [DELETING] $hwlocEnvScript" -ForegroundColor Yellow
        Remove-Item $hwlocEnvScript -Recurse -Force -ErrorAction SilentlyContinue
    }
    if (Test-Path $hwlocMachineEnvScript) {
        Write-Host "  [DELETING] $hwlocMachineEnvScript" -ForegroundColor Yellow
        Remove-Item $hwlocMachineEnvScript -Recurse -Force -ErrorAction SilentlyContinue
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
    Get-ChildItem Env:\HWLOC_PATH* | Remove-Item -ErrorAction SilentlyContinue
    Get-ChildItem Env:\HWLOC_ROOT* | Remove-Item -ErrorAction SilentlyContinue
    Get-ChildItem Env:\HWLOC_BIN* | Remove-Item -ErrorAction SilentlyContinue
    Get-ChildItem Env:\HWLOC_INCLUDE_DIR* | Remove-Item -ErrorAction SilentlyContinue
    Get-ChildItem Env:\HWLOC_LIBRARY_DIR* | Remove-Item -ErrorAction SilentlyContinue
    Get-ChildItem Env:\BINARY_LIB_HWLOC* | Remove-Item -ErrorAction SilentlyContinue
    Get-ChildItem Env:\SHARED_LIB_HWLOC* | Remove-Item -ErrorAction SilentlyContinue
    Get-ChildItem Env:\STATIC_LIB_HWLOC* | Remove-Item -ErrorAction SilentlyContinue
    Get-ChildItem Env:\HWLOC_LIB_NAME* | Remove-Item -ErrorAction SilentlyContinue
    Get-ChildItem Env:\HWLOC_VERSION* | Remove-Item -ErrorAction SilentlyContinue
    Get-ChildItem Env:\HWLOC_MAJOR* | Remove-Item -ErrorAction SilentlyContinue
    Get-ChildItem Env:\HWLOC_MINOR* | Remove-Item -ErrorAction SilentlyContinue
    Get-ChildItem Env:\HWLOC_PATCH* | Remove-Item -ErrorAction SilentlyContinue
    Get-ChildItem Env:\HWLOC_ABI_VERSION* | Remove-Item -ErrorAction SilentlyContinue
    Get-ChildItem Env:\HWLOC_SO_VERSION* | Remove-Item -ErrorAction SilentlyContinue
    
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
    
    Write-Host "--- HWLOC Purge Complete ---" -ForegroundColor Green
}

if ($hwlocForceCleanup) {
    Invoke-hwlocVersionPurge -InstallPath $hwlocInstallDir
}

# --- 7. Source Management ---
if (Test-Path $Source) {
    Write-Host "Syncing hwloc ($Branch) at $Source..." -ForegroundColor Cyan
    Set-Location $Source
    git fetch --all
    git reset --hard "origin/$Branch"
    git pull --recurse-submodules --force
    $tagCommit = (& git rev-parse --verify HEAD).Trim()
} else {
    Write-Host "Cloning hwloc ($Branch) into $Source..." -ForegroundColor Cyan
    git clone --recurse-submodules $RepoUrl $Source -b $Branch
    Set-Location $Source
    $tagCommit = (& git rev-parse --verify HEAD).Trim()
}

# --- Apply Patch some symbols are not exported and build fails linking shared lib ---
$PatchFile = Join-Path $PSScriptRoot "patch\hwloc-clang-windows.patch"
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
if (Test-Path $hwlocInstallDir) {
    Write-Host "Wiping existing installation at $hwlocInstallDir..." -ForegroundColor Yellow
    Remove-Item $hwlocInstallDir -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "[INSTALL] Creating fresh directory: $hwlocInstallDir" -ForegroundColor Cyan
New-Item -Path $hwlocInstallDir -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null

# Ensure fresh build directory
if (Test-Path $BuildDirShared) { Remove-Item $BuildDirShared -Recurse -Force -ErrorAction SilentlyContinue }
if (Test-Path $BuildDirStatic) { Remove-Item $BuildDirStatic -Recurse -Force -ErrorAction SilentlyContinue }
New-Item -Path $BuildDirShared -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null
New-Item -Path $BuildDirStatic -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null

<# # --- Patch CMakeLists.txt for Clang/Windows Compatibility ---
$cmakeFile = Join-Path $Source "contrib/windows-cmake/CMakeLists.txt"

if (Test-Path $cmakeFile) {
    Write-Host "Patching CMakeLists.txt for Clang/LLD compatibility..." -ForegroundColor Cyan
    $content = Get-Content $cmakeFile -Raw
    
    # 1. First, fix the MSVC/WIN32 and Linker flags (Global fixes)
    $content = $content.Replace('$<$<BOOL:${MSVC}>', '$<$<BOOL:${WIN32}>')
    $content = $content.Replace('/subsystem:windows;/entry:mainCRTStartup', '-Wl,/subsystem:windows,/entry:mainCRTStartup')

    # 2. Fix the Search Path
    $oldSearch = 'set(HWLOC_PLUGINS_PATH ${CMAKE_INSTALL_PREFIX}/lib/hwloc)'
    $newSearch = 'set(HWLOC_PLUGINS_PATH ${CMAKE_INSTALL_PREFIX}/bin/hwloc)'
    $content = $content.Replace($oldSearch, $newSearch)

    # 3. Clean the Plugin Install Block
    # This logic finds the "# install plugins" comment and everything that follows 
    # until the end of that specific foreach block, then replaces it.
    $targetHeader = "# install plugins"
    $splitContent = $content -split [Regex]::Escape($targetHeader)

    # Rebuild the file: Keep the top part, add our clean header, then our clean code
    $cleanInstallBlock = @'

foreach(plugin IN LISTS HWLOC_ENABLED_PLUGINS_LIST)
    install(TARGETS hwloc_${plugin}
        LIBRARY DESTINATION bin/hwloc
        ARCHIVE DESTINATION lib/hwloc
        RUNTIME DESTINATION bin/hwloc
    )
endforeach()

'@

    # This regex identifies the old broken loop until the "if(NOT HWLOC_SKIP_TOOLS)" section 
    # to ensure we don't delete the rest of the file.
    $remainingContent = $splitContent[1] -replace '(?s)^.*?if\(NOT HWLOC_SKIP_TOOLS\)', 'if(NOT HWLOC_SKIP_TOOLS)'

    $content = $splitContent[0] + $targetHeader + $cleanInstallBlock + $remainingContent

    # Save it
    $content | Out-File $cmakeFile -Encoding utf8 -Force
    Write-Host "Successfully reconstructed CMakeLists.txt with a clean install block." -ForegroundColor Green
} else {
    Write-Warning "Could not find CMakeLists.txt to check patch at $cmakeFile"
} #>

# Common CMake Flags 
$CommonCmakeArgs = @(
    "-G", "Ninja",
    "-DCMAKE_POLICY_DEFAULT_CMP0091=NEW",
    "-DCMAKE_POLICY_DEFAULT_CMP0109=NEW",
    "-DCMAKE_C_COMPILER=clang",
    "-DCMAKE_CXX_COMPILER=clang++",
    "-DCMAKE_BUILD_TYPE=Release"
)

# --- 9. STAGE 1: Build Static Libraries ---
Write-Host "Building Static (hwlocs.lib)..." -ForegroundColor Cyan
cmake $CommonCmakeArgs `
    -S "$CMakeSource" `
    -B "$BuildDirStatic" `
    -DCMAKE_INSTALL_PREFIX="$hwlocInstallDir" `
    -DBUILD_SHARED_LIBS=OFF `
    -DHWLOC_ENABLE_TESTING=OFF `
    -DHWLOC_ENABLE_PLUGINS=OFF `
    -DHWLOC_SKIP_LSTOPO=ON `
    -DHWLOC_SKIP_TOOLS=ON `
    -DHWLOC_SKIP_INCLUDES=OFF `
    -DHWLOC_WITH_LIBXML2=ON `
    -DHWLOC_WITH_OPENCL=ON `
    -DHWLOC_WITH_CUDA=ON `
    -DCMAKE_C_FLAGS="-Wno-deprecated-declarations -Wno-incompatible-pointer-types -D_CRT_SECURE_NO_WARNINGS=1" `
    -DCMAKE_CXX_FLAGS="-Wno-deprecated-declarations -Wno-incompatible-pointer-types -D_CRT_SECURE_NO_WARNINGS=1" `
    --no-warn-unused-cli

if ($LASTEXITCODE -ne 0) { Write-Error "hwloc CMake configuration failed."; Pop-Location; return }

Write-Host "Building and Installing static lib to $hwlocInstallDir..." -ForegroundColor Green
cmake --build "$BuildDirStatic" --target install --config Release --parallel

if ($LASTEXITCODE -ne 0) { Write-Error "hwloc Build failed with exit code $LASTEXITCODE"; Pop-Location; return }

# Rename static lib to hwlocs.lib to avoid collision
$StaticLibPath = Join-Path $hwlocInstallDir "lib/hwloc.lib"
$NewStaticName = Join-Path $hwlocInstallDir "lib/hwlocs.lib"
if (Test-Path $StaticLibPath) {
    Move-Item -Path $StaticLibPath -Destination $NewStaticName -Force -ErrorAction SilentlyContinue
    Write-Host "Static library renamed to hwlocs.lib" -ForegroundColor Gray
}

# --- 10. STAGE 2: Build Shared Libraries ---
Write-Host "Building Shared (DLL)..." -ForegroundColor Cyan
cmake $CommonCmakeArgs `
    -S "$CMakeSource" `
    -B "$BuildDirShared" `
    -DCMAKE_INSTALL_PREFIX="$hwlocInstallDir" `
    -DBUILD_SHARED_LIBS=ON `
    -DHWLOC_ENABLE_TESTING=OFF `
    -DHWLOC_ENABLE_PLUGINS=ON `
    -DHWLOC_SKIP_LSTOPO=OFF `
    -DHWLOC_SKIP_TOOLS=OFF `
    -DHWLOC_SKIP_INCLUDES=OFF `
    -DHWLOC_WITH_LIBXML2=ON `
    -DHWLOC_WITH_OPENCL=ON `
    -DHWLOC_WITH_CUDA=ON `
    -DCMAKE_C_FLAGS="-Wno-deprecated-declarations -Wno-incompatible-pointer-types -D_CRT_SECURE_NO_WARNINGS=1" `
    -DCMAKE_CXX_FLAGS="-Wno-deprecated-declarations -Wno-incompatible-pointer-types -D_CRT_SECURE_NO_WARNINGS=1" `
    --no-warn-unused-cli
    
if ($LASTEXITCODE -ne 0) { Write-Error "hwloc CMake Shared (DLL) configuration failed."; Pop-Location; return }

Write-Host "Building and Installing dynamic lib to $hwlocInstallDir..." -ForegroundColor Green
cmake --build "$BuildDirShared" --target install --config Release --parallel

if ($LASTEXITCODE -ne 0) { Write-Error "hwloc Shared Build failed with exit code $LASTEXITCODE"; Pop-Location; return }

Write-Host "Successfully built and installed hwloc to $hwlocInstallDir!" -ForegroundColor Green

# Generate Environment Helper with Clean Paths
$GlobalBinDir = "$env:BINARIES_PATH"
$hwlocInstallDir = $hwlocInstallDir.TrimEnd('\')
$hwlocIncludeDir = Join-Path $hwlocInstallDir "include"
$hwlocLibDir = Join-Path $hwlocInstallDir "lib"
$hwlocBinPath = Join-Path $hwlocInstallDir "bin"
$hwlocCMakePath = $hwlocInstallDir.Replace('\', '/')

$StaticLib = Join-Path $hwlocLibDir ("$hwlocLibName" + "static.lib")
$SharedLib = Join-Path $hwlocLibDir "$hwlocLibName.lib"
$BinaryLib = Join-Path $hwlocBinPath "$hwlocLibName.dll"
$versionFile = Join-Path $hwlocInstallDir "version.json"

# Fallback check for "hwloc.lib" / "hwlocs.lib" naming convention
if (-not (Test-Path $StaticLib)) { $StaticLib = Join-Path $hwlocLibDir ("$hwlocLibName" + "s.lib") }
#if (-not (Test-Path $SharedLib)) { $SharedLib = Join-Path $hwlocLibDir "hwloc.lib" }
#if (-not (Test-Path $BinaryLib)) { $BinaryLib = Join-Path $hwlocBinPath "hwloc.dll" }

# Save the config.h before removing build dirs
$hwlocHeader = Join-Path $hwlocIncludeDir "hwloc\autogen\config.h"
$hwlocautogenIncludeDir = Join-Path $hwlocIncludeDir "hwloc\autogen"
$hwlocbuildHeader = Join-Path $BuildDirShared "include/hwloc/autogen/config.h"
if (-not (Test-Path $hwlocHeader)) { Copy-Item -Path "$hwlocbuildHeader" -Destination $hwlocautogenIncludeDir -Recurse -Force -ErrorAction SilentlyContinue }

# Cleanup temporary build debris
Remove-Item $BuildDirShared -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item $BuildDirStatic -Recurse -Force -ErrorAction SilentlyContinue

$hwloctools = @("hwloc-bind.exe", "hwloc-calc.exe", "hwloc-diff.exe", "hwloc-distrib.exe", "hwloc-gather-cpuid.exe",
                "hwloc-info.exe", "hwloc-patch.exe", "lstopo.exe", "lstopo-no-graphics.exe", "lstopo-win.exe")
foreach ($hwloctool in $hwloctools) {
    $target = Join-Path $GlobalBinDir $hwloctool
    if (Test-Path $target) { Remove-Item $target -Force -ErrorAction SilentlyContinue }
}

if ((Test-Path $StaticLib) -or (Test-Path $SharedLib) -or (Test-Path $BinaryLib)) {
    $localVersion = "0.0.0"
    $rawVersion = $Branch
    $binaryversion = "0"
    
    if (Test-Path $hwlocHeader) {
        # Extract version from #define #define HWLOC_VERSION_MAJOR  #define HWLOC_VERSION_MINOR #define HWLOC_VERSION_RELEASE
        $headerContent = Get-Content $hwlocHeader
        
        # Extract Major, Minor, and Release versions
        $major = ($headerContent | Select-String '#define\s+HWLOC_VERSION_MAJOR\s+(\d+)').Matches.Groups[1].Value
        $minor = ($headerContent | Select-String '#define\s+HWLOC_VERSION_MINOR\s+(\d+)').Matches.Groups[1].Value
        $rel = ($headerContent | Select-String '#define\s+HWLOC_VERSION_RELEASE\s+(\d+)').Matches.Groups[1].Value

        if ($major -and $minor -and $rel) {
            $localVersion = "$major.$minor.$rel"
            $rawVersion = $localVersion
            $binaryversion = ([version]$localVersion).Major
            Write-Host "[VERSION] Detected hwloc: $localVersion" -ForegroundColor Cyan
        }
    }
    
    # Save new version state
    $hwlocVersion = $localVersion
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
    
    # Create the Symbolic Link
    foreach ($toolName in $hwloctools) {
        $newExePath = Join-Path $hwlocBinPath $toolName
        $globalLinkPath = Join-Path $GlobalBinDir $toolName
        
        Write-Host "Creating global symlink: $globalLinkPath" -ForegroundColor Cyan

        if (Test-Path $newExePath) {
            if (Test-Path $globalLinkPath) { Remove-Item $globalLinkPath -Force -ErrorAction SilentlyContinue }
            try {
                New-Item -Path $globalLinkPath -ItemType SymbolicLink -Value $newExePath -ErrorAction Stop | Out-Null
                Write-Host "[LINKED] hwloc (Global) -> $newExePath" -ForegroundColor Green
            }
            catch {
                New-Item -Path $globalLinkPath -ItemType HardLink -Value $newExePath | Out-Null
                Write-Host "[HARDLINKED] hwloc (Global) -> $newExePath" -ForegroundColor Green
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

    Write-Host "[LINKED] hwloc is now globally available via %BINARIES_PATH%" -ForegroundColor Green
    
    # --- 11. Create Environment Helper ---
    Write-Host "Generating environment helper script..." -ForegroundColor Cyan
    $EnvContent = @'
# HWLOC Environment Setup
$hwlocroot = "VALUE_ROOT_PATH"
$hwlocinclude = "VALUE_INCLUDE_PATH"
$hwloclibrary = "VALUE_LIB_PATH"
$hwlocbin = "VALUE_BIN_PATH"
$hwlocversion = "VALUE_VERSION"
$hwlocabiversion = "VALUE_ABI_VERSION"
$hwlocsoversion = "VALUE_SO_VERSION"
$hwlocbinary = "VALUE_BINARY"
$hwlocshared = "VALUE_SHARED"
$hwlocstatic = "VALUE_STATIC"
$hwloclibname = "VALUE_LIB_NAME"
$hwloccmakepath = "VALUE_CMAKE_PATH"
$env:HWLOC_PATH = $hwlocroot
$env:HWLOC_ROOT = $hwlocroot
$env:HWLOC_BIN = $hwlocbin
$env:HWLOC_INCLUDE_DIR = $hwlocinclude
$env:HWLOC_LIBRARY_DIR = $hwloclibrary
$env:BINARY_LIB_HWLOC = $hwlocbinary
$env:SHARED_LIB_HWLOC = $hwlocshared
$env:STATIC_LIB_HWLOC = $hwlocstatic
$env:HWLOC_LIB_NAME = $hwloclibname
$env:HWLOC_VERSION = $hwlocversion
$env:HWLOC_MAJOR = ([version]$hwlocversion).Major
$env:HWLOC_MINOR = ([version]$hwlocversion).Minor
$env:HWLOC_PATCH = ([version]$hwlocversion).Patch
$env:HWLOC_ABI_VERSION = $hwlocabiversion
$env:HWLOC_SO_VERSION = $hwlocsoversion
if ($env:CMAKE_PREFIX_PATH -notlike "*$hwloccmakepath*") { $env:CMAKE_PREFIX_PATH = $hwloccmakepath + ";" + $env:CMAKE_PREFIX_PATH; $env:CMAKE_PREFIX_PATH = ($env:CMAKE_PREFIX_PATH).Replace(";;", ";") }
if ($env:INCLUDE -notlike "*$hwlocinclude*") { $env:INCLUDE = $hwlocinclude + ";" + $env:INCLUDE; $env:INCLUDE = ($env:INCLUDE).Replace(";;", ";") }
if ($env:LIB -notlike "*$hwloclibrary*") { $env:LIB = $hwloclibrary + ";" + $env:LIB; $env:LIB = ($env:LIB).Replace(";;", ";") }
if ($env:PATH -notlike "*$hwlocbin*") { $env:PATH = $hwlocbin + ";" + $env:PATH; $env:PATH = ($env:PATH).Replace(";;", ";") }
Write-Host "hwloc Environment Loaded (Version: $hwlocversion) (Bin: $hwlocbin)" -ForegroundColor Green
Write-Host "HWLOC_ROOT: $env:HWLOC_ROOT" -ForegroundColor Gray
'@  -replace "VALUE_ROOT_PATH", $hwlocInstallDir `
    -replace "VALUE_INCLUDE_PATH", $hwlocIncludeDir `
    -replace "VALUE_LIB_PATH", $hwlocLibDir `
    -replace "VALUE_BIN_PATH", $hwlocBinPath `
    -replace "VALUE_VERSION", $hwlocVersion `
    -replace "VALUE_ABI_VERSION", $binaryversion `
    -replace "VALUE_SO_VERSION", $binaryversion `
    -replace "VALUE_SHARED", $SharedLib `
    -replace "VALUE_BINARY", $BinaryLib `
    -replace "VALUE_STATIC", $StaticLib `
    -replace "VALUE_LIB_NAME", $hwlocLibName `
    -replace "VALUE_CMAKE_PATH", $hwlocCMakePath

    $EnvContent | Out-File -FilePath $hwlocEnvScript -Encoding utf8
    Write-Host "Created: $hwlocEnvScript" -ForegroundColor Gray
    
    # Update Current Session
    if (Test-Path $hwlocEnvScript) { . $hwlocEnvScript } else {
        Write-Error "hwloc build install finished but $hwlocEnvScript was not created."
        Pop-Location; return
    }
    
    if ($hwlocWithMachineEnvironment)
    {
        # Generating Machine Environment wich add to the persist registry machine Environment
        $MachineEnvContent = @'
# hwloc Machine Environment Setup

# --- 0. Self-Elevation Logic ---
$IsAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$ScopeColor = "Cyan"

if (-not $IsAdmin) {
    Write-Host "Elevation required to set hwloc system variables. Relaunching as Administrator..." -ForegroundColor Yellow
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

$hwlocroot = "VALUE_ROOT_PATH"
$hwlocbin = "VALUE_BIN_PATH"
$hwlocversion = "VALUE_VERSION"

$TargetScope = if ($IsAdmin) { "Machine" } else { "User" }
$RegPath = if ($IsAdmin) { "System\CurrentControlSet\Control\Session Manager\Environment" } else { "Environment" }
$RegRoot = if ($IsAdmin) { "LocalMachine" } else { "CurrentUser" }

# Open the registry key once
$RegKey = [Microsoft.Win32.Registry]::$RegRoot.OpenSubKey($RegPath, $true)

# Open the registry key directly to read the RAW (unexpanded) string
$CurrentRawPath = $RegKey.GetValue("EXTCOMPLIBS_PATH", "", [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)

# Cleanup: Remove empty strings, any path containing $hwlocroot, and the current target (to avoid dups)
$CleanedPathList = $CurrentRawPath -split ';' | Where-Object { 
    -not [string]::IsNullOrWhitespace($_) -and 
    $_ -notlike "*$hwlocroot*"
}

$NewRawPath = ($CleanedPathList -join ";").Replace(";;", ";")

$TargetPath = $hwlocbin

# Rebuild
$NewRawPath = ($NewRawPath + ";" + $TargetPath + ";").Replace(";;", ";")
Write-Host "[UPDATED] ($TargetScope) '$hwlocbin' synced in EXTCOMPLIBS_PATH" -ForegroundColor $ScopeColor

# Save as ExpandString
$RegKey.SetValue("EXTCOMPLIBS_PATH", $NewRawPath, [Microsoft.Win32.RegistryValueKind]::ExpandString)
$env:EXTCOMPLIBS_PATH = $NewRawPath

$RegKey.Close()

$env:HWLOC_ROOT = $hwlocroot
Write-Host "hwloc Environment Loaded (Version: $hwlocversion) (Bin: $hwlocbin)" -ForegroundColor Green
Write-Host "HWLOC_ROOT: $env:HWLOC_ROOT" -ForegroundColor Gray
'@  -replace "VALUE_ROOT_PATH", $hwlocInstallDir `
    -replace "VALUE_BIN_PATH", $hwlocBinPath `
    -replace "VALUE_VERSION", $hwlocVersion

        $MachineEnvContent | Out-File -FilePath $hwlocMachineEnvScript -Encoding utf8
        Write-Host "Created: $hwlocMachineEnvScript" -ForegroundColor Gray
        
        # --- Interaction: Prompt to apply persistent changes ---
        Write-Host ""
        $choice = Read-Host "Do you want to run the Machine Environment script now to persist hwloc changes to the Registry? (y/n)"
        if ($choice -eq 'y' -or $choice -eq 'Y') {
            Write-Host "Executing $hwlocMachineEnvScript..." -ForegroundColor Yellow
            try {
                # Start the generated script. It handles its own elevation logic.
                & $hwlocMachineEnvScript
            }
            catch {
                Write-Error "Failed to execute the Machine Environment script: $($_.Exception.Message)"
            }
        }
        else {
            Write-Host "Skipped persistent registry update. You can run it later at: $hwlocMachineEnvScript" -ForegroundColor Gray
        }
    }
    
    # --- Return to Start ---
    Pop-Location
    Write-Host "Successfully Done! and returned to: $(Get-Location)" -ForegroundColor DarkGreen
} else {
    Write-Error "hwloc.lib was not found in the $hwlocLibDir folder."
    $hwloctools | ForEach-Object { 
        $globalLinkPath = Join-Path $GlobalBinDir $_
        if (Test-Path $globalLinkPath) {
            Write-Host "Cleaning up dead symlink at $globalLinkPath..." -ForegroundColor Yellow
            Remove-Item $globalLinkPath -Force -ErrorAction SilentlyContinue
        } 
    }
    Pop-Location; return
}
