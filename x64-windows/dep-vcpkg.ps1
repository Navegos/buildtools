# SPDX-FileCopyrightText: Copyright (c) 2026 Navegos. @DevelVitorF. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
# project: buildtools
# file: x64-windows/dep-vcpkg.ps1
# created: 2026-03-08
# lastModified: 2026-04-26

param (
    [Parameter(HelpMessage = "Path for vcpkg storage", Mandatory = $false)]
    [string]$vcpkgInstallDir = "$env:LIBRARIES_PATH\vcpkg",
    
    [Parameter(HelpMessage = "Force a full purge of the local vcpkg version before continuing", Mandatory = $false)]
    [switch]$forceCleanup,
    
    [Parameter(HelpMessage = "Add's vcpkg Machine Environment Variables. Requires Machine Administrator Rights.", Mandatory = $false)]
    [switch]$withMachineEnvironment
)

# Capture parameters
$vcpkgWithMachineEnvironment = $withMachineEnvironment
$vcpkgForceCleanup = $forceCleanup

# 1. Bootstrap Environment if variables are missing
if ([string]::IsNullOrWhitespace($env:ENVIRONMENT_PATH) -or -not (Test-Path $env:ENVIRONMENT_PATH) -or [string]::IsNullOrWhitespace($env:BINARIES_PATH) -or -not (Test-Path $env:BINARIES_PATH) -or [string]::IsNullOrWhitespace($env:LIBRARIES_PATH) -or -not (Test-Path $env:LIBRARIES_PATH)) {
    Write-Error "User Environment variables missing. Please run adduserpaths.ps1 -LibrariesDir 'Path\for\Libraries' BinariesDir 'Path\for\Binaries' -EnvironmentDir 'Path\for\Environment'"
    return
}

$EnvironmentDir = "$env:ENVIRONMENT_PATH"

# if Symlink present delete
$GlobalBinDir = "$env:BINARIES_PATH"
$TargetLink = Join-Path $GlobalBinDir "vcpkg.exe"
# Remove existing symlink we are creating a new one
if (Test-Path $TargetLink) { Remove-Item $TargetLink -Force -ErrorAction SilentlyContinue }
$vcpkgBinPath = $vcpkgInstallDir
$vcpkgExePath = Join-Path $vcpkgBinPath "vcpkg.exe"
$versionFile = Join-Path $vcpkgInstallDir "version.json"
$vcpkgEnvScript = Join-Path $EnvironmentDir "env-vcpkg.ps1"
$vcpkgMachineEnvScript = Join-Path $EnvironmentDir "machine-env-vcpkg.ps1"

# Version Detection
$repo = "microsoft/vcpkg"
try {
    $latestRelease = Invoke-RestMethod -Uri "https://api.github.com/repos/$repo/releases/latest"
    $url = $latestRelease.url
    $tag_name = $latestRelease.tag_name
    $updated_at = $latestRelease.updated_at
    $remoteVersionString = $latestRelease.tag_name.TrimStart('v')
    $refTags = Invoke-RestMethod -Uri "https://api.github.com/repos/$repo/git/ref/tags/$tag_name"
    $tagCommit = $refTags.object.sha
    
    # Clean remote version for comparison (e.g., "1.12.1")
    if ($remoteVersionString -match '^(\d+\.\d+\.\d+)') { $remoteVersion = $Matches[1] } # "tag_name": "2026.03.18",
}
catch {
    Write-Warning "Could not connect to GitHub. Using 0.0.0 for remote."
    $url = "ERR_CONNECTION_TIMED_OUT"
    $tag_name = "0.0.0"
    $updated_at = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssZ")
    $remoteVersion = "0.0.0"
    $tagCommit = "0000000000000000000000000000000000000000"
}

# --- 1. Cleanup Mechanism ---
function Invoke-vcpkgVersionPurge {
    param ([string]$InstallPath)
    Write-Host "--- Initiating vcpkg Purge ---" -ForegroundColor Cyan

    if ($vcpkgWithMachineEnvironment)
    {
        $vcpkgCleanMachineEnvScript = Join-Path $env:TEMP "clean-machine-env-vcpkg.ps1"

        # Generating Clean Machine Environment wich removes the persist registry machine Environment
        $CleanMachineEnvContent = @'
# vcpkg Clean Machine Environment Setup

# --- 0. Self-Elevation Logic ---
$IsAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$ScopeColor = "Cyan"

if (-not $IsAdmin) {
    Write-Host "Elevation required to clean vcpkg system variables. Relaunching as Administrator..." -ForegroundColor Yellow
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

$vcpkgroot = "VALUE_ROOT_PATH"

$TargetScope = if ($IsAdmin) { "Machine" } else { "User" }
$RegPath = if ($IsAdmin) { "System\CurrentControlSet\Control\Session Manager\Environment" } else { "Environment" }
$RegRoot = if ($IsAdmin) { "LocalMachine" } else { "CurrentUser" }

# 1. Registry Cleanup (TOOLS_PATH)
$RegKey = [Microsoft.Win32.Registry]::$RegRoot.OpenSubKey($RegPath, $true)

# Open the registry key directly to read the RAW (unexpanded) string
$RawPath = $RegKey.GetValue("TOOLS_PATH", "", [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)

# Cleanup: Remove empty strings, any path containing $vcpkgroot,
$CleanPath = ($RawPath -split ';' | Where-Object { $_ -notlike "*$vcpkgroot*" }) -join ";"

# Save as ExpandString
$RegKey.SetValue("TOOLS_PATH", $CleanPath, [Microsoft.Win32.RegistryValueKind]::ExpandString)
$env:TOOLS_PATH = $CleanPath

$RegKey.Close()

Write-Host "[REMOVED] ($TargetScope) all '*$vcpkgroot*' removed from TOOLS_PATH" -ForegroundColor $ScopeColor
'@  -replace "VALUE_ROOT_PATH", $InstallPath

        $CleanMachineEnvContent | Out-File -FilePath $vcpkgCleanMachineEnvScript -Encoding utf8
        Write-Host "Created: $vcpkgCleanMachineEnvScript" -ForegroundColor Gray
        
        # --- Interaction: Prompt to remove persistent changes ---
        Write-Host ""
        $choice = Read-Host "Administrator rights required to Clean Machine Environment vcpkg changes? (y/n)"
        if ($choice -eq 'y' -or $choice -eq 'Y') {
            Write-Host "Executing $vcpkgCleanMachineEnvScript..." -ForegroundColor Yellow
            try {
                # Start the generated script. It handles its own elevation logic.
                & $vcpkgCleanMachineEnvScript
            }
            catch {
                Write-Error "Failed to execute the Clean Machine Environment script: $($_.Exception.Message)"
                return
            }
        }
        else {
            Write-Error "Skipped Clean Machine Environment vcpkg changes."
            return
        }

        # Cleanup
        Remove-Item $vcpkgCleanMachineEnvScript -Recurse -Force -ErrorAction SilentlyContinue
    }

    # 2. Filesystem Clean (Requires checking for locked files)
    # delete everithing we create don't fail later
    if (Test-Path $vcpkgEnvScript) {
        Write-Host "  [DELETING] $vcpkgEnvScript" -ForegroundColor Yellow
        Remove-Item $vcpkgEnvScript -Recurse -Force -ErrorAction SilentlyContinue
    }
    if (Test-Path $vcpkgMachineEnvScript) {
        Write-Host "  [DELETING] $vcpkgMachineEnvScript" -ForegroundColor Yellow
        Remove-Item $vcpkgMachineEnvScript -Recurse -Force -ErrorAction SilentlyContinue
    }
    if (Test-Path $InstallPath) {
        Write-Host "  [DELETING] $InstallPath" -ForegroundColor Yellow
        Remove-Item $InstallPath -Recurse -Force -ErrorAction SilentlyContinue
    }
    
    # remove local Env variables for current session
    Get-ChildItem Env:\VCPKG_PATH* | Remove-Item -ErrorAction SilentlyContinue
    Get-ChildItem Env:\VCPKG_ROOT* | Remove-Item -ErrorAction SilentlyContinue
    Get-ChildItem Env:\VCPKG_BIN* | Remove-Item -ErrorAction SilentlyContinue

    Write-Host "--- vcpkg Purge Complete ---" -ForegroundColor Green
}

$localVersion = "0.0.0"
$rawVersion = "0.0.0"
if (Test-Path $vcpkgExePath) {
    $rawVersion = (& $vcpkgExePath version | Select-Object -First 1).Trim()
    if ($rawVersion -match 'version\s+(\d{4}-\d{2}-\d{2})') { $localVersion = $Matches[1].Replace('-', '.') } # need to convert 2026-02-21 to 2026.02.21
}

if (Test-Path $versionFile) {
    $localVersion = (Get-Content $versionFile | ConvertFrom-Json).version
}

if ($vcpkgForceCleanup) {
    Invoke-vcpkgVersionPurge -InstallPath $vcpkgInstallDir
    # Reset trackers to force a fresh install
    $localVersion = "0.0.0"
}

# --- 2. Install or Skip ---
$vLocal = [version]$localVersion
$vRemote = [version]$remoteVersion

if ($vLocal -ge $vRemote -and $localVersion -ne "0.0.0") {
    Write-Host "[SKIP] vcpkg $localVersion is already installed and up to date at: $vcpkgExePath" -ForegroundColor Green
    Write-Host "vcpkg Version: $(& $vcpkgExePath version | Select-Object -First 1)" -ForegroundColor Gray

    # 1. Locate the bin folder and the root folder
    $vcpkgVersion = $localVersion
    $vcpkgBinPath = Split-Path -Path $vcpkgExePath -Parent
    $vcpkgInstallDir = Split-Path -Path $vcpkgBinPath -Parent
    
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
    Write-Host "vcpkg not found. Starting installation..." -ForegroundColor Yellow

    if (-not (Test-Path $vcpkgInstallDir)) { New-Item -Path $vcpkgInstallDir -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null }

    # 2. Get latest release from GitHub
    try {
        $zipUrl = $latestRelease.zipball_url # Download source zip
        $zipFile = Join-Path $env:TEMP "vcpkg_source.zip"

        Write-Host "Downloading vcpkg source ($($latestRelease.tag_name))..." -ForegroundColor Cyan
        Invoke-WebRequest -Uri $zipUrl -OutFile $zipFile

        # 3. Extract and Refine Location
        Write-Host "Extracting to $vcpkgInstallDir..." -ForegroundColor Cyan
        $tempExtractPath = Join-Path $env:TEMP "vcpkg_extract_$(Get-Random)"
        Expand-Archive -Path $zipFile -DestinationPath $tempExtractPath -Force
        
        # vcpkg zip contains a root folder, move its contents to final dir
        $innerFolder = Get-ChildItem -Path $tempExtractPath -Directory | Select-Object -First 1
        Copy-Item -Path "$($innerFolder.FullName)\*" -Destination $vcpkgInstallDir -Recurse -Force -ErrorAction SilentlyContinue

        # 4. Bootstrap vcpkg
        Write-Host "Bootstrapping vcpkg (compiling executable)..." -ForegroundColor Yellow
        Push-Location $vcpkgInstallDir
        try {
            # Ensure we use the bundled compiler detection
            $bootstrapResult = cmd /c ".\bootstrap-vcpkg.bat -disableMetrics" 2>&1
            if ($LASTEXITCODE -ne 0) { throw "Bootstrap failed: $bootstrapResult" }
        }
        finally {
            Pop-Location
        }
        
        $vcpkgVersion = $remoteVersion
        if (Test-Path $vcpkgExePath) {
            $rawVersion = (& $vcpkgExePath version | Select-Object -First 1).Trim()
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
    
        # Cleanup debris
        Remove-Item $zipFile -Force -ErrorAction SilentlyContinue
        Remove-Item $tempExtractPath -Recurse -Force -ErrorAction SilentlyContinue
        
        Write-Host "vcpkg Installation Complete!" -ForegroundColor DarkGreen
    }
    catch {
        Write-Error "Failed to install vcpkg: $($_.Exception.Message)"
        return # Stop execution on failure
    }
}

# Finalize Environment Helper
if (Test-Path $vcpkgExePath) {
    # Create Environment Helper
    Write-Host "Generating environment helper script..." -ForegroundColor Cyan
    
    # Generate Environment Helper with Clean Paths
    $vcpkgBinPath = $vcpkgBinPath.TrimEnd('\')
    $vcpkgInstallDir = $vcpkgInstallDir.TrimEnd('\')
    $vcpkgExePath = Join-Path $vcpkgBinPath "vcpkg.exe"

    # Using a literal here-string with -replace to avoid accidental expansion of $env:PATH during creation
    $EnvContent = @'
# VCPKG Environment Setup
$vcpkgroot = "VALUE_ROOT_PATH"
$vcpkgbin = "VALUE_BIN_PATH"
$vcpkgexe = "VALUE_EXE_PATH"
$vcpkgversion = "VALUE_VERSION"
$env:VCPKG_PATH = $vcpkgroot
$env:VCPKG_ROOT = $vcpkgroot
$env:VCPKG_BIN = $vcpkgbin
$env:BINARY_VCPKG = $vcpkgexe
if ($env:PATH -notlike "*$vcpkgbin*") { $env:PATH = $vcpkgbin + ";" + $env:PATH; $env:PATH = ($env:PATH).Replace(";;", ";") }
Write-Host "vcpkg Environment Loaded (Version: $vcpkgversion) (Bin: $vcpkgbin)" -ForegroundColor Green
Write-Host "VCPKG_ROOT: $env:VCPKG_ROOT" -ForegroundColor Gray
'@  -replace "VALUE_BIN_PATH", $vcpkgBinPath `
    -replace "VALUE_EXE_PATH", $vcpkgExePath `
    -replace "VALUE_ROOT_PATH", $vcpkgInstallDir `
    -replace "VALUE_VERSION", $vcpkgVersion

    $EnvContent | Out-File -FilePath $vcpkgEnvScript -Encoding utf8
    Write-Host "Created: $vcpkgEnvScript" -ForegroundColor Gray
    
    # Update Current Session
    if (Test-Path $vcpkgEnvScript) { . $vcpkgEnvScript } else {
        Write-Error "vcpkg dep install finished but $vcpkgEnvScript was not created."
        return
    }
    
    # --- 10. Symlink to Global Binaries ---
    Write-Host "Creating global symlink to: $GlobalBinDir..." -ForegroundColor Cyan

    # Remove existing symlink we are creating a new one
    if (Test-Path $TargetLink) { Remove-Item $TargetLink -Force -ErrorAction SilentlyContinue }

    # Create the Symbolic Link
    try {
        New-Item -Path $TargetLink -ItemType SymbolicLink -Value $vcpkgExePath -ErrorAction Stop | Out-Null
        Write-Host "[LINKED] vcpkg (Global) -> $vcpkgExePath" -ForegroundColor Gray
    }
    catch {
        New-Item -Path $TargetLink -ItemType HardLink -Value $vcpkgExePath | Out-Null
    }

    Write-Host "[LINKED] vcpkg is now globally available via %BINARIES_PATH%" -ForegroundColor Green
    
    Write-Host "vcpkg Version: $(& $vcpkgExePath version | Select-Object -First 1)" -ForegroundColor Gray
    
    if ($vcpkgWithMachineEnvironment)
    {
        # Generating Machine Environment wich add to the persist registry machine Environment
        $MachineEnvContent = @'
# vcpkg Machine Environment Setup

# --- 0. Self-Elevation Logic ---
$IsAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$ScopeColor = "Cyan"

if (-not $IsAdmin) {
    Write-Host "Elevation required to set vcpkg system variables. Relaunching as Administrator..." -ForegroundColor Yellow
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

$vcpkgroot = "VALUE_ROOT_PATH"
$vcpkgbin = "VALUE_BIN_PATH"
$vcpkgversion = "VALUE_VERSION"

$TargetScope = if ($IsAdmin) { "Machine" } else { "User" }
$RegPath = if ($IsAdmin) { "System\CurrentControlSet\Control\Session Manager\Environment" } else { "Environment" }
$RegRoot = if ($IsAdmin) { "LocalMachine" } else { "CurrentUser" }

# Open the registry key once
$RegKey = [Microsoft.Win32.Registry]::$RegRoot.OpenSubKey($RegPath, $true)

# Open the registry key directly to read the RAW (unexpanded) string
$CurrentRawPath = $RegKey.GetValue("TOOLS_PATH", "", [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)

# Cleanup: Remove empty strings, any path containing $vcpkgroot, and the current target (to avoid dups)
$CleanedPathList = $CurrentRawPath -split ';' | Where-Object { 
    -not [string]::IsNullOrWhitespace($_) -and 
    $_ -notlike "*$vcpkgroot*"
}

$NewRawPath = ($CleanedPathList -join ";").Replace(";;", ";")

$TargetPath = $vcpkgbin

# Rebuild
$NewRawPath = ($NewRawPath + ";" + $TargetPath + ";").Replace(";;", ";")
Write-Host "[UPDATED] ($TargetScope) '$vcpkgbin' synced in TOOLS_PATH" -ForegroundColor $ScopeColor

# Save as ExpandString
$RegKey.SetValue("TOOLS_PATH", $NewRawPath, [Microsoft.Win32.RegistryValueKind]::ExpandString)
$env:TOOLS_PATH = $NewRawPath

$RegKey.Close()

$env:VCPKG_ROOT = $vcpkgroot
Write-Host "vcpkg Environment Loaded (Version: $vcpkgversion) (Bin: $vcpkgbin)" -ForegroundColor Green
Write-Host "VCPKG_ROOT: $env:VCPKG_ROOT" -ForegroundColor Gray
'@  -replace "VALUE_ROOT_PATH", $vcpkgInstallDir `
    -replace "VALUE_BIN_PATH", $vcpkgBinPath `
    -replace "VALUE_VERSION", $vcpkgVersion

        $MachineEnvContent | Out-File -FilePath $vcpkgMachineEnvScript -Encoding utf8
        Write-Host "Created: $vcpkgMachineEnvScript" -ForegroundColor Gray
        
        # --- Interaction: Prompt to apply persistent changes ---
        Write-Host ""
        $choice = Read-Host "Do you want to run the Machine Environment script now to persist vcpkg changes to the Registry? (y/n)"
        if ($choice -eq 'y' -or $choice -eq 'Y') {
            Write-Host "Executing $vcpkgMachineEnvScript..." -ForegroundColor Yellow
            try {
                # Start the generated script. It handles its own elevation logic.
                & $vcpkgMachineEnvScript
            }
            catch {
                Write-Error "Failed to execute the Machine Environment script: $($_.Exception.Message)"
            }
        }
        else {
            Write-Host "Skipped persistent registry update. You can run it later at: $vcpkgMachineEnvScript" -ForegroundColor Gray
        }
    }
} else {
    Write-Error "vcpkg.exe was not found in the $vcpkgBinPath folder."
    return
}
