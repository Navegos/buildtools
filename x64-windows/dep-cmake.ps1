# Copyright 2026 (C) Navegos. DevelVitorF. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
# file:x64-windows/dep-cmake.ps1

param (
    [Parameter(HelpMessage="Path for cmake storage", Mandatory=$false)]
    [string]$cmakeInstallDir = "$env:LIBRARIES_PATH\cmake",
    
    [Parameter(HelpMessage = "Force a full uninstallation of the local CMake version before continuing", Mandatory = $false)]
    [switch]$forceCleanup,
    
    [Parameter(HelpMessage = "Add's CMake Machine Environment Variables. Requires Machine Administrator Rights.", Mandatory = $false)]
    [switch]$withMachineEnvironment
)

if ([string]::IsNullOrWhitespace($env:ENVIRONMENT_PATH) -or -not (Test-Path $env:ENVIRONMENT_PATH) -or [string]::IsNullOrWhitespace($env:BINARIES_PATH) -or -not (Test-Path $env:BINARIES_PATH) -or [string]::IsNullOrWhitespace($env:LIBRARIES_PATH) -or -not (Test-Path $env:LIBRARIES_PATH)) {
    Write-Error "User Environment variables missing. With administrator privileges run adduserpaths.ps1 -LibrariesDir 'Path\for\Libraries' -BinariesDir 'Path\for\Binaries' -EnvironmentDir 'Path\for\Environment'"
    return
}

$EnvironmentDir = "$env:ENVIRONMENT_PATH"

# if Symlink present delete
$GlobalBinDir = "$env:BINARIES_PATH"
# Remove existing symlink we are creating a new one
$cmaketools = @("cmake.exe", "cmake-gui.exe", "cmcldeps.exe", "cpack.exe", "ctest.exe")
foreach ($cmaketool in $cmaketools) {
    $target = Join-Path $GlobalBinDir $cmaketool
    if (Test-Path $target) { Remove-Item $target -Force -ErrorAction SilentlyContinue }
}
$cmakeBinPath = Join-Path $cmakeInstallDir "bin"
$cmakeExePath = Join-Path $cmakeBinPath "cmake.exe"
$versionFile = Join-Path $cmakeInstallDir "version.json"

# Version Detection
$repo = "Kitware/CMake"
try {
    $latestRelease = Invoke-RestMethod -Uri "https://api.github.com/repos/$repo/releases/latest"
    $url = $latestRelease.url
    $tag_name = $latestRelease.tag_name
    $updated_at = $latestRelease.updated_at
    $remoteVersionString = $latestRelease.tag_name.TrimStart('v')
    $refTags = Invoke-RestMethod -Uri "https://api.github.com/repos/$repo/git/ref/tags/$tag_name"
    $tagCommit = $refTags.object.sha
    
    # Clean remote version for comparison (e.g., "1.12.1")
    if ($remoteVersionString -match '^(\d+\.\d+\.\d+)') { $remoteVersion = $Matches[1] }
} catch {
    Write-Warning "Could not connect to GitHub. Using 0.0.0 for remote."
    $url = "ERR_CONNECTION_TIMED_OUT"
    $tag_name = "0.0.0"
    $updated_at = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssZ")
    $remoteVersion = "0.0.0"
    $tagCommit = "0000000000000000000000000000000000000000"
}

# --- 1. Cleanup Mechanism ---
function Invoke-CMakeVersionPurge {
    param ([string]$InstallPath)
    Write-Host "--- Initiating CMake Purge ---" -ForegroundColor Cyan

    if ($withMachineEnvironment)
    {
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

    # 2. Filesystem Nuke (Requires checking for locked files)
    if (Test-Path $InstallPath) {
        Write-Host "  [DELETING] $InstallPath" -ForegroundColor Yellow
        Remove-Item $InstallPath -Recurse -Force -ErrorAction SilentlyContinue
    }

    Write-Host "--- CMake Purge Complete ---" -ForegroundColor Green
}

$localVersion = "0.0.0"
$rawVersion = "0.0.0"
if (Test-Path $cmakeExePath) {
    $rawVersion = (& $cmakeExePath --version | Select-Object -First 1).Trim()
    if ($rawVersion -match 'version\s+(\d+\.\d+\.\d+)') { $localVersion = $Matches[1] }
}

if (Test-Path $versionFile) {
    $localVersion = (Get-Content $versionFile | ConvertFrom-Json).version
}

if ($forceCleanup) {
    Invoke-CMakeVersionPurge -InstallPath $cmakeInstallDir
    # Reset trackers to force a fresh install
    $localVersion = "0.0.0"
}

# --- 2. Install or Skip ---
$vLocal  = [version]$localVersion
$vRemote = [version]$remoteVersion

if ($vLocal -ge $vRemote -and $localVersion -ne "0.0.0") {
    Write-Host "[SKIP] CMake $localVersion is already installed and up to date at: $cmakeExePath" -ForegroundColor Green
    Write-Host "CMake Version: $(& $cmakeExePath --version | Select-Object -First 1)" -ForegroundColor Gray

    # 1. Locate the bin folder and the root folder
    $cmakeVersion = $localVersion
    $cmakeBinPath = Split-Path -Path $cmakeExePath -Parent
    $cmakeInstallDir = Split-Path -Path $cmakeBinPath -Parent
    
    if (-not (Test-Path $versionFile)) {
        $versionInfo = @{
            url        = $url;
            tag_name   = $tag_name;
            commit     = $tagCommit;
            version    = $localVersion;
            rawversion = $rawVersion;
            date       = (Get-Date).ToString("yyyy-MM-dd");
            updated_at = $updated_at;
            type       = "rel_dist";
        }
        $versionInfo | ConvertTo-Json | Out-File -FilePath $versionFile -Encoding utf8 -Force
    }
} else {
    Write-Host "[UPDATE] Local: $localVersion -> Remote: $remoteVersion" -ForegroundColor Yellow
    
    # --- 2. Prepare Clean Install Directory ---
    if (Test-Path $cmakeInstallDir) {
        Write-Host "[CLEANUP] Removing existing CMake installation at $cmakeInstallDir..." -ForegroundColor Yellow
        # We remove the content and the folder to ensure a completely fresh folder entry
        Remove-Item -Path $cmakeInstallDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    # Create a brand new, empty directory
    Write-Host "[INSTALL] Creating fresh directory: $cmakeInstallDir" -ForegroundColor Cyan
    New-Item -Path $cmakeInstallDir -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null

    try {
        $asset = $latestRelease.assets | Where-Object { $_.name -match "windows-x86_64\.zip$" } | Select-Object -First 1
        $zipFile = Join-Path $env:TEMP $asset.name

        Write-Host "Downloading $($asset.name)..." -ForegroundColor Cyan
        Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $zipFile

        Write-Host "Extracting and flattening..." -ForegroundColor Gray
        $tempExtractPath = Join-Path $env:TEMP "cmake_extract_$(Get-Random)"
        Expand-Archive -Path $zipFile -DestinationPath $tempExtractPath -Force

        # Kitware zips usually have a single root folder like 'cmake-3.30.0-windows-x86_64'
        # We find that folder and move its contents to the final destination
        $internalRoot = Get-ChildItem -Path $tempExtractPath -Directory | Select-Object -First 1
        if ($internalRoot) {
            Write-Host "Flattening directory structure..." -ForegroundColor Gray
            # Wipe old install to ensure clean update
            if (Test-Path $cmakeBinPath) { Remove-Item "$cmakeInstallDir\*" -Recurse -Force -Exclude "version.json" }
            Get-ChildItem -Path $internalRoot.FullName | Move-Item -Destination $cmakeInstallDir -Force -ErrorAction SilentlyContinue
        }
        
        $cmakeVersion = $remoteVersion
        if (Test-Path $cmakeExePath) {
            $rawVersion = (& $cmakeExePath --version | Select-Object -First 1).Trim()
        }
        $versionInfo = @{
            url        = $url;
            tag_name   = $tag_name;
            commit     = $tagCommit;
            version    = $remoteVersion;
            rawversion = $rawVersion;
            date       = (Get-Date).ToString("yyyy-MM-dd");
            updated_at = $updated_at;
            type       = "rel_dist";
        }
        $versionInfo | ConvertTo-Json | Out-File -FilePath $versionFile -Encoding utf8 -Force
    
        # Cleanup extraction debris
        Remove-Item $zipFile -Force -ErrorAction SilentlyContinue
        Remove-Item $tempExtractPath -Recurse -Force -ErrorAction SilentlyContinue

        Write-Host "CMake $remoteVersion installed successfully!" -ForegroundColor DarkGreen
    }
    catch {
        Write-Error "Failed to install CMake: $($_.Exception.Message)"
        return # Stop execution on failure
    }
}

# --- 3. Finalize Helpers & Symlinks ---
if (Test-Path $cmakeExePath) {
    # Helper Script Generation
    Write-Host "Generating environment helper script..." -ForegroundColor Cyan
    $cmakeEnvScript = Join-Path $EnvironmentDir "env-cmake.ps1"

    # Generate Environment Helper with Clean Paths
    $cmakeBinPath = $cmakeBinPath.TrimEnd('\')
    $cmakeInstallDir = $cmakeInstallDir.TrimEnd('\')

    # Using a literal here-string with -replace to avoid accidental expansion of $env:PATH during creation
    $EnvContent = @'
# CMAKE Environment Setup
$cmakeroot = "VALUE_ROOT_PATH"
$cmakebin = "VALUE_BIN_PATH"
$cmakeversion = "VALUE_VERSION"
$env:CMAKE_PATH = $cmakeroot
$env:CMAKE_ROOT = $cmakeroot
$env:CMAKE_BIN = $cmakebin
if ($env:PATH -notlike "*$cmakebin*") { $env:PATH = $cmakebin + ";" + $env:PATH }
Write-Host "CMake Environment Loaded (Version: $cmakeversion) (Bin: $cmakebin)" -ForegroundColor Green
Write-Host "CMAKE_ROOT: $env:CMAKE_ROOT" -ForegroundColor Gray
'@  -replace "VALUE_BIN_PATH", $cmakeBinPath `
    -replace "VALUE_ROOT_PATH", $cmakeInstallDir `
    -replace "VALUE_VERSION", $cmakeVersion

    $EnvContent | Out-File -FilePath $cmakeEnvScript -Encoding utf8
    Write-Host "Created: $cmakeEnvScript" -ForegroundColor Gray

    # Update Current Session
    if (Test-Path $cmakeEnvScript) { . $cmakeEnvScript } else {
        Write-Error "cmake dep install finished but $cmakeEnvScript was not created."
        return
    }
    
    # --- 10. Symlink to Global Binaries ---
    Write-Host "Creating global symlink to: $GlobalBinDir..." -ForegroundColor Cyan

    # Create Symlink
    foreach ($cmaketool in $cmaketools) {
        $source = Join-Path $cmakeBinPath $cmaketool
        $target = Join-Path $GlobalBinDir $cmaketool
        
        if (Test-Path $source) {
            if (Test-Path $target) { Remove-Item $target -Force -ErrorAction SilentlyContinue }
            try {
                New-Item -ItemType SymbolicLink -Path $target -Value $source -ErrorAction Stop | Out-Null
                Write-Host "[LINKED] $cmaketool" -ForegroundColor Gray
            } catch {
                # Fallback to hardlink if developer mode is off/insufficient permissions
                New-Item -ItemType HardLink -Path $target -Value $source | Out-Null
            }
        }
        else {
            Write-Warning "Optional tool $cmaketool not found in $cmakeBinPath distribution; skipping symlink."
        }
    }
    
    Write-Host "[LINKED] Cmake is now globally available via %BINARIES_PATH%" -ForegroundColor Green
    
    Write-Host "CMake Version: $(& $cmakeExePath --version | Select-Object -First 1)" -ForegroundColor Gray
    
    if ($withMachineEnvironment)
    {
        $cmakeMachineEnvScript = Join-Path $EnvironmentDir "machine-env-cmake.ps1"

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
} else {
    Write-Error "cmake.exe was not found in the $cmakeBinPath folder."
    return
}
