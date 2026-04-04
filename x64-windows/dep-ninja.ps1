# Copyright 2026 (C) Navegos. DevelVitorF. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
# file:x64-windows/dep-ninja.ps1

param (
    [Parameter(HelpMessage="Path for ninja storage", Mandatory=$false)]
    [string]$ninjaInstallDir = "$env:LIBRARIES_PATH\ninja",

    [Parameter(HelpMessage = "Force a full uninstallation of the local Ninja version before continuing", Mandatory = $false)]
    [switch]$forceCleanup,
    
    [Parameter(HelpMessage = "Add's Ninja Machine Environment Variables. Requires Machine Administrator Rights.", Mandatory = $false)]
    [switch]$withMachineEnvironment
)

if ([string]::IsNullOrWhitespace($env:ENVIRONMENT_PATH) -or -not (Test-Path $env:ENVIRONMENT_PATH) -or [string]::IsNullOrWhitespace($env:BINARIES_PATH) -or -not (Test-Path $env:BINARIES_PATH) -or [string]::IsNullOrWhitespace($env:LIBRARIES_PATH) -or -not (Test-Path $env:LIBRARIES_PATH)) {
    Write-Error "User Environment variables missing. With administrator privileges run adduserpaths.ps1 -LibrariesDir 'Path\for\Libraries' -BinariesDir 'Path\for\Binaries' -EnvironmentDir 'Path\for\Environment'"
    return
}

$EnvironmentDir = "$env:ENVIRONMENT_PATH"

# if Symlink present delete
$GlobalBinDir = "$env:BINARIES_PATH"
$TargetLink = Join-Path $GlobalBinDir "ninja.exe"
# Remove existing symlink we are creating a new one
if (Test-Path $TargetLink) { Remove-Item $TargetLink -Force -ErrorAction SilentlyContinue }
$ninjaBinPath = Join-Path $ninjaInstallDir "bin"
$ninjaExePath = Join-Path $ninjaInstallDir "ninja.exe"
if (-not (Test-Path $ninjaExePath)) { $ninjaExePath = Join-Path $ninjaBinPath "ninja.exe" }
$versionFile = Join-Path $ninjaInstallDir "version.json"

# Version Detection
$repo = "ninja-build/ninja"
try {
    $latestRelease = Invoke-RestMethod -Uri "https://api.github.com/repos/$repo/releases/latest"
    $url = $latestRelease.url
    $tag_name = $latestRelease.tag_name
    $updated_at = $latestRelease.updated_at
    $remoteVersionString = $tag_name.TrimStart('v')
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
function Invoke-NinjaVersionPurge {
    param ([string]$InstallPath)
    Write-Host "--- Initiating Ninja Purge ---" -ForegroundColor Cyan

    if ($withMachineEnvironment)
    {
        $ninjaCleanMachineEnvScript = Join-Path $env:TEMP "clean-machine-env-ninja.ps1"

        # Generating Clean Machine Environment wich removes the persist registry machine Environment
        $CleanMachineEnvContent = @'
# Nnija Clean Machine Environment Setup

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

    # 2. Filesystem Nuke (Requires checking for locked files)
    if (Test-Path $InstallPath) {
        Write-Host "  [DELETING] $InstallPath" -ForegroundColor Yellow
        Remove-Item $InstallPath -Recurse -Force -ErrorAction SilentlyContinue
    }

    Write-Host "--- Ninja Purge Complete ---" -ForegroundColor Green
}

$localVersion = "0.0.0"
$rawVersion = "0.0.0"
if (Test-Path $ninjaExePath) {
    $rawVersion = (& $ninjaExePath --version).Trim()
    if ($rawVersion -match '^(\d+\.\d+\.\d+)') { $localVersion = $Matches[1] }
}

if (Test-Path $versionFile) {
    $localVersion = (Get-Content $versionFile | ConvertFrom-Json).version
}

if ($forceCleanup) {
    Invoke-NinjaVersionPurge -InstallPath $ninjaInstallDir
    # Reset trackers to force a fresh install
    $localVersion = "0.0.0"
}

# --- 2. Install or Skip ---
$vLocal  = [version]$localVersion
$vRemote = [version]$remoteVersion

if ($vLocal -ge $vRemote -and $localVersion -ne "0.0.0") {
    Write-Host "[SKIP] Ninja $localVersion is already installed and up to date at: $ninjaExePath" -ForegroundColor Green
    Write-Host "Ninja Version: $(& $ninjaExePath --version)" -ForegroundColor Gray

    # 1. Locate the bin folder and the root folder
    $ninjaVersion = $localVersion
    $ninjaBinPath = Split-Path -Path $ninjaExePath -Parent
    $ninjaInstallDir = Split-Path -Path $ninjaBinPath -Parent

    if (-not (Test-Path $versionFile)){
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
    if (Test-Path $ninjaInstallDir) {
        Write-Host "[CLEANUP] Removing existing Ninja installation at $ninjaInstallDir..." -ForegroundColor Yellow
        # We remove the content and the folder to ensure a completely fresh folder entry
        Remove-Item -Path $ninjaInstallDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    # Create a brand new, empty directory
    Write-Host "[INSTALL] Creating fresh directory: $ninjaInstallDir" -ForegroundColor Cyan
    New-Item -Path $ninjaInstallDir -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null

    # 4. Get latest release from GitHub
    try {
        $asset = $latestRelease.assets | Where-Object { $_.name -match "win\.zip$" } | Select-Object -First 1
        $zipFile = Join-Path $env:TEMP $asset.name

        Write-Host "Downloading $($asset.name)..." -ForegroundColor Cyan
        Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $zipFile

        # 5. Extract and Refine Location
        Write-Host "Extracting to temporary location..." -ForegroundColor Cyan
        $tempExtractPath = Join-Path $env:TEMP "ninja_extract_$(Get-Random)"
        Expand-Archive -Path $zipFile -DestinationPath $tempExtractPath -Force
        
        # Ensure the \bin folder exists in the final destination
        if (!(Test-Path $ninjaBinPath)) { New-Item -ItemType Directory -Path $ninjaBinPath -Force -ErrorAction SilentlyContinue | Out-Null }

        $ninjaExePath = Join-Path $ninjaBinPath "ninja.exe"

        # Find ninja.exe anywhere in the zip and move it to \bin
        $ninjaExe = Get-ChildItem -Path $tempExtractPath -Filter "ninja.exe" -Recurse | Select-Object -First 1
        if ($ninjaExe) {
            Move-Item -Path $ninjaExe.FullName -Destination $ninjaExePath -Force -ErrorAction SilentlyContinue
            Write-Host "Placed ninja.exe in: $ninjaBinPath" -ForegroundColor Gray
        }
        
        $ninjaVersion = $remoteVersion
        if (Test-Path $ninjaExePath) {
            $rawVersion = (& $ninjaExePath --version).Trim()
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
        
        Write-Host "ninja $remoteVersion Installation Complete!" -ForegroundColor DarkGreen
    }
    catch {
        Write-Error "Failed to install Ninja: $($_.Exception.Message)"
        return # Stop execution on failure
    }
}

# Finalize Environment Helper
if (Test-Path $ninjaExePath) {
    # Create Environment Helper
    Write-Host "Generating environment helper script..." -ForegroundColor Cyan
    $ninjaEnvScript = Join-Path $EnvironmentDir "env-ninja.ps1"
    
    # Generate Environment Helper with Clean Paths
    $ninjaBinPath = $ninjaBinPath.TrimEnd('\')
    $ninjaInstallDir = $ninjaInstallDir.TrimEnd('\')

    # Using a literal here-string with -replace to avoid accidental expansion of $env:PATH during creation
    $EnvContent = @'
# NINJA Environment Setup
$ninjaroot = "VALUE_ROOT_PATH"
$ninjabin = "VALUE_BIN_PATH"
$ninjaversion = "VALUE_VERSION"
$env:NINJA_PATH = $ninjaroot
$env:NINJA_ROOT = $ninjaroot
$env:NINJA_BIN = $ninjabin
if ($env:PATH -notlike "*$ninjabin*") { $env:PATH = $ninjabin + ";" + $env:PATH }
Write-Host "Ninja Environment Loaded (Version: $ninjaversion) (Bin: $ninjabin)" -ForegroundColor Green
Write-Host "NINJA_ROOT: $env:NINJA_ROOT" -ForegroundColor Gray
'@  -replace "VALUE_BIN_PATH", $ninjaBinPath `
    -replace "VALUE_ROOT_PATH", $ninjaInstallDir `
    -replace "VALUE_VERSION", $ninjaVersion

    $EnvContent | Out-File -FilePath $ninjaEnvScript -Encoding utf8
    Write-Host "Created: $ninjaEnvScript" -ForegroundColor Gray
    
    # Update Current Session
    if (Test-Path $ninjaEnvScript) { . $ninjaEnvScript } else {
        Write-Error "ninja dep install finished but $ninjaEnvScript was not created."
        return
    }
    
    # --- 10. Symlink to Global Binaries ---
    Write-Host "Creating global symlink to: $GlobalBinDir..." -ForegroundColor Cyan

    # Remove existing symlink we are creating a new one
    if (Test-Path $TargetLink) { Remove-Item $TargetLink -Force -ErrorAction SilentlyContinue }

    # Create the Symbolic Link
    try {
        New-Item -ItemType SymbolicLink -Path $TargetLink -Value $ninjaExePath -ErrorAction Stop | Out-Null
        Write-Host "[LINKED] Ninja (Global) -> $ninjaExePath" -ForegroundColor Gray
    } catch {
        New-Item -ItemType HardLink -Path $TargetLink -Value $ninjaExePath | Out-Null
    }

    Write-Host "[LINKED] Ninja is now globally available via %BINARIES_PATH%" -ForegroundColor Green

    Write-Host "Ninja Version: $(& $ninjaExePath --version)" -ForegroundColor Gray
    
    if ($withMachineEnvironment)
    {
        $ninjaMachineEnvScript = Join-Path $EnvironmentDir "machine-env-ninja.ps1"

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

        $MachineEnvContent | Out-File -FilePath $ninjaMachineEnvScript -Encoding utf8
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
} else {
    Write-Error "ninja.exe was not found in the $ninjaBinPath folder."
    return
}
