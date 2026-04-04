# Copyright 2026 (C) Navegos. DevelVitorF. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
# file:x64-windows/dep-libiconv.ps1

param (
    [Parameter(HelpMessage="Target vcpkg LIBICONV triplet")]
    [string]$Triplet = "x64-windows",
    
    [Parameter(HelpMessage = "Force a full uninstallation of the local LIBICONV version before continuing", Mandatory = $false)]
    [switch]$forceCleanup,
    
    [Parameter(HelpMessage = "Add's LIBICONV Machine Environment Variables. Requires Machine Administrator Rights.", Mandatory = $false)]
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
$libiconvInstallDir = $installBase
$libiconvIncludeDir = Join-Path $libiconvInstallDir "include"
$libiconvBinPath = Join-Path $libiconvInstallDir "bin"
$libiconvToolsPath = Join-Path $libiconvInstallDir "tools\libiconv"
$libiconvToolsBinPath = Join-Path $libiconvToolsPath "bin"
$libiconvLibDir = Join-Path $libiconvInstallDir "lib"
$versionFile = Join-Path $libiconvToolsPath "version.json"

# Version Detection
$repo = "microsoft/vcpkg"
$filePath = "ports/libiconv/vcpkg.json"
$branch = "master"
$rawJsonUrl = "https://raw.githubusercontent.com/$repo/$branch/$filePath"
$apiUrl = "https://api.github.com/repos/$repo/commits?path=$filePath&sha=$branch&per_page=1"
$remoteVersion = "0.0.0"
try {
    Write-Host "Fetching latest LIBICONV version from vcpkg master..." -ForegroundColor Gray
    $libiconvManifest = Invoke-RestMethod -Uri $rawJsonUrl
    $url = $rawJsonUrl
    $tag_name = $libiconvManifest.version
    $updated_at = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssZ")
    $remoteVersionString = $libiconvManifest.version.TrimStart('v')
    
    # Clean remote version for comparison (e.g., "1.12.1")
    if ($remoteVersionString -match '^(\d+\.\d+(\.\d+)?)') { $remoteVersion = $Matches[1] }

    try {
        # Fetch the commit history for this specific file
        $commits = Invoke-RestMethod -Uri $apiUrl -Method Get
        
        if ($commits.Count -gt 0) {
            $tagCommit = $commits[0].sha
            $updated_at = $commits[0].commit.committer.date
            Write-Host "[REMOTE] Latest SHA for libiconv/vcpkg.json: $tagCommit" -ForegroundColor Cyan
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
function Invoke-libiconvVersionPurge {
    param ([string]$InstallPath)
    Write-Host "--- Initiating LIBICONV Purge ---" -ForegroundColor Cyan

    $libiconvBinInstallPath = Join-Path $InstallPath "bin"
    $libiconvToolsBinInstallPath = Join-Path $InstallPath "tools\libiconv\bin"

    if ($withMachineEnvironment) {
        $libiconvCleanMachineEnvScript = Join-Path $env:TEMP "clean-machine-env-libiconv.ps1"

        # Generating Clean Machine Environment wich removes the persist registry machine Environment
        $CleanMachineEnvContent = @'
# libiconv Clean Machine Environment Setup

# --- 0. Self-Elevation Logic ---
$IsAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$ScopeColor = "Cyan"

if (-not $IsAdmin) {
    Write-Host "Elevation required to clean libiconv system variables. Relaunching as Administrator..." -ForegroundColor Yellow
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

$libiconvbinpath = "VALUE_LIBICONV_BIN_PATH"
$libiconvtoolsbinpath = "VALUE_LIBICONV_TOOLS_BIN_PATH"

$TargetScope = if ($IsAdmin) { "Machine" } else { "User" }
$RegPath = if ($IsAdmin) { "System\CurrentControlSet\Control\Session Manager\Environment" } else { "Environment" }
$RegRoot = if ($IsAdmin) { "LocalMachine" } else { "CurrentUser" }

# 1. Registry Cleanup (EXTCOMP_PATH)
$RegKey = [Microsoft.Win32.Registry]::$RegRoot.OpenSubKey($RegPath, $true)

# Open the registry key directly to read the RAW (unexpanded) string
$RawPath = $RegKey.GetValue("EXTCOMP_PATH", "", [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
$RawLibPath = $RegKey.GetValue("EXTCOMPLIBS_PATH", "", [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)

# Cleanup: Remove empty strings, any path containing $libiconvtoolsbinpath,
$CleanPath = ($RawPath -split ';' | Where-Object { $_ -notlike "*$libiconvtoolsbinpath*" }) -join ";"
$CleanLibPath = ($RawLibPath -split ';' | Where-Object { $_ -notlike "*$libiconvbinpath*" }) -join ";"

# Save as ExpandString
$RegKey.SetValue("EXTCOMP_PATH", $CleanPath, [Microsoft.Win32.RegistryValueKind]::ExpandString)
$RegKey.SetValue("EXTCOMPLIBS_PATH", $CleanLibPath, [Microsoft.Win32.RegistryValueKind]::ExpandString)
$env:EXTCOMP_PATH = $CleanPath
$env:EXTCOMPLIBS_PATH = $CleanLibPath

$RegKey.Close()

Write-Host "[REMOVED] ($TargetScope) all '*$libiconvtoolsbinpath*' removed from EXTCOMP_PATH" -ForegroundColor $ScopeColor
'@  -replace "VALUE_LIBICONV_TOOLS_BIN_PATH", $libiconvToolsBinInstallPath -replace "VALUE_LIBICONV_BIN_PATH", $libiconvBinInstallPath

        $CleanMachineEnvContent | Out-File -FilePath $libiconvCleanMachineEnvScript -Encoding utf8
        Write-Host "Created: $libiconvCleanMachineEnvScript" -ForegroundColor Gray
        
        # --- Interaction: Prompt to remove persistent changes ---
        Write-Host ""
        $choice = Read-Host "Administrator rights required to Clean Machine Environment libiconv changes? (y/n)"
        if ($choice -eq 'y' -or $choice -eq 'Y') {
            Write-Host "Executing $libiconvCleanMachineEnvScript..." -ForegroundColor Yellow
            try {
                # Start the generated script. It handles its own elevation logic.
                & $libiconvCleanMachineEnvScript
            }
            catch {
                Write-Error "Failed to execute the Clean Machine Environment script: $($_.Exception.Message)"
                return
            }
        }
        else {
            Write-Error "Skipped Clean Machine Environment libiconv changes."
            return
        }

        # Cleanup
        Remove-Item $libiconvCleanMachineEnvScript -Recurse -Force -ErrorAction SilentlyContinue
    }
    
    # --- 1. Remove LIBICONV via vcpkg ---
    # Note: 'libiconv' is the meta-package in vcpkg
    Write-Host "Removing LIBICONV:$Triplet via vcpkg..." -ForegroundColor Cyan
    Push-Location $vcpkgRoot
    cmd /c "vcpkg remove --recurse libiconv:$Triplet"
    if ($LASTEXITCODE -ne 0) {
        Write-Error "vcpkg failed to remove LIBICONV."
        Pop-Location; return
    }
    Pop-Location
    
    Write-Host "--- LIBICONV Purge Complete ---" -ForegroundColor Green
}

# Fix this using vcpkg to get LIBICONV version
$localVersion = "0.0.0"
$rawVersion = "0.0.0"
if (Test-Path (Join-Path $libiconvLibDir "iconv.lib")) {
    $rawVersion = (vcpkg list libiconv:$Triplet | Select-Object -First 1).Trim()
    if ($rawVersion -match '^(\d+\.\d+(\.\d+)?)') { $localVersion = $Matches[1] }
}

if (Test-Path $versionFile) {
    $localVersion = (Get-Content $versionFile | ConvertFrom-Json).version
}

if ($forceCleanup) {
    Invoke-libiconvVersionPurge -InstallPath $libiconvInstallDir
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
    Write-Host "[SKIP] LIBICONV $localVersion is already installed and up to date at: $libiconvInstallDir" -ForegroundColor Green
    Write-Host "LIBICONV Version: $(vcpkg list libiconv:$Triplet | Select-Object -First 1)" -ForegroundColor Gray

    # 1. Locate the bin folder and the root folder
    $libiconvVersion = $localVersion
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
    # --- 1. Install libiconv via vcpkg ---
    Write-Host "Installing libiconv:$Triplet via vcpkg..." -ForegroundColor Cyan
    Push-Location $vcpkgRoot
    cmd /c "vcpkg install --recurse libiconv:$Triplet"
    if ($LASTEXITCODE -ne 0) {
        Write-Error "vcpkg failed to install libiconv."
        Pop-Location; return
    }
    Pop-Location

    $libiconvVersion = $remoteVersion
    if (Test-Path (Join-Path $libiconvLibDir "iconv.lib")) {
        $rawVersion = (vcpkg list libiconv:$Triplet | Select-Object -First 1).Trim()
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
if (Test-Path (Join-Path $libiconvLibDir "iconv.lib")) {
    # Generate Environment Helper with Clean Paths
    $libiconvInstallDir = $libiconvInstallDir.TrimEnd('\')
    $libiconvIncludeDir = $libiconvIncludeDir.TrimEnd('\')
    $libiconvLibDir     = $libiconvLibDir.TrimEnd('\')
    $libiconvBinPath    = $libiconvBinPath.TrimEnd('\')
    $libiconvToolsBinPath = $libiconvToolsBinPath.TrimEnd('\')
    $libiconvCMakePath  = $libiconvInstallDir.Replace('\', '/')
    
    # --- 3. Create Environment Helper ---
    Write-Host "Generating environment helper script..." -ForegroundColor Cyan
    $libiconvEnvScript = Join-Path $EnvironmentDir "env-libiconv.ps1"

    # Using a literal here-string with -replace to avoid accidental expansion of $env:PATH during creation
    $EnvContent = @'
# LIBICONV Environment Setup
$libiconvroot = "VALUE_ROOT_PATH"
$libiconvinclude = "VALUE_INCLUDE_PATH"
$libiconvlibrary = "VALUE_LIB_PATH"
$libiconvbin = "VALUE_BIN_PATH"
$libiconvtoolsbin = "VALUE_TOOLS_BIN_PATH"
$libiconvcmakepath = "VALUE_CMAKE_PATH"
$libiconvversion = "VALUE_VERSION"
$env:LIBICONV_PATH = $libiconvroot
$env:LIBICONV_ROOT = $libiconvroot
$env:LIBICONV_BIN = $libiconvbin
$env:LIBICONV_TOOLS_BIN = $libiconvtoolsbin
$env:LIBICONV_INCLUDEDIR = $libiconvinclude
$env:LIBICONV_LIBRARYDIR = $libiconvlibrary
if ($env:CMAKE_PREFIX_PATH -notlike "*$libiconvcmakepath*") { $env:CMAKE_PREFIX_PATH = $libiconvcmakepath + ";" + $env:CMAKE_PREFIX_PATH }
if ($env:INCLUDE -notlike "*$libiconvinclude*") { $env:INCLUDE = $libiconvinclude + ";" + $env:INCLUDE }
if ($env:LIB -notlike "*$libiconvlibrary*") { $env:LIB = $libiconvlibrary + ";" + $env:LIB }
"$libiconvbin", "$libiconvtoolsbin" | ForEach-Object { if ($env:PATH -notlike "*$_*") { $env:PATH = $_ + ";" + $env:PATH } }
Write-Host "LIBICONV Environment Loaded (Version: $libiconvversion) (Bin: $libiconvbin)" -ForegroundColor Green
Write-Host "LIBICONV_ROOT: $env:LIBICONV_ROOT" -ForegroundColor Gray
'@  -replace "VALUE_ROOT_PATH", $libiconvInstallDir `
    -replace "VALUE_INCLUDE_PATH", $libiconvIncludeDir `
    -replace "VALUE_LIB_PATH", $libiconvLibDir `
    -replace "VALUE_BIN_PATH", $libiconvBinPath `
    -replace "VALUE_TOOLS_BIN_PATH", $libiconvToolsBinPath `
    -replace "VALUE_CMAKE_PATH", $libiconvCMakePath `
    -replace "VALUE_VERSION", $libiconvVersion

    $EnvContent | Out-File -FilePath $libiconvEnvScript -Encoding utf8
    Write-Host "Created: $libiconvEnvScript" -ForegroundColor Gray
    
    # Update Current Session
    if (Test-Path $libiconvEnvScript) { . $libiconvEnvScript } else {
        Write-Error "libiconv dep install finished but $libiconvEnvScript was not created."
        return
    }
    Write-Host "libiconv Version: $(vcpkg list libiconv:$Triplet | Select-Object -First 1)" -ForegroundColor Gray
    
    if ($withMachineEnvironment) {
        $libiconvMachineEnvScript = Join-Path $EnvironmentDir "machine-env-libiconv.ps1"

        # Generating Machine Environment wich add to the persist registry machine Environment
        $MachineEnvContent = @'
# LIBICONV Machine Environment Setup

# --- 0. Self-Elevation Logic ---
$IsAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$ScopeColor = "Cyan"

if (-not $IsAdmin) {
    Write-Host "Elevation required to set LIBICONV system variables. Relaunching as Administrator..." -ForegroundColor Yellow
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

$libiconvroot = "VALUE_ROOT_PATH"
$libiconvbin = "VALUE_BIN_PATH"
$libiconvtoolsbin = "VALUE_TOOLS_BIN_PATH"
$libiconvversion = "VALUE_VERSION"

$TargetScope = if ($IsAdmin) { "Machine" } else { "User" }
$RegPath = if ($IsAdmin) { "System\CurrentControlSet\Control\Session Manager\Environment" } else { "Environment" }
$RegRoot = if ($IsAdmin) { "LocalMachine" } else { "CurrentUser" }

# Open the registry key once
$RegKey = [Microsoft.Win32.Registry]::$RegRoot.OpenSubKey($RegPath, $true)

# Open the registry key directly to read the RAW (unexpanded) string
$CurrentRawPath = $RegKey.GetValue("EXTCOMP_PATH", "", [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
$CurrentRawLibPath = $RegKey.GetValue("EXTCOMPLIBS_PATH", "", [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)

# Cleanup: Remove empty strings, any path containing $libiconvroot, and the current target (to avoid dups)
$CleanedPathList = $CurrentRawPath -split ';' | Where-Object { 
    -not [string]::IsNullOrWhitespace($_) -and 
    $_ -notlike "*$libiconvtoolsbin*"
}
$CleanedPathLibList = $CurrentRawLibPath -split ';' | Where-Object { 
    -not [string]::IsNullOrWhitespace($_) -and 
    $_ -notlike "*$libiconvbin*"
}

$NewRawPath = ($CleanedPathList -join ";").Replace(";;", ";")
$NewRawLibPath = ($CleanedPathLibList -join ";").Replace(";;", ";")

$TargetPath = $libiconvtoolsbin
$TargetLibPath = $libiconvbin

# Rebuild
$NewRawPath = ($NewRawPath + ";" + $TargetPath + ";").Replace(";;", ";")
$NewRawLibPath = ($NewRawLibPath + ";" + $TargetLibPath + ";").Replace(";;", ";")
Write-Host "[UPDATED] ($TargetScope) '$libiconvtoolsbin' synced in EXTCOMP_PATH" -ForegroundColor $ScopeColor

# Save as ExpandString
$RegKey.SetValue("EXTCOMP_PATH", $NewRawPath, [Microsoft.Win32.RegistryValueKind]::ExpandString)
$RegKey.SetValue("EXTCOMPLIBS_PATH", $NewRawLibPath, [Microsoft.Win32.RegistryValueKind]::ExpandString)
$env:EXTCOMP_PATH = $NewRawPath
$env:EXTCOMPLIBS_PATH = $NewRawLibPath

$RegKey.Close()

$env:LIBICONV_ROOT = $libiconvroot
Write-Host "libiconv Environment Loaded (Version: $libiconvversion) (Bin: $libiconvtoolsbin)" -ForegroundColor Green
Write-Host "LIBICONV_ROOT: $env:LIBICONV_ROOT" -ForegroundColor Gray
'@  -replace "VALUE_ROOT_PATH", $libiconvInstallDir `
    -replace "VALUE_BIN_PATH", $libiconvBinPath `
    -replace "VALUE_TOOLS_BIN_PATH", $libiconvToolsBinPath `
    -replace "VALUE_VERSION", $libiconvVersion

        $MachineEnvContent | Out-File -FilePath $libiconvMachineEnvScript -Encoding utf8
        Write-Host "Created: $libiconvMachineEnvScript" -ForegroundColor Gray
        
        # --- Interaction: Prompt to apply persistent changes ---
        Write-Host ""
        $choice = Read-Host "Do you want to run the Machine Environment script now to persist LIBICONV changes to the Registry? (y/n)"
        if ($choice -eq 'y' -or $choice -eq 'Y') {
            Write-Host "Executing $libiconvMachineEnvScript..." -ForegroundColor Yellow
            try {
                # Start the generated script. It handles its own elevation logic.
                & $libiconvMachineEnvScript
            }
            catch {
                Write-Error "Failed to execute the Machine Environment script: $($_.Exception.Message)"
            }
        }
        else {
            Write-Host "Skipped persistent registry update. You can run it later at: $libiconvMachineEnvScript" -ForegroundColor Gray
        }
    }
} else {
    Write-Error "iconv.lib was not found in the $libiconvLibDir folder."
    return
}
