# Copyright 2026 (C) Navegos. DevelVitorF. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
# file:x64-windows/dep-bzip2.ps1

param (
    [Parameter(HelpMessage = "Target vcpkg BZIP2 triplet")]
    [string]$Triplet = "x64-windows",
    
    [Parameter(HelpMessage = "Force a full purge of the local BZIP2 version before continuing", Mandatory = $false)]
    [switch]$forceCleanup,
    
    [Parameter(HelpMessage = "Add's BZIP2 Machine Environment Variables. Requires Machine Administrator Rights.", Mandatory = $false)]
    [switch]$withMachineEnvironment
)

# Capture parameters
$bzip2WithMachineEnvironment = $withMachineEnvironment
$bzip2ForceCleanup = $forceCleanup

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
if (-not $env:VCPKG_PATH) {
    $vcpkgEnvScript = Join-Path $EnvironmentDir "env-vcpkg.ps1"
    if (Test-Path $vcpkgEnvScript) { . $vcpkgEnvScript }
    if (-not $env:VCPKG_PATH) {
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
$bzip2InstallDir = $installBase
$bzip2IncludeDir = Join-Path $bzip2InstallDir "include"
$bzip2BinPath = Join-Path $bzip2InstallDir "bin"
$bzip2ToolsPath = Join-Path $bzip2InstallDir "tools\bzip2"
$bzip2ToolsBinPath = Join-Path $bzip2ToolsPath "bin"
$bzip2LibDir = Join-Path $bzip2InstallDir "lib"
$versionFile = Join-Path $bzip2ToolsPath "version.json"
$bzip2EnvScript = Join-Path $EnvironmentDir "env-bzip2.ps1"
$bzip2MachineEnvScript = Join-Path $EnvironmentDir "machine-env-bzip2.ps1"

# Version Detection
$repo = "microsoft/vcpkg"
$filePath = "ports/bzip2/vcpkg.json"
$branch = "master"
$rawJsonUrl = "https://raw.githubusercontent.com/$repo/$branch/$filePath"
$apiUrl = "https://api.github.com/repos/$repo/commits?path=$filePath&sha=$branch&per_page=1"
$remoteVersion = "0.0.0"
try {
    Write-Host "Fetching latest BZIP2 version from vcpkg master..." -ForegroundColor Gray
    $bzip2Manifest = Invoke-RestMethod -Uri $rawJsonUrl
    $url = $rawJsonUrl
    $tag_name = $bzip2Manifest.version
    $updated_at = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssZ")
    $remoteVersionString = $bzip2Manifest.version.TrimStart('v')
    
    # Clean remote version for comparison (e.g., "1.12.1")
    if ($remoteVersionString -match '^(\d+\.\d+(\.\d+)?)') { $remoteVersion = $Matches[1] }

    try {
        # Fetch the commit history for this specific file
        $commits = Invoke-RestMethod -Uri $apiUrl -Method Get
        
        if ($commits.Count -gt 0) {
            $tagCommit = $commits[0].sha
            $updated_at = $commits[0].commit.committer.date
            Write-Host "[REMOTE] Latest SHA for bzip2/vcpkg.json: $tagCommit" -ForegroundColor Cyan
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
function Invoke-bzip2VersionPurge {
    param ([string]$InstallPath)
    Write-Host "--- Initiating BZIP2 Purge ---" -ForegroundColor Cyan

    $bzip2BinInstallPath = Join-Path $InstallPath "bin"
    $bzip2ToolsBinInstallPath = Join-Path $InstallPath "tools\bzip2\bin"

    if ($bzip2WithMachineEnvironment)
    {
        $bzip2CleanMachineEnvScript = Join-Path $env:TEMP "clean-machine-env-bzip2.ps1"

        # Generating Clean Machine Environment wich removes the persist registry machine Environment
        $CleanMachineEnvContent = @'
# bzip2 Clean Machine Environment Setup

# --- 0. Self-Elevation Logic ---
$IsAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$ScopeColor = "Cyan"

if (-not $IsAdmin) {
    Write-Host "Elevation required to clean bzip2 system variables. Relaunching as Administrator..." -ForegroundColor Yellow
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

$bzip2binpath = "VALUE_BZIP2_BIN_PATH"
$bzip2toolsbinpath = "VALUE_BZIP2_TOOLS_BIN_PATH"

$TargetScope = if ($IsAdmin) { "Machine" } else { "User" }
$RegPath = if ($IsAdmin) { "System\CurrentControlSet\Control\Session Manager\Environment" } else { "Environment" }
$RegRoot = if ($IsAdmin) { "LocalMachine" } else { "CurrentUser" }

# 1. Registry Cleanup (EXTCOMP_PATH)
$RegKey = [Microsoft.Win32.Registry]::$RegRoot.OpenSubKey($RegPath, $true)

# Open the registry key directly to read the RAW (unexpanded) string
$RawPath = $RegKey.GetValue("EXTCOMP_PATH", "", [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
$RawLibPath = $RegKey.GetValue("EXTCOMPLIBS_PATH", "", [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)

# Cleanup: Remove empty strings, any path containing $bzip2toolsbinpath,
$CleanPath = ($RawPath -split ';' | Where-Object { $_ -notlike "*$bzip2toolsbinpath*" }) -join ";"
$CleanLibPath = ($RawLibPath -split ';' | Where-Object { $_ -notlike "*$bzip2binpath*" }) -join ";"

# Save as ExpandString
$RegKey.SetValue("EXTCOMP_PATH", $CleanPath, [Microsoft.Win32.RegistryValueKind]::ExpandString)
$RegKey.SetValue("EXTCOMPLIBS_PATH", $CleanLibPath, [Microsoft.Win32.RegistryValueKind]::ExpandString)
$env:EXTCOMP_PATH = $CleanPath
$env:EXTCOMPLIBS_PATH = $CleanLibPath

$RegKey.Close()

Write-Host "[REMOVED] ($TargetScope) all '*$bzip2toolsbinpath*' removed from EXTCOMP_PATH" -ForegroundColor $ScopeColor
'@  -replace "VALUE_BZIP2_TOOLS_BIN_PATH", $bzip2ToolsBinInstallPath -replace "VALUE_BZIP2_BIN_PATH", $bzip2BinInstallPath

        $CleanMachineEnvContent | Out-File -FilePath $bzip2CleanMachineEnvScript -Encoding utf8
        Write-Host "Created: $bzip2CleanMachineEnvScript" -ForegroundColor Gray
        
        # --- Interaction: Prompt to remove persistent changes ---
        Write-Host ""
        $choice = Read-Host "Administrator rights required to Clean Machine Environment bzip2 changes? (y/n)"
        if ($choice -eq 'y' -or $choice -eq 'Y') {
            Write-Host "Executing $bzip2CleanMachineEnvScript..." -ForegroundColor Yellow
            try {
                # Start the generated script. It handles its own elevation logic.
                & $bzip2CleanMachineEnvScript
            }
            catch {
                Write-Error "Failed to execute the Clean Machine Environment script: $($_.Exception.Message)"
                return
            }
        }
        else {
            Write-Error "Skipped Clean Machine Environment bzip2 changes."
            return
        }

        # Cleanup
        Remove-Item $bzip2CleanMachineEnvScript -Recurse -Force -ErrorAction SilentlyContinue
    }
    
    # 2. Filesystem Clean (Requires checking for locked files)
    # delete everithing we create don't fail later
    if (Test-Path $bzip2EnvScript) {
        Write-Host "  [DELETING] $bzip2EnvScript" -ForegroundColor Yellow
        Remove-Item $bzip2EnvScript -Recurse -Force -ErrorAction SilentlyContinue
    }
    if (Test-Path $bzip2MachineEnvScript) {
        Write-Host "  [DELETING] $bzip2MachineEnvScript" -ForegroundColor Yellow
        Remove-Item $bzip2MachineEnvScript -Recurse -Force -ErrorAction SilentlyContinue
    }

    # --- 1. Remove BZIP2 via vcpkg ---
    # Note: 'bzip2' is the meta-package in vcpkg
    Write-Host "Removing BZIP2:$Triplet via vcpkg..." -ForegroundColor Cyan
    Push-Location $vcpkgRoot
    cmd /c "vcpkg remove --recurse bzip2:$Triplet"
    if ($LASTEXITCODE -ne 0) {
        Write-Error "vcpkg failed to remove BZIP2."
        Pop-Location; return
    }
    Pop-Location
    
    # remove local Env variables for current session
    Get-ChildItem Env:\BZIP2_PATH* | Remove-Item -ErrorAction SilentlyContinue
    Get-ChildItem Env:\BZIP2_ROOT* | Remove-Item -ErrorAction SilentlyContinue
    Get-ChildItem Env:\BZIP2_BIN* | Remove-Item -ErrorAction SilentlyContinue
    Get-ChildItem Env:\BZIP2_TOOLS_BIN* | Remove-Item -ErrorAction SilentlyContinue
    Get-ChildItem Env:\BZIP2_INCLUDE_DIR* | Remove-Item -ErrorAction SilentlyContinue
    Get-ChildItem Env:\BZIP2_LIBRARY_DIR* | Remove-Item -ErrorAction SilentlyContinue

    Write-Host "--- BZIP2 Purge Complete ---" -ForegroundColor Green
}

# Fix this using vcpkg to get BZIP2 version
$localVersion = "0.0.0"
$rawVersion = "0.0.0"
if (Test-Path (Join-Path $bzip2LibDir "bzip2uc.lib")) {
    $rawVersion = (vcpkg list bzip2:$Triplet | Select-Object -First 1).Trim()
    if ($rawVersion -match '^(\d+\.\d+(\.\d+)?)') { $localVersion = $Matches[1] }
}

if (Test-Path $versionFile) {
    $localVersion = (Get-Content $versionFile | ConvertFrom-Json).version
}

if ($bzip2ForceCleanup) {
    Invoke-bzip2VersionPurge -InstallPath $bzip2InstallDir
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
    Write-Host "[SKIP] BZIP2 $localVersion is already installed and up to date at: $bzip2InstallDir" -ForegroundColor Green
    Write-Host "BZIP2 Version: $(vcpkg list bzip2:$Triplet | Select-Object -First 1)" -ForegroundColor Gray

    # 1. Locate the bin folder and the root folder
    $bzip2Version = $localVersion
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
    # --- 1. Install BZIP2 via vcpkg ---
    # Note: 'bzip2' is the meta-package in vcpkg
    Write-Host "Installing bzip2:$Triplet via vcpkg..." -ForegroundColor Cyan
    Push-Location $vcpkgRoot
    cmd /c "vcpkg install --recurse bzip2:$Triplet"
    if ($LASTEXITCODE -ne 0) {
        Write-Error "vcpkg failed to install BZIP2."
        Pop-Location; return
    }
    Pop-Location

    $bzip2Version = $remoteVersion
    if (Test-Path (Join-Path $bzip2LibDir "bz2.lib")) {
        $rawVersion = (vcpkg list bzip2:$Triplet | Select-Object -First 1).Trim()
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
# BZIP2 typically produces bz2.lib etc.
if (Test-Path (Join-Path $bzip2LibDir "bz2.lib")) {
    # Generate Environment Helper with Clean Paths
    $bzip2InstallDir = $bzip2InstallDir.TrimEnd('\')
    $bzip2IncludeDir = $bzip2IncludeDir.TrimEnd('\')
    $bzip2LibDir     = $bzip2LibDir.TrimEnd('\')
    $bzip2BinPath    = $bzip2BinPath.TrimEnd('\')
    $bzip2ToolsBinPath = $bzip2ToolsBinPath.TrimEnd('\')
    $bzip2CMakePath  = $bzip2InstallDir.Replace('\', '/')
    
    # --- 3. Create Environment Helper ---
    Write-Host "Generating environment helper script..." -ForegroundColor Cyan

    # Using a literal here-string with -replace to avoid accidental expansion of $env:PATH during creation
    $EnvContent = @'
# BZIP2 Environment Setup
$bzip2root = "VALUE_ROOT_PATH"
$bzip2include = "VALUE_INCLUDE_PATH"
$bzip2library = "VALUE_LIB_PATH"
$bzip2bin = "VALUE_BIN_PATH"
$bzip2toolsbin = "VALUE_TOOLS_BIN_PATH"
$bzip2cmakepath = "VALUE_CMAKE_PATH"
$bzip2version = "VALUE_VERSION"
$env:BZIP2_PATH = $bzip2root
$env:BZIP2_ROOT = $bzip2root
$env:BZIP2_BIN = $bzip2bin
$env:BZIP2_TOOLS_BIN = $bzip2toolsbin
$env:BZIP2_INCLUDE_DIR = $bzip2include
$env:BZIP2_LIBRARY_DIR = $bzip2library
if ($env:CMAKE_PREFIX_PATH -notlike "*$bzip2cmakepath*") { $env:CMAKE_PREFIX_PATH = $bzip2cmakepath + ";" + $env:CMAKE_PREFIX_PATH; $env:CMAKE_PREFIX_PATH = ($env:CMAKE_PREFIX_PATH).Replace(";;", ";") }
if ($env:INCLUDE -notlike "*$bzip2include*") { $env:INCLUDE = $bzip2include + ";" + $env:INCLUDE; $env:INCLUDE = ($env:INCLUDE).Replace(";;", ";") }
if ($env:LIB -notlike "*$bzip2library*") { $env:LIB = $bzip2library + ";" + $env:LIB; $env:LIB = ($env:LIB).Replace(";;", ";") }
"$bzip2bin", "$bzip2toolsbin" | ForEach-Object { if ($env:PATH -notlike "*$_*") { $env:PATH = $_ + ";" + $env:PATH; $env:PATH = ($env:PATH).Replace(";;", ";") } }
Write-Host "BZIP2 Environment Loaded (Version: $bzip2version) (Bin: $bzip2bin)" -ForegroundColor Green
Write-Host "BZIP2_ROOT: $env:BZIP2_ROOT" -ForegroundColor Gray
'@  -replace "VALUE_ROOT_PATH", $bzip2InstallDir `
    -replace "VALUE_INCLUDE_PATH", $bzip2IncludeDir `
    -replace "VALUE_LIB_PATH", $bzip2LibDir `
    -replace "VALUE_BIN_PATH", $bzip2BinPath `
    -replace "VALUE_TOOLS_BIN_PATH", $bzip2ToolsBinPath `
    -replace "VALUE_CMAKE_PATH", $bzip2CMakePath `
    -replace "VALUE_VERSION", $bzip2Version

    $EnvContent | Out-File -FilePath $bzip2EnvScript -Encoding utf8
    Write-Host "Created: $bzip2EnvScript" -ForegroundColor Gray
    
    # Update Current Session
    if (Test-Path $bzip2EnvScript) { . $bzip2EnvScript } else {
        Write-Error "bzip2 dep install finished but $bzip2EnvScript was not created."
        return
    }
    Write-Host "bzip2 Version: $(vcpkg list bzip2:$Triplet | Select-Object -First 1)" -ForegroundColor Gray
    
    if ($bzip2WithMachineEnvironment)
    {
        # Generating Machine Environment wich add to the persist registry machine Environment
        $MachineEnvContent = @'
# BZIP2 Machine Environment Setup

# --- 0. Self-Elevation Logic ---
$IsAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$ScopeColor = "Cyan"

if (-not $IsAdmin) {
    Write-Host "Elevation required to set BZIP2 system variables. Relaunching as Administrator..." -ForegroundColor Yellow
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

$bzip2root = "VALUE_ROOT_PATH"
$bzip2bin = "VALUE_BIN_PATH"
$bzip2toolsbin = "VALUE_TOOLS_BIN_PATH"
$bzip2version = "VALUE_VERSION"

$TargetScope = if ($IsAdmin) { "Machine" } else { "User" }
$RegPath = if ($IsAdmin) { "System\CurrentControlSet\Control\Session Manager\Environment" } else { "Environment" }
$RegRoot = if ($IsAdmin) { "LocalMachine" } else { "CurrentUser" }

# Open the registry key once
$RegKey = [Microsoft.Win32.Registry]::$RegRoot.OpenSubKey($RegPath, $true)

# Open the registry key directly to read the RAW (unexpanded) string
$CurrentRawPath = $RegKey.GetValue("EXTCOMP_PATH", "", [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
$CurrentRawLibPath = $RegKey.GetValue("EXTCOMPLIBS_PATH", "", [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)

# Cleanup: Remove empty strings, any path containing $bzip2root, and the current target (to avoid dups)
$CleanedPathList = $CurrentRawPath -split ';' | Where-Object { 
    -not [string]::IsNullOrWhitespace($_) -and 
    $_ -notlike "*$bzip2toolsbin*"
}
$CleanedPathLibList = $CurrentRawLibPath -split ';' | Where-Object { 
    -not [string]::IsNullOrWhitespace($_) -and 
    $_ -notlike "*$bzip2bin*"
}

$NewRawPath = ($CleanedPathList -join ";").Replace(";;", ";")
$NewRawLibPath = ($CleanedPathLibList -join ";").Replace(";;", ";")

$TargetPath = $bzip2toolsbin
$TargetLibPath = $bzip2bin

# Rebuild
$NewRawPath = ($NewRawPath + ";" + $TargetPath + ";").Replace(";;", ";")
$NewRawLibPath = ($NewRawLibPath + ";" + $TargetLibPath + ";").Replace(";;", ";")
Write-Host "[UPDATED] ($TargetScope) '$bzip2toolsbin' synced in EXTCOMP_PATH" -ForegroundColor $ScopeColor

# Save as ExpandString
$RegKey.SetValue("EXTCOMP_PATH", $NewRawPath, [Microsoft.Win32.RegistryValueKind]::ExpandString)
$RegKey.SetValue("EXTCOMPLIBS_PATH", $NewRawLibPath, [Microsoft.Win32.RegistryValueKind]::ExpandString)
$env:EXTCOMP_PATH = $NewRawPath
$env:EXTCOMPLIBS_PATH = $NewRawLibPath

$RegKey.Close()

$env:BZIP2_ROOT = $bzip2root
Write-Host "bzip2 Environment Loaded (Version: $bzip2version) (Bin: $bzip2toolsbin)" -ForegroundColor Green
Write-Host "BZIP2_ROOT: $env:BZIP2_ROOT" -ForegroundColor Gray
'@  -replace "VALUE_ROOT_PATH", $bzip2InstallDir `
    -replace "VALUE_BIN_PATH", $bzip2BinPath `
    -replace "VALUE_TOOLS_BIN_PATH", $bzip2ToolsBinPath `
    -replace "VALUE_VERSION", $bzip2Version

        $MachineEnvContent | Out-File -FilePath $bzip2MachineEnvScript -Encoding utf8
        Write-Host "Created: $bzip2MachineEnvScript" -ForegroundColor Gray
        
        # --- Interaction: Prompt to apply persistent changes ---
        Write-Host ""
        $choice = Read-Host "Do you want to run the Machine Environment script now to persist BZIP2 changes to the Registry? (y/n)"
        if ($choice -eq 'y' -or $choice -eq 'Y') {
            Write-Host "Executing $bzip2MachineEnvScript..." -ForegroundColor Yellow
            try {
                # Start the generated script. It handles its own elevation logic.
                & $bzip2MachineEnvScript
            }
            catch {
                Write-Error "Failed to execute the Machine Environment script: $($_.Exception.Message)"
            }
        }
        else {
            Write-Host "Skipped persistent registry update. You can run it later at: $bzip2MachineEnvScript" -ForegroundColor Gray
        }
    }
} else {
    Write-Error "bz2.lib was not found in the $bzip2LibDir folder."
    return
}
