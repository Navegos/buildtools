# Copyright 2026 (C) Navegos. DevelVitorF. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
# file:x64-windows/dep-icu.ps1

param (
    [Parameter(HelpMessage="Target vcpkg ICU triplet")]
    [string]$Triplet = "x64-windows",
    
    [Parameter(HelpMessage = "Force a full uninstallation of the local ICU version before continuing", Mandatory = $false)]
    [switch]$forceCleanup,
    
    [Parameter(HelpMessage = "Add's ICU Machine Environment Variables. Requires Machine Administrator Rights.", Mandatory = $false)]
    [switch]$withMachineEnvironment
)

# 1. Bootstrap Environment if variables are missing
if ([string]::IsNullOrWhitespace($env:ENVIRONMENT_PATH) -or -not (Test-Path $env:ENVIRONMENT_PATH) -or [string]::IsNullOrWhitespace($env:BINARIES_PATH) -or -not (Test-Path $env:BINARIES_PATH) -or [string]::IsNullOrWhitespace($env:LIBRARIES_PATH) -or -not (Test-Path $env:LIBRARIES_PATH)) {
    Write-Error "User Environment variables missing. Please run adduserpaths.ps1 -LibrariesDir 'Path\for\Libraries' BinariesDir 'Path\for\Binaries' -EnvironmentDir 'Path\for\Environment'"
    return
}

$EnvironmentDir = "$env:ENVIRONMENT_PATH"

# --- 1. Initialize Visual Studio 2026 Dev Environment dependencie requirement ---
$DevShellBootstrapScript = Join-Path $PSScriptRoot "dev-shell.ps1"
if (Test-Path $DevShellBootstrapScript) { . $DevShellBootstrapScript } else {
    Write-Error "Required dependency '$DevShellBootstrapScript' not found!"
    return
}

# --- 2. Initialize vcpkg environment if missing ---
if (!$env:VCPKG_PATH) {
    $vcpkgEnvScript = Join-Path $EnvironmentDir "env-vcpkg.ps1"
    if (Test-Path $vcpkgEnvScript) { . $vcpkgEnvScript } else {
        $depvcpkgEnvScript = Join-Path $PSScriptRoot "dep-vcpkg.ps1"
        if (Test-Path $depvcpkgEnvScript) { . $depvcpkgEnvScript }
        else {
            Write-Error "CRITICAL: Cannot load vcpkg environment. vcpkg is missing and $depvcpkgEnvScript was not found."
            return
        }
    }
}

$vcpkgRoot = "$env:VCPKG_PATH"

if ([string]::IsNullOrWhitespace($vcpkgRoot)) {
    Write-Error "VCPKG_PATH is still missing. Please run dep-vcpkg.ps1 first."
    return
}

# --- 3. Resolve Paths ---
$installBase = Join-Path $vcpkgRoot "installed\$Triplet"
$icuInstallDir = $installBase
$icuIncludeDir = Join-Path $icuInstallDir "include"
$icuBinPath = Join-Path $icuInstallDir "bin"
$icuToolsPath = Join-Path $icuInstallDir "tools\icu"
$icuToolsBinPath = Join-Path $icuToolsPath "bin"
$icuLibDir = Join-Path $icuInstallDir "lib"
$versionFile = Join-Path $icuToolsPath "version.json"

# Version Detection
$repo = "microsoft/vcpkg"
$filePath = "ports/icu/vcpkg.json"
$branch = "master"
$rawJsonUrl = "https://raw.githubusercontent.com/$repo/$branch/$filePath"
$apiUrl = "https://api.github.com/repos/$repo/commits?path=$filePath&sha=$branch&per_page=1"
$remoteVersion = "0.0.0"
try {
    Write-Host "Fetching latest ICU version from vcpkg master..." -ForegroundColor Gray
    $icuManifest = Invoke-RestMethod -Uri $rawJsonUrl
    $url = $rawJsonUrl
    $tag_name = $icuManifest.version
    $updated_at = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssZ")
    $remoteVersionString = $icuManifest.version.TrimStart('v')
    
    # Clean remote version for comparison (e.g., "1.12.1")
    if ($remoteVersionString -match '^(\d+\.\d+(\.\d+)?)') { $remoteVersion = $Matches[1] }

    try {
        # Fetch the commit history for this specific file
        $commits = Invoke-RestMethod -Uri $apiUrl -Method Get
        
        if ($commits.Count -gt 0) {
            $tagCommit = $commits[0].sha
            $updated_at = $commits[0].commit.committer.date
            Write-Host "[REMOTE] Latest SHA for icu/vcpkg.json: $tagCommit" -ForegroundColor Cyan
        }
        else {
            throw "No commits found for $filePath"
        }
    }
    catch {
        Write-Warning "Failed to fetch commit SHA: $($_.Exception.Message)"
        $tagCommit = "0000000000000000000000000000000000000000"
    }
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
function Invoke-icuVersionPurge {
    param ([string]$InstallPath)
    Write-Host "--- Initiating ICU Purge ---" -ForegroundColor Cyan

    $icuBinInstallPath = Join-Path $InstallPath "bin"
    $icuToolsBinInstallPath = Join-Path $InstallPath "tools\icu\bin"

    if ($withMachineEnvironment)
    {
        $icuCleanMachineEnvScript = Join-Path $env:TEMP "clean-machine-env-icu.ps1"

        # Generating Clean Machine Environment wich removes the persist registry machine Environment
        $CleanMachineEnvContent = @'
# icu Clean Machine Environment Setup

# --- 0. Self-Elevation Logic ---
$IsAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$ScopeColor = "Cyan"

if (-not $IsAdmin) {
    Write-Host "Elevation required to clean icu system variables. Relaunching as Administrator..." -ForegroundColor Yellow
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

$icubinpath = "VALUE_ICU_BIN_PATH"
$icutoolsbinpath = "VALUE_ICU_TOOLS_BIN_PATH"

$TargetScope = if ($IsAdmin) { "Machine" } else { "User" }
$RegPath = if ($IsAdmin) { "System\CurrentControlSet\Control\Session Manager\Environment" } else { "Environment" }
$RegRoot = if ($IsAdmin) { "LocalMachine" } else { "CurrentUser" }

# 1. Registry Cleanup (EXTCOMP_PATH)
$RegKey = [Microsoft.Win32.Registry]::$RegRoot.OpenSubKey($RegPath, $true)

# Open the registry key directly to read the RAW (unexpanded) string
$RawPath = $RegKey.GetValue("EXTCOMP_PATH", "", [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
$RawLibPath = $RegKey.GetValue("EXTCOMPLIBS_PATH", "", [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)

# Cleanup: Remove empty strings, any path containing $icutoolsbinpath,
$CleanPath = ($RawPath -split ';' | Where-Object { $_ -notlike "*$icutoolsbinpath*" }) -join ";"
$CleanLibPath = ($RawLibPath -split ';' | Where-Object { $_ -notlike "*$icubinpath*" }) -join ";"

# Save as ExpandString
$RegKey.SetValue("EXTCOMP_PATH", $CleanPath, [Microsoft.Win32.RegistryValueKind]::ExpandString)
$RegKey.SetValue("EXTCOMPLIBS_PATH", $CleanLibPath, [Microsoft.Win32.RegistryValueKind]::ExpandString)
$env:EXTCOMP_PATH = $CleanPath
$env:EXTCOMPLIBS_PATH = $CleanLibPath

$RegKey.Close()

Write-Host "[REMOVED] ($TargetScope) all '*$icutoolsbinpath*' removed from EXTCOMP_PATH" -ForegroundColor $ScopeColor
'@  -replace "VALUE_ICU_TOOLS_BIN_PATH", $icuToolsBinInstallPath -replace "VALUE_ICU_BIN_PATH", $icuBinInstallPath

        $CleanMachineEnvContent | Out-File -FilePath $icuCleanMachineEnvScript -Encoding utf8
        Write-Host "Created: $icuCleanMachineEnvScript" -ForegroundColor Gray
        
        # --- Interaction: Prompt to remove persistent changes ---
        Write-Host ""
        $choice = Read-Host "Administrator rights required to Clean Machine Environment icu changes? (y/n)"
        if ($choice -eq 'y' -or $choice -eq 'Y') {
            Write-Host "Executing $icuCleanMachineEnvScript..." -ForegroundColor Yellow
            try {
                # Start the generated script. It handles its own elevation logic.
                & $icuCleanMachineEnvScript
            }
            catch {
                Write-Error "Failed to execute the Clean Machine Environment script: $($_.Exception.Message)"
                return
            }
        }
        else {
            Write-Error "Skipped Clean Machine Environment icu changes."
            return
        }

        # Cleanup
        Remove-Item $icuCleanMachineEnvScript -Recurse -Force -ErrorAction SilentlyContinue
    }
    
    # --- 1. Remove ICU via vcpkg ---
    # Note: 'icu' is the meta-package in vcpkg
    Write-Host "Removing ICU:$Triplet via vcpkg..." -ForegroundColor Cyan
    Push-Location $vcpkgRoot
    cmd /c "vcpkg remove --recurse icu:$Triplet"
    if ($LASTEXITCODE -ne 0) {
        Write-Error "vcpkg failed to remove ICU."
        Pop-Location; return
    }
    Pop-Location
    
    Write-Host "--- ICU Purge Complete ---" -ForegroundColor Green
}

# Fix this using vcpkg to get ICU version
$localVersion = "0.0.0"
$rawVersion = "0.0.0"
if (Test-Path (Join-Path $icuLibDir "icuuc.lib")) {
    $rawVersion = (vcpkg list icu:$Triplet | Select-Object -First 1).Trim()
    if ($rawVersion -match '^(\d+\.\d+(\.\d+)?)') { $localVersion = $Matches[1] }
}

if (Test-Path $versionFile) {
    $localVersion = (Get-Content $versionFile | ConvertFrom-Json).version
}

if ($forceCleanup) {
    Invoke-icuVersionPurge -InstallPath $icuInstallDir
    # Reset trackers to force a fresh install
    $localVersion = "0.0.0"
}

# --- 2. Install or Skip ---
# Refined casting logic
$vLocal = [version]"0.0.0"
$vRemote = [version]"0.0.0"

if ($localVersion -match '^(\d+\.\d+(\.\d+)?)') { $vLocal = [version]($localVersion -replace '#.*', '') }
if ($remoteVersion -match '^(\d+\.\d+(\.\d+)?)') { $vRemote = [version]($remoteVersion -replace '#.*', '') }

if ($vLocal -ge $vRemote -and $localVersion -ne "0.0.0") {
    Write-Host "[SKIP] ICU $localVersion is already installed and up to date at: $icuInstallDir" -ForegroundColor Green
    Write-Host "ICU Version: $(vcpkg list icu:$Triplet | Select-Object -First 1)" -ForegroundColor Gray

    # 1. Locate the bin folder and the root folder
    $icuVersion = $localVersion
    if (-not (Test-Path $versionFile)) {
        $versionInfo = @{
            url        = $url;
            tag_name   = $tag_name;
            commit     = $tagCommit;
            version    = $localVersion;
            rawversion = $rawVersion;
            date       = (Get-Date).ToString("yyyy-MM-dd");
            updated_at = $updated_at;
            type       = "build_tool";
        }
        $versionInfo | ConvertTo-Json | Out-File -FilePath $versionFile -Encoding utf8 -Force
    }
} else {
    # --- 1. Install ICU via vcpkg ---
    # Note: 'icu' is the meta-package in vcpkg
    Write-Host "Installing icu:$Triplet via vcpkg..." -ForegroundColor Cyan
    Push-Location $vcpkgRoot
    # We use --recurse to handle dependencies like 'icu-data'
    cmd /c "vcpkg install --recurse icu:$Triplet"
    if ($LASTEXITCODE -ne 0) {
        Write-Error "vcpkg failed to install ICU."
        Pop-Location; return
    }
    Pop-Location

    $icuVersion = $remoteVersion
    if (Test-Path (Join-Path $icuLibDir "icuuc.lib")) {
        $rawVersion = (vcpkg list icu:$Triplet | Select-Object -First 1).Trim()
    }
    $versionInfo = @{
        url        = $url;
        tag_name   = $tag_name;
        commit     = $tagCommit;
        version    = $remoteVersion;
        rawversion = $rawVersion;
        date       = (Get-Date).ToString("yyyy-MM-dd");
        updated_at = $updated_at;
        type       = "build_tool";
    }
    $versionInfo | ConvertTo-Json | Out-File -FilePath $versionFile -Encoding utf8 -Force
}

# Finalize Environment Helper
# ICU typically produces icuuc.lib (Common), icuin.lib (I18N), etc.
if (Test-Path (Join-Path $icuLibDir "icuuc.lib")) {
    # Generate Environment Helper with Clean Paths
    $icuInstallDir = $icuInstallDir.TrimEnd('\')
    $icuIncludeDir = $icuIncludeDir.TrimEnd('\')
    $icuLibDir     = $icuLibDir.TrimEnd('\')
    $icuBinPath    = $icuBinPath.TrimEnd('\')
    $icuToolsBinPath = $icuToolsBinPath.TrimEnd('\')
    $icuCMakePath  = $icuInstallDir.Replace('\', '/')
    
    # --- 3. Create Environment Helper ---
    Write-Host "Generating environment helper script..." -ForegroundColor Cyan
    $icuEnvScript = Join-Path $EnvironmentDir "env-icu.ps1"

    # Using a literal here-string with -replace to avoid accidental expansion of $env:PATH during creation
    $EnvContent = @'
# ICU Environment Setup
$icuroot = "VALUE_ROOT_PATH"
$icuinclude = "VALUE_INCLUDE_PATH"
$iculibrary = "VALUE_LIB_PATH"
$icubin = "VALUE_BIN_PATH"
$icutoolsbin = "VALUE_TOOLS_BIN_PATH"
$icucmakepath = "VALUE_CMAKE_PATH"
$icuversion = "VALUE_VERSION"
$env:ICU_PATH = $icuroot
$env:ICU_ROOT = $icuroot
$env:ICU_BIN = $icubin
$env:ICU_TOOLS_BIN = $icutoolsbin
$env:ICU_INCLUDEDIR = $icuinclude
$env:ICU_LIBRARYDIR = $iculibrary
if ($env:CMAKE_PREFIX_PATH -notlike "*$icucmakepath*") { $env:CMAKE_PREFIX_PATH = $icucmakepath + ";" + $env:CMAKE_PREFIX_PATH }
if ($env:INCLUDE -notlike "*$icuinclude*") { $env:INCLUDE = $icuinclude + ";" + $env:INCLUDE }
if ($env:LIB -notlike "*$iculibrary*") { $env:LIB = $iculibrary + ";" + $env:LIB }
"$icubin", "$icutoolsbin" | ForEach-Object { if ($env:PATH -notlike "*$_*") { $env:PATH = $_ + ";" + $env:PATH } }
Write-Host "ICU Environment Loaded (Version: $icuversion) (Bin: $icubin)" -ForegroundColor Green
Write-Host "ICU_ROOT: $env:ICU_ROOT" -ForegroundColor Gray
'@  -replace "VALUE_ROOT_PATH", $icuInstallDir `
    -replace "VALUE_INCLUDE_PATH", $icuIncludeDir `
    -replace "VALUE_LIB_PATH", $icuLibDir `
    -replace "VALUE_BIN_PATH", $icuBinPath `
    -replace "VALUE_TOOLS_BIN_PATH", $icuToolsBinPath `
    -replace "VALUE_CMAKE_PATH", $icuCMakePath `
    -replace "VALUE_VERSION", $icuVersion

    $EnvContent | Out-File -FilePath $icuEnvScript -Encoding utf8
    Write-Host "Created: $icuEnvScript" -ForegroundColor Gray
    
    # Update Current Session
    if (Test-Path $icuEnvScript) { . $icuEnvScript } else {
        Write-Error "icu dep install finished but $icuEnvScript was not created."
        return
    }
    Write-Host "icu Version: $(vcpkg list icu:$Triplet | Select-Object -First 1)" -ForegroundColor Gray
    
    if ($withMachineEnvironment)
    {
        $icuMachineEnvScript = Join-Path $EnvironmentDir "machine-env-icu.ps1"

        # Generating Machine Environment wich add to the persist registry machine Environment
        $MachineEnvContent = @'
# ICU Machine Environment Setup

# --- 0. Self-Elevation Logic ---
$IsAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$ScopeColor = "Cyan"

if (-not $IsAdmin) {
    Write-Host "Elevation required to set ICU system variables. Relaunching as Administrator..." -ForegroundColor Yellow
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

$icuroot = "VALUE_ROOT_PATH"
$icubin = "VALUE_BIN_PATH"
$icutoolsbin = "VALUE_TOOLS_BIN_PATH"
$icuversion = "VALUE_VERSION"

$TargetScope = if ($IsAdmin) { "Machine" } else { "User" }
$RegPath = if ($IsAdmin) { "System\CurrentControlSet\Control\Session Manager\Environment" } else { "Environment" }
$RegRoot = if ($IsAdmin) { "LocalMachine" } else { "CurrentUser" }

# Open the registry key once
$RegKey = [Microsoft.Win32.Registry]::$RegRoot.OpenSubKey($RegPath, $true)

# Open the registry key directly to read the RAW (unexpanded) string
$CurrentRawPath = $RegKey.GetValue("EXTCOMP_PATH", "", [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
$CurrentRawLibPath = $RegKey.GetValue("EXTCOMPLIBS_PATH", "", [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)

# Cleanup: Remove empty strings, any path containing $icuroot, and the current target (to avoid dups)
$CleanedPathList = $CurrentRawPath -split ';' | Where-Object { 
    -not [string]::IsNullOrWhitespace($_) -and 
    $_ -notlike "*$icutoolsbin*"
}
$CleanedPathLibList = $CurrentRawLibPath -split ';' | Where-Object { 
    -not [string]::IsNullOrWhitespace($_) -and 
    $_ -notlike "*$icubin*"
}

$NewRawPath = ($CleanedPathList -join ";").Replace(";;", ";")
$NewRawLibPath = ($CleanedPathLibList -join ";").Replace(";;", ";")

$TargetPath = $icutoolsbin
$TargetLibPath = $icubin

# Rebuild
$NewRawPath = ($NewRawPath + ";" + $TargetPath + ";").Replace(";;", ";")
$NewRawLibPath = ($NewRawLibPath + ";" + $TargetLibPath + ";").Replace(";;", ";")
Write-Host "[UPDATED] ($TargetScope) '$icutoolsbin' synced in EXTCOMP_PATH" -ForegroundColor $ScopeColor

# Save as ExpandString
$RegKey.SetValue("EXTCOMP_PATH", $NewRawPath, [Microsoft.Win32.RegistryValueKind]::ExpandString)
$RegKey.SetValue("EXTCOMPLIBS_PATH", $NewRawLibPath, [Microsoft.Win32.RegistryValueKind]::ExpandString)
$env:EXTCOMP_PATH = $NewRawPath
$env:EXTCOMPLIBS_PATH = $NewRawLibPath

$RegKey.Close()

$env:ICU_ROOT = $icuroot
Write-Host "icu Environment Loaded (Version: $icuversion) (Bin: $icutoolsbin)" -ForegroundColor Green
Write-Host "ICU_ROOT: $env:ICU_ROOT" -ForegroundColor Gray
'@  -replace "VALUE_ROOT_PATH", $icuInstallDir `
    -replace "VALUE_BIN_PATH", $icuBinPath `
    -replace "VALUE_TOOLS_BIN_PATH", $icuToolsBinPath `
    -replace "VALUE_VERSION", $icuVersion

        $MachineEnvContent | Out-File -FilePath $icuMachineEnvScript -Encoding utf8
        Write-Host "Created: $icuMachineEnvScript" -ForegroundColor Gray
        
        # --- Interaction: Prompt to apply persistent changes ---
        Write-Host ""
        $choice = Read-Host "Do you want to run the Machine Environment script now to persist ICU changes to the Registry? (y/n)"
        if ($choice -eq 'y' -or $choice -eq 'Y') {
            Write-Host "Executing $icuMachineEnvScript..." -ForegroundColor Yellow
            try {
                # Start the generated script. It handles its own elevation logic.
                & $icuMachineEnvScript
            }
            catch {
                Write-Error "Failed to execute the Machine Environment script: $($_.Exception.Message)"
            }
        }
        else {
            Write-Host "Skipped persistent registry update. You can run it later at: $icuMachineEnvScript" -ForegroundColor Gray
        }
    }
} else {
    Write-Error "icuuc.lib was not found in the $icuLibDir folder."
    return
}
