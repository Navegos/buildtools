# SPDX-FileCopyrightText: Copyright (c) 2026 Navegos. @DevelVitorF. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
# project: buildtools
# file: x64-windows/build-ninja.ps1
# created: 2026-02-28
# lastModified: 2026-04-26

param (
    [Parameter(HelpMessage = "Base workspace path", Mandatory = $false)]
    [string]$workspacePath = $null,

    [Parameter(HelpMessage = "ninja git repo url", Mandatory = $false)]
    [string]$gitUrl = "https://github.com/ninja-build/ninja.git",
    
    [Parameter(HelpMessage = "ninja git branch to sync from", Mandatory = $false)]
    [string]$gitBranch = "master",

    [Parameter(HelpMessage = "Path for ninja storage", Mandatory = $false)]
    [string]$ninjaInstallDir = "$env:LIBRARIES_PATH\ninja",
    
    [Parameter(HelpMessage = "Force a full purge of the local Ninja version before continuing", Mandatory = $false)]
    [switch]$forceCleanup,
    
    [Parameter(HelpMessage = "Add's Ninja Machine Environment Variables. Requires Machine Administrator Rights.", Mandatory = $false)]
    [switch]$withMachineEnvironment
)

# Capture parameters
$NinjaWorkspacePath = $workspacePath
$NinjaGitUrl = $gitUrl
$NinjaGitBranch = $gitBranch
$NinjaForceCleanup = $forceCleanup
$NinjaWithMachineEnvironment = $withMachineEnvironment

if ([string]::IsNullOrWhitespace($env:ENVIRONMENT_PATH) -or -not (Test-Path $env:ENVIRONMENT_PATH) -or [string]::IsNullOrWhitespace($env:BINARIES_PATH) -or -not (Test-Path $env:BINARIES_PATH) -or [string]::IsNullOrWhitespace($env:LIBRARIES_PATH) -or -not (Test-Path $env:LIBRARIES_PATH)) {
    Write-Error "User Environment variables missing. With administrator privileges run adduserpaths.ps1 -LibrariesDir 'Path\for\Libraries' -BinariesDir 'Path\for\Binaries' -EnvironmentDir 'Path\for\Environment'"
    return
}

$EnvironmentDir = "$env:ENVIRONMENT_PATH"

$ninjaEnvScript = Join-Path $EnvironmentDir "env-ninja.ps1"
$ninjaMachineEnvScript = Join-Path $EnvironmentDir "machine-env-ninja.ps1"
$RootNinjaWorkspacePath = if ([string]::IsNullOrWhitespace($NinjaWorkspacePath)) { Get-Location } else { $NinjaWorkspacePath }

# --- 1. Cleanup Mechanism ---
function Invoke-NinjaVersionPurge {
    param ([string]$InstallPath)
    Write-Host "--- Initiating Ninja Purge ---" -ForegroundColor Cyan

    if ($NinjaWithMachineEnvironment)
    {
        $ninjaCleanMachineEnvScript = Join-Path $env:TEMP "clean-machine-env-ninja.ps1"

        # Generating Clean Machine Environment wich removes the persist registry machine Environment
        $CleanMachineEnvContent = @'
# Ninja Clean Machine Environment Setup

# --- 0. Self-Elevation Logic ---
$IsAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$ScopeColor = "Cyan"

if (-not $IsAdmin) {
    Write-Host "Elevation required to clean ninja system variables. Relaunching as Administrator..." -ForegroundColor Yellow
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

$ninjaroot = "VALUE_ROOT_PATH"

$TargetScope = if ($IsAdmin) { "Machine" } else { "User" }
$RegPath = if ($IsAdmin) { "System\CurrentControlSet\Control\Session Manager\Environment" } else { "Environment" }
$RegRoot = if ($IsAdmin) { "LocalMachine" } else { "CurrentUser" }

# 1. Registry Cleanup (TOOLS_PATH)
$RegKey = [Microsoft.Win32.Registry]::$RegRoot.OpenSubKey($RegPath, $true)

# Open the registry key directly to read the RAW (unexpanded) string
$RawPath = $RegKey.GetValue("TOOLS_PATH", "", [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)

# Cleanup: Remove empty strings, any path containing $ninjaroot,
$CleanPath = ($RawPath -split ';' | Where-Object { $_ -notlike "*$ninjaroot*" }) -join ";"

# Save as ExpandString
$RegKey.SetValue("TOOLS_PATH", $CleanPath, [Microsoft.Win32.RegistryValueKind]::ExpandString)
$env:TOOLS_PATH = $CleanPath

$RegKey.Close()

Write-Host "[REMOVED] ($TargetScope) all '*$ninjaroot*' removed from TOOLS_PATH" -ForegroundColor $ScopeColor
'@  -replace "VALUE_ROOT_PATH", $InstallPath

        $CleanMachineEnvContent | Out-File -FilePath $ninjaCleanMachineEnvScript -Encoding utf8
        Write-Host "Created: $ninjaCleanMachineEnvScript" -ForegroundColor Gray
        
        # --- Interaction: Prompt to remove persistent changes ---
        Write-Host ""
        $choice = Read-Host "Administrator rights required to Clean Machine Environment ninja changes? (y/n)"
        if ($choice -eq 'y' -or $choice -eq 'Y') {
            Write-Host "Executing $ninjaCleanMachineEnvScript..." -ForegroundColor Yellow
            try {
                # Start the generated script. It handles its own elevation logic.
                & $ninjaCleanMachineEnvScript
            }
            catch {
                Write-Error "Failed to execute the Clean Machine Environment script: $($_.Exception.Message)"
                return
            }
        }
        else {
            Write-Error "Skipped Clean Machine Environment ninja changes."
            return
        }

        # Cleanup
        Remove-Item $ninjaCleanMachineEnvScript -Recurse -Force -ErrorAction SilentlyContinue
    }

    $Source         = Join-Path $RootNinjaWorkspacePath "ninja"
    
    # 2. Filesystem Clean (Requires checking for locked files)
    # delete everithing we create don't fail later
    if (Test-Path $ninjaEnvScript) {
        Write-Host "  [DELETING] $ninjaEnvScript" -ForegroundColor Yellow
        Remove-Item $ninjaEnvScript -Recurse -Force -ErrorAction SilentlyContinue
    }
    if (Test-Path $ninjaMachineEnvScript) {
        Write-Host "  [DELETING] $ninjaMachineEnvScript" -ForegroundColor Yellow
        Remove-Item $ninjaMachineEnvScript -Recurse -Force -ErrorAction SilentlyContinue
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
    Get-ChildItem Env:\NINJA_PATH* | Remove-Item -ErrorAction SilentlyContinue
    Get-ChildItem Env:\NINJA_ROOT* | Remove-Item -ErrorAction SilentlyContinue
    Get-ChildItem Env:\NINJA_BIN* | Remove-Item -ErrorAction SilentlyContinue

    Write-Host "--- Ninja Purge Complete ---" -ForegroundColor Green
}

# We need to call Purge before dep-ninja or dependencie builds fails
if ($NinjaForceCleanup) {
    Invoke-NinjaVersionPurge -InstallPath $ninjaInstallDir
}

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

$RootPath = $RootNinjaWorkspacePath

# --- 6. Path Resolution ---
Push-Location $RootPath

$Source         = Join-Path $RootPath "ninja"
$BuildDir       = Join-Path $Source "build_dir"  # Nested inside source
$RepoUrl        = $NinjaGitUrl
$Branch         = $NinjaGitBranch
$CMakeSource    = $Source
$tag_name       = $Branch
$url            = $RepoUrl

# --- 7. Source Management ---
if (Test-Path $Source) {
    Write-Host "Syncing ninja ($Branch) at $Source..." -ForegroundColor Cyan
    Set-Location $Source
    git fetch --all
    git reset --hard "origin/$Branch"
    git pull --recurse-submodules --force
    $tagCommit = (& git rev-parse --verify HEAD).Trim()
} else {
    Write-Host "Cloning ninja ($Branch) into $Source..." -ForegroundColor Cyan
    git clone --recurse-submodules $RepoUrl $Source -b $Branch
    Set-Location $Source
    $tagCommit = (& git rev-parse --verify HEAD).Trim()
}

# --- 8. Clean & Build (Shadow Swap Logic) ---
# We use .exe extension so it remains 'executable' and detectable
$GlobalBinDir = "$env:BINARIES_PATH"
$TargetLink = Join-Path $GlobalBinDir "ninja.exe"
$ninjaBinPath = Join-Path $ninjaInstallDir "bin"

# 2. Check for existing installation
$ninjaExePath = Join-Path $ninjaInstallDir "ninja.exe"
if (-not (Test-Path $ninjaExePath)) { $ninjaExePath = Join-Path $ninjaBinPath "ninja.exe" }
$TempNinjaDir = Join-Path $env:TEMP "ninja_old"
$TempNinjaBinDir = Join-Path $TempNinjaDir "bin"
$TempNinja = Join-Path $TempNinjaBinDir "ninja.exe"
$versionFile = Join-Path $ninjaInstallDir "version.json"

if (Test-Path $ninjaExePath) {
    if (Test-Path $TempNinja) { Remove-Item $TempNinja -Force -ErrorAction SilentlyContinue } else {
        # Create a brand new, temp empty directory
        if (-not (Test-Path $TempNinjaBinDir))
        {
            Write-Host "[INSTALL] Creating fresh temp directory: $TempNinjaBinDir" -ForegroundColor Cyan
            New-Item -Path $TempNinjaBinDir -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null
        }
    }

    # 1. Rename the existing binary (Windows allows this while running)
    Move-Item -Path $ninjaExePath -Destination $TempNinja -Force -ErrorAction SilentlyContinue
    Write-Host "[SWAP] Active ninja.exe -> $TempNinja" -ForegroundColor Yellow

    if (Test-Path $TempNinja) {
        Write-Host "Creating global symlink: $TargetLink" -ForegroundColor Cyan

        # Remove existing symlink we are creating a new one
        if (Test-Path $TargetLink) { Remove-Item $TargetLink -Force -ErrorAction SilentlyContinue }

        # Create the Symbolic Link
        try {
            New-Item -Path $TargetLink -ItemType SymbolicLink -Value $TempNinja -ErrorAction Stop | Out-Null
            Write-Host "[LINKED] Ninja (Global) -> $TempNinja" -ForegroundColor Green
        }
        catch {
            New-Item -Path $TargetLink -ItemType HardLink -Value $TempNinja | Out-Null
            Write-Host "[HARDLINKED] Ninja (Global) -> $TempNinja" -ForegroundColor Green
        }

        Write-Host "[LINKED] Ninja is now globally available via %BINARIES_PATH%" -ForegroundColor Green
    }
    else {
        Write-Error "CRITICAL: Could not find ninja.exe to symlink at $TempNinja"
        if (Test-Path $TargetLink) { 
            Write-Host "Cleaning up dead symlink at $TargetLink..." -ForegroundColor Yellow
            Remove-Item $TargetLink -Force -ErrorAction SilentlyContinue 
        }
        Pop-Location; return
    }
}

# Ensure fresh Install directory
if (Test-Path $ninjaInstallDir) {
    Write-Host "Wiping existing installation at $ninjaInstallDir..." -ForegroundColor Yellow
    Remove-Item $ninjaInstallDir -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "[INSTALL] Creating fresh directory: $ninjaBinPath" -ForegroundColor Cyan
New-Item -Path $ninjaBinPath -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null

# Ensure fresh build directory
if (Test-Path $BuildDir) { Remove-Item $BuildDir -Recurse -Force -ErrorAction SilentlyContinue }
New-Item -Path $BuildDir -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null

Write-Host "Configuring with Clang/Ninja..." -ForegroundColor Cyan
cmake -G "Ninja" `
    -S "$CMakeSource" `
    -B "$BuildDir" `
    -DCMAKE_POLICY_DEFAULT_CMP0091=NEW `
    -DCMAKE_POLICY_DEFAULT_CMP0109=NEW `
    -DCMAKE_CXX_COMPILER="clang++" `
    -DCMAKE_INSTALL_PREFIX="$ninjaInstallDir" `
    -DCMAKE_BUILD_TYPE=Release `
    -DBUILD_TESTING=OFF `
    -DCMAKE_CXX_FLAGS="-Wno-deprecated-declarations -D_CRT_SECURE_NO_WARNINGS=1" `
    --no-warn-unused-cli

if ($LASTEXITCODE -ne 0) { Write-Error "ninja CMake configuration failed."; Pop-Location; return }

Write-Host "Building and Installing to $ninjaInstallDir..." -ForegroundColor Green
cmake --build "$BuildDir" --target install --config Release --parallel

if ($LASTEXITCODE -ne 0) { Write-Error "ninja Build failed with exit code $LASTEXITCODE"; Pop-Location; return }

Write-Host "Successfully built and installed ninja to $ninjaInstallDir!" -ForegroundColor Green

# Cleanup temporary build debris
Remove-Item $BuildDir -Recurse -Force -ErrorAction SilentlyContinue
if (Test-Path $TempNinjaDir) {
    Write-Host "Releasing old temp directory: $TempNinjaBinDir" -ForegroundColor Cyan
    # Give the OS a heartbeat to release file handles
    Start-Sleep -Milliseconds 500
    Remove-Item $TempNinjaDir -Recurse -Force -ErrorAction SilentlyContinue
}

# Generate Environment Helper with Clean Paths
$ninjaBinPath = $ninjaBinPath.TrimEnd('\')
$ninjaInstallDir = $ninjaInstallDir.TrimEnd('\')

# --- 9. Symlink to Global Binaries ---
$ninjaExePath = Join-Path $ninjaInstallDir "ninja.exe"
if (-not (Test-Path $ninjaExePath)) { $ninjaExePath = Join-Path $ninjaBinPath "ninja.exe" }

if (Test-Path $ninjaExePath) {
    # Ninja --version usually returns a single string like "1.12.1" or "1.12.1.git"
    $rawVersion = (& $ninjaExePath --version).Trim()
    # We extract only the numeric part (e.g., 1.12.1) so [version] can handle it
    if ($rawVersion -match '^(\d+\.\d+\.\d+)') { $localVersion = $Matches[1] } else { $localVersion = "0.0.0" }

    # Save new version state
    $ninjaVersion = $localVersion
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

    Write-Host "Creating global symlink: $TargetLink" -ForegroundColor Cyan

    # Remove existing symlink we are creating a new one
    if (Test-Path $TargetLink) { Remove-Item $TargetLink -Force -ErrorAction SilentlyContinue }
    
    # Create the Symbolic Link
    try {
        New-Item -Path $TargetLink -ItemType SymbolicLink -Value $ninjaExePath -ErrorAction Stop | Out-Null
        Write-Host "[LINKED] Ninja (Global) -> $ninjaExePath" -ForegroundColor Green
    } catch {
        New-Item -Path $TargetLink -ItemType HardLink -Value $ninjaExePath | Out-Null
        Write-Host "[HARDLINKED] Ninja (Global) -> $ninjaExePath" -ForegroundColor Green
    }
    
    Write-Host "[LINKED] Ninja is now globally available via %BINARIES_PATH%" -ForegroundColor Green

    # --- 10. Create Environment Helper ---
    Write-Host "Generating environment helper script..." -ForegroundColor Cyan
    $EnvContent = @'
# NINJA Environment Setup
$ninjaroot = "VALUE_ROOT_PATH"
$ninjabin = "VALUE_BIN_PATH"
$ninjaexe = "VALUE_EXE_PATH"
$ninjaversion = "VALUE_VERSION"
$env:NINJA_PATH = $ninjaroot
$env:NINJA_ROOT = $ninjaroot
$env:NINJA_BIN = $ninjabin
$env:BINARY_NINJA = $ninjaexe
if ($env:PATH -notlike "*$ninjabin*") { $env:PATH = $ninjabin + ";" + $env:PATH; $env:PATH = ($env:PATH).Replace(";;", ";") }
Write-Host "Ninja Environment Loaded (Version: $ninjaversion) (Bin: $ninjabin)" -ForegroundColor Green
Write-Host "NINJA_ROOT: $env:NINJA_ROOT" -ForegroundColor Gray
'@  -replace "VALUE_BIN_PATH", $ninjaBinPath `
    -replace "VALUE_EXE_PATH", $ninjaExePath `
    -replace "VALUE_ROOT_PATH", $ninjaInstallDir `
    -replace "VALUE_VERSION", $ninjaVersion

    $EnvContent | Out-File -FilePath $ninjaEnvScript -Encoding utf8 -force
    Write-Host "Created: $ninjaEnvScript" -ForegroundColor Gray

    # Update Current Session
    if (Test-Path $ninjaEnvScript) { . $ninjaEnvScript } else {
        Write-Error "ninja build install finished but $ninjaEnvScript was not created."
        Pop-Location; return
    }

    Write-Host "Ninja Version: $(& $ninjaExePath --version)" -ForegroundColor Gray
    
    if ($NinjaWithMachineEnvironment)
    {
        # Generating Machine Environment wich add to the persist registry machine Environment
        $MachineEnvContent = @'
# Ninja Machine Environment Setup

# --- 0. Self-Elevation Logic ---
$IsAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$ScopeColor = "Cyan"

if (-not $IsAdmin) {
    Write-Host "Elevation required to set ninja system variables. Relaunching as Administrator..." -ForegroundColor Yellow
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

$ninjaroot = "VALUE_ROOT_PATH"
$ninjabin = "VALUE_BIN_PATH"
$ninjaversion = "VALUE_VERSION"

$TargetScope = if ($IsAdmin) { "Machine" } else { "User" }
$RegPath = if ($IsAdmin) { "System\CurrentControlSet\Control\Session Manager\Environment" } else { "Environment" }
$RegRoot = if ($IsAdmin) { "LocalMachine" } else { "CurrentUser" }

# Open the registry key once
$RegKey = [Microsoft.Win32.Registry]::$RegRoot.OpenSubKey($RegPath, $true)

# Open the registry key directly to read the RAW (unexpanded) string
$CurrentRawPath = $RegKey.GetValue("TOOLS_PATH", "", [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)

# Cleanup: Remove empty strings, any path containing $ninjaroot, and the current target (to avoid dups)
$CleanedPathList = $CurrentRawPath -split ';' | Where-Object { 
    -not [string]::IsNullOrWhitespace($_) -and 
    $_ -notlike "*$ninjaroot*"
}

$NewRawPath = ($CleanedPathList -join ";").Replace(";;", ";")

$TargetPath = $ninjabin

# Rebuild
$NewRawPath = ($NewRawPath + ";" + $TargetPath + ";").Replace(";;", ";")
Write-Host "[UPDATED] ($TargetScope) '$ninjabin' synced in TOOLS_PATH" -ForegroundColor $ScopeColor

# Save as ExpandString
$RegKey.SetValue("TOOLS_PATH", $NewRawPath, [Microsoft.Win32.RegistryValueKind]::ExpandString)
$env:TOOLS_PATH = $NewRawPath

$RegKey.Close()

$env:NINJA_ROOT = $ninjaroot
Write-Host "Ninja Environment Loaded (Version: $ninjaversion) (Bin: $ninjabin)" -ForegroundColor Green
Write-Host "NINJA_ROOT: $env:NINJA_ROOT" -ForegroundColor Gray
'@  -replace "VALUE_ROOT_PATH", $ninjaInstallDir `
    -replace "VALUE_BIN_PATH", $ninjaBinPath `
    -replace "VALUE_VERSION", $ninjaVersion

        $MachineEnvContent | Out-File -FilePath $ninjaMachineEnvScript -Encoding utf8 -force
        Write-Host "Created: $ninjaMachineEnvScript" -ForegroundColor Gray
        
        # --- Interaction: Prompt to apply persistent changes ---
        Write-Host ""
        $choice = Read-Host "Do you want to run the Machine Environment script now to persist Ninja changes to the Registry? (y/n)"
        if ($choice -eq 'y' -or $choice -eq 'Y') {
            Write-Host "Executing $ninjaMachineEnvScript..." -ForegroundColor Yellow
            try {
                # Start the generated script. It handles its own elevation logic.
                & $ninjaMachineEnvScript
            }
            catch {
                Write-Error "Failed to execute the Machine Environment script: $($_.Exception.Message)"
            }
        }
        else {
            Write-Host "Skipped persistent registry update. You can run it later at: $ninjaMachineEnvScript" -ForegroundColor Gray
        }
    }

    # --- Return to Start ---
    Pop-Location
    Write-Host "Successfully Done! and returned to: $(Get-Location)" -ForegroundColor DarkGreen
} else {
    Write-Error "ninja.exe was not found in the $ninjaBinPath folder."
    if (Test-Path $TargetLink) { 
        Write-Host "Cleaning up dead symlink at $TargetLink..." -ForegroundColor Yellow
        Remove-Item $TargetLink -Force -ErrorAction SilentlyContinue 
    }
    Pop-Location; return
}
