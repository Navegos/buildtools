# SPDX-FileCopyrightText: Copyright (c) 2026 Navegos. @DevelVitorF. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
# project: buildtools
# file: x64-windows/dep-jom.ps1
# created: 2026-05-03
# lastModified: 2026-05-13

param (
    [Parameter(HelpMessage = "Path for jom storage", Mandatory = $false)]
    [string]$jomInstallDir = "$env:LIBRARIES_PATH\jom",
    
    [Parameter(HelpMessage = "Force a full purge of the local jom version before continuing", Mandatory = $false)]
    [switch]$forceCleanup,
    
    [Parameter(HelpMessage = "Add's jom Machine Environment Variables. Requires Machine Administrator Rights.", Mandatory = $false)]
    [switch]$withMachineEnvironment,

    [Parameter(ValueFromRemainingArguments = $true)]
    $RemainingArgs
)

# Capture parameters
$JomWithMachineEnvironment = $withMachineEnvironment
$JomForceCleanup = $forceCleanup

if ([string]::IsNullOrWhitespace($env:ENVIRONMENT_PATH) -or -not (Test-Path $env:ENVIRONMENT_PATH) -or [string]::IsNullOrWhitespace($env:BINARIES_PATH) -or -not (Test-Path $env:BINARIES_PATH) -or [string]::IsNullOrWhitespace($env:LIBRARIES_PATH) -or -not (Test-Path $env:LIBRARIES_PATH) -or [string]::IsNullOrWhitespace($env:BUILDTOOLS_PATH) -or -not (Test-Path $env:BUILDTOOLS_PATH)) {
    Write-Error "User Environment variables missing. Please run add-user-paths.ps1 -LibrariesDir 'Path/for/Libraries' -BinariesDir 'Path/for/Binaries' -EnvironmentDir 'Path/for/Environment' -BuildToolsDir 'Path/for/BuildTools'"
    return
}

$EnvironmentDir = "$env:ENVIRONMENT_PATH"

# if Symlink present delete
$GlobalBinDir = "$env:BINARIES_PATH"
$jomtools = @("jom.exe")
foreach ($jomtool in $jomtools) {
    $target = Join-Path $GlobalBinDir $jomtool
    if (Test-Path $target) { Remove-Item $target -Force -ErrorAction SilentlyContinue }
}
$jomBinPath = Join-Path $jomInstallDir "bin"
$jomExePath = Join-Path $jomBinPath "jom.exe"
$versionFile = Join-Path $jomInstallDir "version.json"
$jomEnvScript = Join-Path $EnvironmentDir "env-jom.ps1"
$jomMachineEnvScript = Join-Path $EnvironmentDir "machine-env-jom.ps1"

# Download URL
$url = "https://download.qt.io/official_releases/jom/jom.zip"
$tag_name = "0.0.0"
$updated_at = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssZ")
$tagCommit = "0000000000000000000000000000000000000000"

# --- 1. Cleanup Mechanism ---
function Invoke-JomVersionPurge {
    param ([string]$InstallPath)
    Write-Host "--- Initiating Jom Purge ---" -ForegroundColor Cyan

    if ($JomWithMachineEnvironment)
    {
        $jomCleanMachineEnvScript = Join-Path $env:TEMP "clean-machine-env-jom.ps1"
        
        # Generating Clean Machine Environment wich removes the persist registry machine Environment
        $CleanMachineEnvContent = @'
# Jom Clean Machine Environment Setup

# --- 0. Self-Elevation Logic ---
$IsAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$ScopeColor = "Cyan"

if (-not $IsAdmin) {
    Write-Host "Elevation required to clean jom system variables. Relaunching as Administrator..." -ForegroundColor Yellow
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

$jomroot = "VALUE_ROOT_PATH"

$TargetScope = if ($IsAdmin) { "Machine" } else { "User" }
$RegPath = if ($IsAdmin) { "System\CurrentControlSet\Control\Session Manager\Environment" } else { "Environment" }
$RegRoot = if ($IsAdmin) { "LocalMachine" } else { "CurrentUser" }

# 1. Registry Cleanup (TOOLS_PATH)
$RegKey = [Microsoft.Win32.Registry]::$RegRoot.OpenSubKey($RegPath, $true)
$RawPath = $RegKey.GetValue("TOOLS_PATH", "", [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)

# Cleanup: Remove empty strings, any path containing $jomroot,
$CleanPath = ($RawPath -split ';' | Where-Object { $_ -notlike "*$jomroot*" }) -join ";"
$RegKey.SetValue("TOOLS_PATH", $CleanPath, [Microsoft.Win32.RegistryValueKind]::ExpandString)
$env:TOOLS_PATH = $CleanPath
$RegKey.Close()

Write-Host "[REMOVED] ($TargetScope) all '*$jomroot*' removed from TOOLS_PATH" -ForegroundColor $ScopeColor
'@  -replace "VALUE_ROOT_PATH", $InstallPath

        $CleanMachineEnvContent | Out-File -FilePath $jomCleanMachineEnvScript -Encoding utf8
        Write-Host "Created: $jomCleanMachineEnvScript" -ForegroundColor Gray
        
        Write-Host ""
        $choice = Read-Host "Administrator rights required to Clean Machine Environment jom changes? (y/n)"
        if ($choice -eq 'y' -or $choice -eq 'Y') {
            Write-Host "Executing $jomCleanMachineEnvScript..." -ForegroundColor Yellow
            try { & $jomCleanMachineEnvScript }
            catch { Write-Error "Failed to execute script: $($_.Exception.Message)"; return }
        } else {
            Write-Error "Skipped Clean Machine Environment jom changes."
            return
        }
        Remove-Item $jomCleanMachineEnvScript -Recurse -Force -ErrorAction SilentlyContinue
    }

    if (Test-Path $jomEnvScript) {
        Write-Host "  [DELETING] $jomEnvScript" -ForegroundColor Yellow
        Remove-Item $jomEnvScript -Recurse -Force -ErrorAction SilentlyContinue
    }
    if (Test-Path $jomMachineEnvScript) {
        Write-Host "  [DELETING] $jomMachineEnvScript" -ForegroundColor Yellow
        Remove-Item $jomMachineEnvScript -Recurse -Force -ErrorAction SilentlyContinue
    }
    if (Test-Path $InstallPath) {
        Write-Host "  [DELETING] $InstallPath" -ForegroundColor Yellow
        Remove-Item $InstallPath -Recurse -Force -ErrorAction SilentlyContinue
    }
    
    foreach ($jomtool in $jomtools) {
        $target = Join-Path $GlobalBinDir $jomtool
        if (Test-Path $target) { Remove-Item $target -Force -ErrorAction SilentlyContinue; Write-Host "  [REMOVED] Link: $jomtool" -ForegroundColor Gray }
    }
    
    Get-ChildItem Env:\JOM_* | ForEach-Object { Remove-Item Env:\$($_.Name) -ErrorAction SilentlyContinue }
    Get-ChildItem Env:\BINARY_JOM* | ForEach-Object { Remove-Item Env:\$($_.Name) -ErrorAction SilentlyContinue }

    $CurrentPath = $env:PATH
    $CleanedPathList = $CurrentPath -split ';' | Where-Object { 
        -not [string]::IsNullOrWhitespace($_) -and 
        $_ -notlike "*$InstallPath*"
    }
    $NewPath = ($CleanedPathList -join ";").Replace(";;", ";")
    $NewPath = ($NewPath + ";").Replace(";;", ";")
    $env:PATH = $NewPath
    
    Write-Host "--- Jom Purge Complete ---" -ForegroundColor Green
}

$localVersion = "0.0.0"
$rawVersion = "0.0.0"
if (Test-Path $jomExePath) {
    $rawVersion = (& $jomExePath /VERSION 2>&1 | Select-Object -First 1).ToString().Trim()
    if ($rawVersion -match 'jom(?:\s+version)?\s+(\d+\.\d+\.\d+)') { $localVersion = $Matches[1] }
}

if (Test-Path $versionFile) {
    $localVersion = (Get-Content $versionFile | ConvertFrom-Json).version
}

if ($JomForceCleanup) {
    Invoke-JomVersionPurge -InstallPath $jomInstallDir
    $localVersion = "0.0.0"
}

# --- 2. Fetch and Compare ---
Write-Host "Fetching jom from $url to check version..." -ForegroundColor Cyan
$zipFile = Join-Path $env:TEMP "jom.zip"
$tempExtractPath = Join-Path $env:TEMP "jom_extract_$(Get-Random)"

Invoke-WebRequest -Uri $url -OutFile $zipFile
Expand-Archive -Path $zipFile -DestinationPath $tempExtractPath -Force

$tempJomExe = Join-Path $tempExtractPath "jom.exe"
$remoteVersion = "0.0.0"
$remoteRawVersion = "0.0.0"
if (Test-Path $tempJomExe) {
    $remoteRawVersion = (& $tempJomExe /VERSION 2>&1 | Select-Object -First 1).ToString().Trim()
    if ($remoteRawVersion -match 'jom(?:\s+version)?\s+(\d+\.\d+\.\d+)') { $remoteVersion = $Matches[1] }
}

$vLocal  = [version]$localVersion
$vRemote = [version]$remoteVersion

if ($vLocal -ge $vRemote -and $localVersion -ne "0.0.0") {
    Write-Host "[SKIP] Jom $localVersion is already installed at: $jomExePath" -ForegroundColor Green
    Write-Host "Jom Version: $rawVersion" -ForegroundColor Gray

    $jomVersion = $localVersion
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
    
    Remove-Item $zipFile -Force -ErrorAction SilentlyContinue
    Remove-Item $tempExtractPath -Recurse -Force -ErrorAction SilentlyContinue
} else {
    Write-Host "[UPDATE] Local: $localVersion -> Remote: $remoteVersion" -ForegroundColor Yellow
    
    if (Test-Path $jomInstallDir) {
        Write-Host "[CLEANUP] Removing existing jom installation at $jomInstallDir..." -ForegroundColor Yellow
        Remove-Item -Path $jomInstallDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    Write-Host "[INSTALL] Creating fresh directory: $jomInstallDir" -ForegroundColor Cyan
    New-Item -Path $jomInstallDir -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null
    New-Item -Path $jomBinPath -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null

    try {
        Write-Host "Deploying files to $jomInstallDir and $jomBinPath..." -ForegroundColor Gray
        Get-ChildItem -Path $tempExtractPath | ForEach-Object {
            if ($_.Extension -match '^\.(bat|exe|xml)$') {
                Move-Item -Path $_.FullName -Destination $jomBinPath -Force -ErrorAction SilentlyContinue
            } else {
                Move-Item -Path $_.FullName -Destination $jomInstallDir -Force -ErrorAction SilentlyContinue
            }
        }
        
        $jomVersion = $remoteVersion
        $rawVersion = $remoteRawVersion

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
    
        Remove-Item $zipFile -Force -ErrorAction SilentlyContinue
        Remove-Item $tempExtractPath -Recurse -Force -ErrorAction SilentlyContinue
        Write-Host "Jom $remoteVersion installed successfully!" -ForegroundColor DarkGreen
    }
    catch {
        Write-Error "Failed to install Jom: $($_.Exception.Message)"
        return 
    }
}

# --- 3. Finalize Helpers & Symlinks ---
if (Test-Path $jomExePath) {
    # Create Environment Helper
    Write-Host "Generating environment helper script..." -ForegroundColor Cyan
    
    # Generate Environment Helper with Clean Paths
    $jomBinPath = $jomBinPath.TrimEnd('\')
    $jomInstallDir = $jomInstallDir.TrimEnd('\')
    $jomExePath = Join-Path $jomInstallDir "jom.exe"
    if (-not (Test-Path $jomExePath)) { $jomExePath = Join-Path $jomBinPath "jom.exe" }
    
    # Using a literal here-string with -replace to avoid accidental expansion of $env:PATH during creation
    $EnvContent = @'
# JOM Environment Setup
$jomroot = "VALUE_ROOT_PATH"
$jombin = "VALUE_BIN_PATH"
$jomexe = "VALUE_EXE_PATH"
$jomversion = "VALUE_VERSION"
$env:JOM_PATH = $jomroot
$env:JOM_ROOT = $jomroot
$env:JOM_BIN = $jombin
$env:BINARY_JOM = $jomexe
if ($env:PATH -notlike "*$jombin*") { $env:PATH = $jombin + ";" + $env:PATH; $env:PATH = ($env:PATH).Replace(";;", ";") }
Write-Host "Jom Environment Loaded (Version: $jomversion) (Bin: $jombin)" -ForegroundColor Green
Write-Host "JOM_ROOT: $env:JOM_ROOT" -ForegroundColor Gray
'@  -replace "VALUE_BIN_PATH", $jomBinPath `
    -replace "VALUE_EXE_PATH", $jomExePath `
    -replace "VALUE_ROOT_PATH", $jomInstallDir `
    -replace "VALUE_VERSION", $jomVersion

    $EnvContent | Out-File -FilePath $jomEnvScript -Encoding utf8
    Write-Host "Created: $jomEnvScript" -ForegroundColor Gray
    
    # Update Current Session
    if (Test-Path $jomEnvScript) { . $jomEnvScript } else {
        Write-Error "jom dep install failed."
        return
    }
    
    # --- 10. Symlink to Global Binaries ---
    Write-Host "Creating global symlink to: $GlobalBinDir..." -ForegroundColor Cyan
    foreach ($jomtool in $jomtools) {
        $source = Join-Path $jomBinPath $jomtool
        $target = Join-Path $GlobalBinDir $jomtool
        if (Test-Path $source) {
            if (Test-Path $target) { Remove-Item $target -Force -ErrorAction SilentlyContinue }
            try {
                New-Item -Path $target -ItemType SymbolicLink -Value $source -ErrorAction Stop | Out-Null
                Write-Host "[LINKED] $jomtool" -ForegroundColor Gray
            } 
            catch {
                New-Item -Path $target -ItemType HardLink -Value $source | Out-Null
                Write-Host "[HARDLINKED] $jomtool (Global) -> $source" -ForegroundColor Gray
            }
        }
    }

    Write-Host "[LINKED] Jom is now globally available via %BINARIES_PATH%" -ForegroundColor Green

    Write-Host "Jom Version: $(& $jomExePath /VERSION 2>&1 | Select-Object -First 1)" -ForegroundColor Gray
    
    if ($JomWithMachineEnvironment) {
        $MachineEnvContent = @'
# Jom Machine Environment Setup

# --- 0. Self-Elevation Logic ---
$IsAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$ScopeColor = "Cyan"

if (-not $IsAdmin) {
    Write-Host "Elevation required to set jom system variables. Relaunching as Administrator..." -ForegroundColor Yellow
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

$jomroot = "VALUE_ROOT_PATH"
$jombin = "VALUE_BIN_PATH"
$jomversion = "VALUE_VERSION"

$TargetScope = if ($IsAdmin) { "Machine" } else { "User" }
$RegPath = if ($IsAdmin) { "System\CurrentControlSet\Control\Session Manager\Environment" } else { "Environment" }
$RegRoot = if ($IsAdmin) { "LocalMachine" } else { "CurrentUser" }

# Open the registry key once
$RegKey = [Microsoft.Win32.Registry]::$RegRoot.OpenSubKey($RegPath, $true)

# Open the registry key directly to read the RAW (unexpanded) string
$CurrentRawPath = $RegKey.GetValue("TOOLS_PATH", "", [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)

# Cleanup: Remove empty strings, any path containing $jomroot, and the current target (to avoid dups)
$CleanedPathList = $CurrentRawPath -split ';' | Where-Object { 
    -not [string]::IsNullOrWhitespace($_) -and 
    $_ -notlike "*$jomroot*"
}

$NewRawPath = ($CleanedPathList -join ";").Replace(";;", ";")

$TargetPath = $jombin

# Rebuild
$NewRawPath = ($NewRawPath + ";" + $TargetPath + ";").Replace(";;", ";")
Write-Host "[UPDATED] ($TargetScope) '$jombin' synced in TOOLS_PATH" -ForegroundColor $ScopeColor

# Save as ExpandString
$RegKey.SetValue("TOOLS_PATH", $NewRawPath, [Microsoft.Win32.RegistryValueKind]::ExpandString)
$env:TOOLS_PATH = $NewRawPath

$RegKey.Close()

Write-Host "Jom Environment Loaded (Version: $jomVersion) (Bin: $jomBinPath)" -ForegroundColor Green
Write-Host "JOM_ROOT: $env:JOM_ROOT" -ForegroundColor Gray
'@  -replace "VALUE_ROOT_PATH", $jomInstallDir `
    -replace "VALUE_BIN_PATH", $jomBinPath `
    -replace "VALUE_VERSION", $jomVersion

        $MachineEnvContent | Out-File -FilePath $jomMachineEnvScript -Encoding utf8
        Write-Host "Created: $jomMachineEnvScript" -ForegroundColor Gray
        
        # --- Interaction: Prompt to apply persistent changes ---
        Write-Host ""
        $choice = Read-Host "Do you want to run the Machine Environment script now to persist Jom changes to the Registry? (y/n)"
        if ($choice -eq 'y' -or $choice -eq 'Y') {
            Write-Host "Executing $jomMachineEnvScript..." -ForegroundColor Yellow
            try {
                # Start the generated script. It handles its own elevation logic.
                & $jomMachineEnvScript
            }
            catch {
                Write-Error "Failed to execute the Machine Environment script: $($_.Exception.Message)"
            }
        }
        else {
            Write-Host "Skipped persistent registry update. You can run it later at: $jomMachineEnvScript" -ForegroundColor Gray
        }
    }
} else {
    Write-Error "jom.exe was not found in the $jomBinPath folder."
    return
}
