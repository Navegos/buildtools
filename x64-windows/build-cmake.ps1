# Copyright 2026 (C) Navegos. DevelVitorF. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
# file:x64-windows/build-cmake.ps1

param (
    [Parameter(HelpMessage = "Base workspace path", Mandatory = $false)]
    [string]$workspacePath = $null,

    [Parameter(HelpMessage = "CMake git repo url", Mandatory = $false)]
    [string]$gitUrl = "https://github.com/Kitware/CMake.git",
    
    [Parameter(HelpMessage = "CMake git branch to sync from", Mandatory = $false)]
    [string]$gitBranch = "master",

    [Parameter(HelpMessage = "Path for CMake storage", Mandatory = $false)]
    [string]$cmakeInstallDir = "$env:LIBRARIES_PATH\cmake",
    
    [Parameter(HelpMessage = "Force a full purge of the local CMake version before continuing", Mandatory = $false)]
    [switch]$forceCleanup,
    
    [Parameter(HelpMessage = "Add's CMake Machine Environment Variables. Requires Machine Administrator Rights.", Mandatory = $false)]
    [switch]$withMachineEnvironment
)

# Capture parameters
$CMakeWorkspacePath = $workspacePath
$CMakeGitUrl = $gitUrl
$CMakeGitBranch = $gitBranch
$CMakeForceCleanup = $forceCleanup
$CMakeWithMachineEnvironment = $withMachineEnvironment

if ([string]::IsNullOrWhitespace($env:ENVIRONMENT_PATH) -or -not (Test-Path $env:ENVIRONMENT_PATH) -or [string]::IsNullOrWhitespace($env:BINARIES_PATH) -or -not (Test-Path $env:BINARIES_PATH) -or [string]::IsNullOrWhitespace($env:LIBRARIES_PATH) -or -not (Test-Path $env:LIBRARIES_PATH)) {
    Write-Error "User Environment variables missing. With administrator privileges run adduserpaths.ps1 -LibrariesDir 'Path\for\Libraries' -BinariesDir 'Path\for\Binaries' -EnvironmentDir 'Path\for\Environment'"
    return
}

# we need this set(UTILITIES BZIP2 CPPDAP CURL EXPAT FORM JSONCPP LIBARCHIVE LIBLZMA LIBRHASH LIBUV NGHTTP2 ZLIB ZSTD) and QT for cmake-gui -DBUILD_QtDialog=ON
Write-Error "Unfinished and working in this build-cmake.ps1 script, the required dependency's are incomplete"
return

$EnvironmentDir = "$env:ENVIRONMENT_PATH"

$cmakeEnvScript = Join-Path $EnvironmentDir "env-cmake.ps1"
$cmakeMachineEnvScript = Join-Path $EnvironmentDir "machine-env-cmake.ps1"
$RootzstdWorkspacePath = if ([string]::IsNullOrWhitespace($zstdWorkspacePath)) { Get-Location } else { $zstdWorkspacePath }

# --- 1. Cleanup Mechanism ---
function Invoke-CMakeVersionPurge {
    param ([string]$InstallPath)
    Write-Host "--- Initiating CMake Purge ---" -ForegroundColor Cyan

    if ($CMakeWithMachineEnvironment) {
        $cmakeCleanMachineEnvScript = Join-Path $env:TEMP "clean-machine-env-cmake.ps1"

        # Generating Clean Machine Environment wich removes the persist registry machine Environment
        $CleanMachineEnvContent = @'
# CMake Clean Machine Environment Setup

# --- 0. Self-Elevation Logic ---
$IsAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$ScopeColor = "Cyan"

if (-not $IsAdmin) {
    Write-Host "Elevation required to clean cmake system variables. Relaunching as Administrator..." -ForegroundColor Yellow
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

$cmakeroot = "VALUE_ROOT_PATH"

$TargetScope = if ($IsAdmin) { "Machine" } else { "User" }
$RegPath = if ($IsAdmin) { "System\CurrentControlSet\Control\Session Manager\Environment" } else { "Environment" }
$RegRoot = if ($IsAdmin) { "LocalMachine" } else { "CurrentUser" }

# 1. Registry Cleanup (TOOLS_PATH)
$RegKey = [Microsoft.Win32.Registry]::$RegRoot.OpenSubKey($RegPath, $true)

# Open the registry key directly to read the RAW (unexpanded) string
$RawPath = $RegKey.GetValue("TOOLS_PATH", "", [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)

# Cleanup: Remove empty strings, any path containing $cmakeroot,
$CleanPath = ($RawPath -split ';' | Where-Object { $_ -notlike "*$cmakeroot*" }) -join ";"

# Save as ExpandString
$RegKey.SetValue("TOOLS_PATH", $CleanPath, [Microsoft.Win32.RegistryValueKind]::ExpandString)
$env:TOOLS_PATH = $CleanPath

$RegKey.Close()

Write-Host "[REMOVED] ($TargetScope) all '*$cmakeroot*' removed from TOOLS_PATH" -ForegroundColor $ScopeColor
'@  -replace "VALUE_ROOT_PATH", $InstallPath

        $CleanMachineEnvContent | Out-File -FilePath $cmakeCleanMachineEnvScript -Encoding utf8
        Write-Host "Created: $cmakeCleanMachineEnvScript" -ForegroundColor Gray
        
        # --- Interaction: Prompt to remove persistent changes ---
        Write-Host ""
        $choice = Read-Host "Administrator rights required to Clean Machine Environment cmake changes? (y/n)"
        if ($choice -eq 'y' -or $choice -eq 'Y') {
            Write-Host "Executing $cmakeCleanMachineEnvScript..." -ForegroundColor Yellow
            try {
                # Start the generated script. It handles its own elevation logic.
                & $cmakeCleanMachineEnvScript
            }
            catch {
                Write-Error "Failed to execute the Clean Machine Environment script: $($_.Exception.Message)"
                return
            }
        }
        else {
            Write-Error "Skipped Clean Machine Environment cmake changes."
            return
        }

        # Cleanup
        Remove-Item $cmakeCleanMachineEnvScript -Recurse -Force -ErrorAction SilentlyContinue
    }
    
    $Source = Join-Path $RootzstdWorkspacePath "cmake"
    
    # 2. Filesystem Clean (Requires checking for locked files)
    # delete everithing we create don't fail later
    if (Test-Path $cmakeEnvScript) {
        Write-Host "  [DELETING] $cmakeEnvScript" -ForegroundColor Yellow
        Remove-Item $cmakeEnvScript -Recurse -Force -ErrorAction SilentlyContinue
    }
    if (Test-Path $cmakeMachineEnvScript) {
        Write-Host "  [DELETING] $cmakeMachineEnvScript" -ForegroundColor Yellow
        Remove-Item $cmakeMachineEnvScript -Recurse -Force -ErrorAction SilentlyContinue
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
    Get-ChildItem Env:\CMAKE_PATH* | Remove-Item -ErrorAction SilentlyContinue
    Get-ChildItem Env:\CMAKE_ROOT* | Remove-Item -ErrorAction SilentlyContinue
    Get-ChildItem Env:\CMAKE_BIN* | Remove-Item -ErrorAction SilentlyContinue

    Write-Host "--- CMake Purge Complete ---" -ForegroundColor Green
}

# We need to call Purge before dep-cmake or dependencie builds fails
if ($CMakeForceCleanup) {
    Invoke-CMakeVersionPurge -InstallPath $cmakeInstallDir
}

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

$RootPath = $RootzstdWorkspacePath

# --- 6. Path Resolution ---
Push-Location $RootPath

$Source         = Join-Path $RootPath "cmake"
$BuildDir       = Join-Path $Source "build_dir"
$RepoUrl        = $CMakeGitUrl
$Branch         = $CMakeGitBranch
$CMakeSource    = $Source
$tag_name       = $Branch
$url            = $RepoUrl

# --- 7. Source Management ---
if (Test-Path $Source) {
    Write-Host "Syncing CMake ($Branch) at $Source..." -ForegroundColor Cyan
    Set-Location $Source
    git fetch --all
    git reset --hard "origin/$Branch"
    git pull --recurse-submodules --force
    $tagCommit = (& git rev-parse --verify HEAD).Trim()
}
else {
    Write-Host "Cloning CMake ($Branch) into $Source..." -ForegroundColor Cyan
    git clone --recurse-submodules $RepoUrl $Source -b $Branch
    Set-Location $Source
    $tagCommit = (& git rev-parse --verify HEAD).Trim()
}

# --- 8. Clean & Build (Shadow Swap Logic) ---
# We use .exe extension so it remains 'executable' and detectable
$GlobalBinDir = "$env:BINARIES_PATH"
$cmakeBinPath = Join-Path $cmakeInstallDir "bin"

# 2. Check for existing installation
$cmakeExePath = Join-Path $cmakeBinPath "cmake.exe"
$TempCMakeDir = Join-Path $env:TEMP "cmake_old"
$TempCMakeBinDir = Join-Path $TempCMakeDir "bin"
$versionFile = Join-Path $cmakeInstallDir "version.json"

# --- 8. Clean & Build (Shadow Swap Logic) ---
$cmaketools = @("cmake.exe", "cmake-gui.exe", "cmcldeps.exe", "cpack.exe", "ctest.exe")

# Loop through each tool for the Shadow Swap
foreach ($toolName in $cmaketools) {
    $currentExePath = Join-Path $cmakeBinPath $toolName
    $tempExePath = Join-Path $TempCMakeBinDir $toolName
    $globalLinkPath = Join-Path $GlobalBinDir $toolName

    if (Test-Path $currentExePath) {
        # 1. Remove previous backup if it exists
        if (Test-Path $tempExePath) { Remove-Item $tempExePath -Force -ErrorAction SilentlyContinue } else {
            # Create a brand new, temp empty directory
            if (-not (Test-Path $TempCMakeBinDir)) {
                Write-Host "[INSTALL] Creating fresh temp directory: $TempCMakeBinDir" -ForegroundColor Cyan
                New-Item -Path $TempCMakeBinDir -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null
            }
        }

        # 2. Rename existing binary (The "Shadow Swap")
        Move-Item -Path $currentExePath -Destination $tempExePath -Force -ErrorAction SilentlyContinue
        Write-Host "[SWAP] Active $toolName -> $tempExePath" -ForegroundColor Yellow

        if (Test-Path $tempExePath) {
            Write-Host "Creating global symlink: $globalLinkPath" -ForegroundColor Cyan

            # 3. Clean up existing global symlink
            if (Test-Path $globalLinkPath) { Remove-Item $globalLinkPath -Force -ErrorAction SilentlyContinue }
            
            # 4. Create new global symlink/hardlink to the OLD/TEMP file
            # This keeps the environment functional DURING the build process
            try {
                New-Item -Path $globalLinkPath -ItemType SymbolicLink -Value $tempExePath -ErrorAction Stop | Out-Null
                Write-Host "[LINKED] $toolName (Global) -> $tempExePath" -ForegroundColor Green
            }
            catch {
                New-Item -Path $globalLinkPath -ItemType HardLink -Value $tempExePath | Out-Null
                Write-Host "[HARDLINKED] $toolName (Global) -> $tempExePath" -ForegroundColor Green
            }
        }
        else {
            Write-Error "CRITICAL: Could not find $toolName to swap at $tempExePath"
            # Cleanup dead global link
            if (Test-Path $globalLinkPath) {
                Write-Host "Cleaning up dead symlink at $globalLinkPath..." -ForegroundColor Yellow
                Remove-Item $globalLinkPath -Force -ErrorAction SilentlyContinue
            }
            Pop-Location; return
        }
    }
}

# Ensure fresh Install directory
if (Test-Path $cmakeInstallDir) {
    Write-Host "Wiping existing installation at $cmakeInstallDir..." -ForegroundColor Yellow
    Remove-Item $cmakeInstallDir -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "[INSTALL] Creating fresh directory: $cmakeBinPath" -ForegroundColor Cyan
New-Item -Path $cmakeBinPath -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null

# Ensure fresh build directory
if (Test-Path $BuildDir) { Remove-Item $BuildDir -Recurse -Force -ErrorAction SilentlyContinue }
New-Item -Path $BuildDir -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null

Write-Host "Configuring with Clang/Ninja..." -ForegroundColor Cyan
cmake -G "Ninja" `
    -S "$CMakeSource" `
    -B "$BuildDir" `
    -DCMAKE_POLICY_DEFAULT_CMP0091=NEW `
    -DCMAKE_POLICY_DEFAULT_CMP0109=NEW `
    -DCMAKE_C_COMPILER="clang" `
    -DCMAKE_CXX_COMPILER="clang++" `
    -DCMAKE_INSTALL_PREFIX="$cmakeInstallDir" `
    -DCMAKE_BUILD_TYPE=Release `
    -DBUILD_TESTING=OFF `
    -DCMAKE_C_FLAGS="-Wno-deprecated-declarations -D_CRT_SECURE_NO_WARNINGS=1" `
    -DCMAKE_CXX_FLAGS="-Wno-deprecated-declarations -D_CRT_SECURE_NO_WARNINGS=1" `
    --no-warn-unused-cli

if ($LASTEXITCODE -ne 0) { Write-Error "CMake configuration failed."; Pop-Location; return }

Write-Host "Building and Installing to $cmakeInstallDir..." -ForegroundColor Green
cmake --build "$BuildDir" --target INSTALL --config Release --parallel

if ($LASTEXITCODE -ne 0) { Write-Error "CMake Build failed with exit code $LASTEXITCODE"; Pop-Location; return }

Write-Host "Successfully built and installed CMake to $cmakeInstallDir!" -ForegroundColor Green

# Cleanup temporary build debris
Remove-Item $BuildDir -Recurse -Force -ErrorAction SilentlyContinue
if (Test-Path $TempCMakeDir) {
    Write-Host "Releasing old binary..." -ForegroundColor Gray
    # Give the OS a heartbeat to release file handles
    Start-Sleep -Milliseconds 500
    Remove-Item $TempCMakeDir -Recurse -Force -ErrorAction SilentlyContinue
}

# Generate Environment Helper with Clean Paths
$cmakeBinPath = $cmakeBinPath.TrimEnd('\')
$cmakeInstallDir = $cmakeInstallDir.TrimEnd('\')

# --- 9. Symlink to Global Binaries ---
if (Test-Path $cmakeExePath) {
    $rawVersion = (& $cmakeExePath --version | Select-Object -First 1).Trim()
    # We extract only the numeric part (e.g., 1.12.1) so [version] can handle it
    if ($rawVersion -match 'version\s+(\d+\.\d+\.\d+)') { $localVersion = $Matches[1] } else { $localVersion = "0.0.0" }
    
    # Save new version state
    $cmakeVersion = $localVersion
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
    foreach ($toolName in $cmaketools) {
        $newExePath    = Join-Path $cmakeBinPath $toolName
        $globalLinkPath = Join-Path $GlobalBinDir $toolName
        
        Write-Host "Creating global symlink: $globalLinkPath" -ForegroundColor Cyan

        if (Test-Path $newExePath) {
            if (Test-Path $globalLinkPath) { Remove-Item $globalLinkPath -Force -ErrorAction SilentlyContinue }
            try {
                New-Item -Path $globalLinkPath -ItemType SymbolicLink -Value $newExePath -ErrorAction Stop | Out-Null
                Write-Host "[LINKED] CMake (Global) -> $newExePath" -ForegroundColor Green
            }
            catch {
                New-Item -Path $globalLinkPath -ItemType HardLink -Value $newExePath | Out-Null
                Write-Host "[HARDLINKED] CMake (Global) -> $newExePath" -ForegroundColor Green
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

    Write-Host "[LINKED] CMake is now globally available via %BINARIES_PATH%" -ForegroundColor Green
    
    # --- 10. Create Environment Helper ---
    Write-Host "Generating environment helper script..." -ForegroundColor Cyan
    $EnvContent = @'
# CMAKE Environment Setup
$cmakebin = "VALUE_BIN_PATH"
$cmakeroot = "VALUE_ROOT_PATH"
$cmakeversion = "VALUE_VERSION"
$env:CMAKE_PATH = $cmakeroot
$env:CMAKE_ROOT = $cmakeroot
$env:CMAKE_BIN = $cmakebin
if ($env:PATH -notlike "*$cmakebin*") { $env:PATH = $cmakebin + ";" + $env:PATH; $env:PATH = ($env:PATH).Replace(";;", ";") }
Write-Host "CMake Environment Loaded (Version: $cmakeversion) (Bin: $cmakebin)" -ForegroundColor Green
Write-Host "CMAKE_ROOT: $env:CMAKE_ROOT" -ForegroundColor Gray
'@  -replace "VALUE_BIN_PATH", $cmakeBinPath `
    -replace "VALUE_ROOT_PATH", $cmakeInstallDir `
    -replace "VALUE_VERSION", $cmakeVersion

    $EnvContent | Out-File -FilePath $cmakeEnvScript -Encoding utf8
    Write-Host "Created: $cmakeEnvScript" -ForegroundColor Gray

    # Update Current Session
    if (Test-Path $cmakeEnvScript) { . $cmakeEnvScript } else {
        Write-Error "cmake build install finished but $cmakeEnvScript was not created."
        Pop-Location; return
    }

    Write-Host "CMake Version: $(& $cmakeExePath --version | Select-Object -First 1)" -ForegroundColor Gray
    
    if ($CMakeWithMachineEnvironment)
    {
        # Generating Machine Environment wich add to the persist registry machine Environment
        $MachineEnvContent = @'
# CMake Machine Environment Setup

# --- 0. Self-Elevation Logic ---
$IsAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$ScopeColor = "Cyan"

if (-not $IsAdmin) {
    Write-Host "Elevation required to set cmake system variables. Relaunching as Administrator..." -ForegroundColor Yellow
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

$cmakeroot = "VALUE_ROOT_PATH"
$cmakebin = "VALUE_BIN_PATH"
$cmakeversion = "VALUE_VERSION"

$TargetScope = if ($IsAdmin) { "Machine" } else { "User" }
$RegPath = if ($IsAdmin) { "System\CurrentControlSet\Control\Session Manager\Environment" } else { "Environment" }
$RegRoot = if ($IsAdmin) { "LocalMachine" } else { "CurrentUser" }

# Open the registry key once
$RegKey = [Microsoft.Win32.Registry]::$RegRoot.OpenSubKey($RegPath, $true)

# Open the registry key directly to read the RAW (unexpanded) string
$CurrentRawPath = $RegKey.GetValue("TOOLS_PATH", "", [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)

# Cleanup: Remove empty strings, any path containing $cmakeroot, and the current target (to avoid dups)
$CleanedPathList = $CurrentRawPath -split ';' | Where-Object { 
    -not [string]::IsNullOrWhitespace($_) -and 
    $_ -notlike "*$cmakeroot*"
}

$NewRawPath = ($CleanedPathList -join ";").Replace(";;", ";")

$TargetPath = $cmakebin

# Rebuild
$NewRawPath = ($NewRawPath + ";" + $TargetPath + ";").Replace(";;", ";")
Write-Host "[UPDATED] ($TargetScope) '$cmakebin' synced in TOOLS_PATH" -ForegroundColor $ScopeColor

# Save as ExpandString
$RegKey.SetValue("TOOLS_PATH", $NewRawPath, [Microsoft.Win32.RegistryValueKind]::ExpandString)
$env:TOOLS_PATH = $NewRawPath

$RegKey.Close()

$env:CMAKE_ROOT = $cmakeroot
Write-Host "CMake Environment Loaded (Version: $cmakeversion) (Bin: $cmakebin)" -ForegroundColor Green
Write-Host "CMAKE_ROOT: $env:CMAKE_ROOT" -ForegroundColor Gray
'@  -replace "VALUE_ROOT_PATH", $cmakeInstallDir `
    -replace "VALUE_BIN_PATH", $cmakeBinPath `
    -replace "VALUE_VERSION", $cmakeVersion

        $MachineEnvContent | Out-File -FilePath $cmakeMachineEnvScript -Encoding utf8
        Write-Host "Created: $cmakeMachineEnvScript" -ForegroundColor Gray
        
        # --- Interaction: Prompt to apply persistent changes ---
        Write-Host ""
        $choice = Read-Host "Do you want to run the Machine Environment script now to persist CMake changes to the Registry? (y/n)"
        if ($choice -eq 'y' -or $choice -eq 'Y') {
            Write-Host "Executing $cmakeMachineEnvScript..." -ForegroundColor Yellow
            try {
                # Start the generated script. It handles its own elevation logic.
                & $cmakeMachineEnvScript
            }
            catch {
                Write-Error "Failed to execute the Machine Environment script: $($_.Exception.Message)"
            }
        }
        else {
            Write-Host "Skipped persistent registry update. You can run it later at: $cmakeMachineEnvScript" -ForegroundColor Gray
        }
    }

    # --- Return to Start ---
    Pop-Location
    Write-Host "Successfully Done! and returned to: $(Get-Location)" -ForegroundColor DarkGreen
} else {
    Write-Error "cmake.exe was not found in the $cmakeBinPath folder."
    $cmaketools | ForEach-Object { 
        $globalLinkPath = Join-Path $GlobalBinDir $_
        if (Test-Path $globalLinkPath) {
            Write-Host "Cleaning up dead symlink at $globalLinkPath..." -ForegroundColor Yellow
            Remove-Item $globalLinkPath -Force -ErrorAction SilentlyContinue
        } 
    }
    Pop-Location; return
}
