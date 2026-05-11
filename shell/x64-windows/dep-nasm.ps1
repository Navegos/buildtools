# SPDX-FileCopyrightText: Copyright (c) 2026 Navegos. @DevelVitorF. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
# project: buildtools
# file: x64-windows/dep-nasm.ps1
# created: 2026-05-01
# lastModified: 2026-05-11

param (
    [Parameter(HelpMessage = "Path for NASM storage", Mandatory = $false)]
    [string]$nasmInstallDir = "$env:LIBRARIES_PATH\nasm",

    [Parameter(HelpMessage = "Force a full purge of the local NASM version before continuing", Mandatory = $false)]
    [switch]$forceCleanup,
    
    [Parameter(HelpMessage = "Add's NASM Machine Environment Variables. Requires Machine Administrator Rights.", Mandatory = $false)]
    [switch]$withMachineEnvironment
)

# Capture parameters
$NasmWithMachineEnvironment = $withMachineEnvironment
$NasmForceCleanup = $forceCleanup

if ([string]::IsNullOrWhitespace($env:ENVIRONMENT_PATH) -or -not (Test-Path $env:ENVIRONMENT_PATH) -or [string]::IsNullOrWhitespace($env:BINARIES_PATH) -or -not (Test-Path $env:BINARIES_PATH) -or [string]::IsNullOrWhitespace($env:LIBRARIES_PATH) -or -not (Test-Path $env:LIBRARIES_PATH) -or [string]::IsNullOrWhitespace($env:BUILDTOOLS_PATH) -or -not (Test-Path $env:BUILDTOOLS_PATH)) {
    Write-Error "User Environment variables missing. Please run add-user-paths.ps1 -LibrariesDir 'Path/for/Libraries' -BinariesDir 'Path/for/Binaries' -EnvironmentDir 'Path/for/Environment' -BuildToolsDir 'Path/for/BuildTools'"
    return
}

$EnvironmentDir = "$env:ENVIRONMENT_PATH"

# if Symlink present delete
$GlobalBinDir = "$env:BINARIES_PATH"
$nasmtools = @("nasm.exe", "ndisasm.exe")
foreach ($nasmtool in $nasmtools) {
    $target = Join-Path $GlobalBinDir $nasmtool
    if (Test-Path $target) { Remove-Item $target -Force -ErrorAction SilentlyContinue }
}

$nasmBinPath = Join-Path $nasmInstallDir "bin"
$nasmExePath = Join-Path $nasmBinPath "nasm.exe"
$versionFile = Join-Path $nasmInstallDir "version.json"
$nasmEnvScript = Join-Path $EnvironmentDir "env-nasm.ps1"
$nasmMachineEnvScript = Join-Path $EnvironmentDir "machine-env-nasm.ps1"

# Version Detection via GitHub
$repo = "netwide-assembler/nasm"
try {
    Write-Host "Fetching latest NASM release from GitHub..." -ForegroundColor Gray
    $tags = Invoke-RestMethod -Uri "https://api.github.com/repos/$repo/tags"
    
    # Find the most recent actual release tag (e.g., nasm-2.16.03)
    $latestTag = ($tags | Where-Object { $_.name -match '^nasm-\d+\.\d+' }) | Select-Object -First 1
    if (-not $latestTag) { throw "Could not find a valid release tag in the repository." }
    
    $tag_name = $latestTag.name
    $tagCommit = $latestTag.commit.sha

    $remoteVersion = "0.0.0"
    $remoteComparableVersion = "0.0.0"
    if ($tag_name -match 'nasm-([0-9rc\.]+)') { 
        $remoteVersion = $Matches[1] 
        
        # Parse version formats like 3.02.0.rc7, 3.02.0rc7, 3.02.rc7, 3.02rc7 into 3.02.0.7
        $remoteComparableVersion = $remoteVersion -replace '\.?rc', '.rc'
        if ($remoteComparableVersion -match '^\d+\.\d+\.rc') {
            $remoteComparableVersion = $remoteComparableVersion -replace '\.rc', '.0.rc'
        }
        $remoteComparableVersion = $remoteComparableVersion -replace '\.rc', '.'
    }
    
    # Predictable release binary structure on official site
    $downloadUrl = "https://www.nasm.us/pub/nasm/releasebuilds/$remoteVersion/win64/nasm-$remoteVersion-win64.zip"
    $url = $downloadUrl
    $updated_at = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssZ")
} catch {
    Write-Warning "Could not connect to fetch release tags. Using 0.0.0 for remote."
    $url = "ERR_CONNECTION_TIMED_OUT"
    $tag_name = "0.0.0"
    $updated_at = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssZ")
    $remoteVersion = "0.0.0"
    $tagCommit = "0000000000000000000000000000000000000000"
    $downloadUrl = $null
}

# --- 1. Cleanup Mechanism ---
function Invoke-NasmVersionPurge {
    param ([string]$InstallPath)
    Write-Host "--- Initiating NASM Purge ---" -ForegroundColor Cyan

    if ($NasmWithMachineEnvironment)
    {
        $nasmCleanMachineEnvScript = Join-Path $env:TEMP "clean-machine-env-nasm.ps1"

        # Generating Clean Machine Environment wich removes the persist registry machine Environment
        $CleanMachineEnvContent = @'
# NASM Clean Machine Environment Setup

# --- 0. Self-Elevation Logic ---
$IsAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$ScopeColor = "Cyan"

if (-not $IsAdmin) {
    Write-Host "Elevation required to clean NASM system variables. Relaunching as Administrator..." -ForegroundColor Yellow
    $Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    foreach ($Parameter in $PSBoundParameters.GetEnumerator()) {
        if ($Parameter.Value -is [switch]) {
            if ($Parameter.Value) { $Arguments += " -$($Parameter.Key)" }
        }
        else {
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

$nasmroot = "VALUE_ROOT_PATH"

$TargetScope = if ($IsAdmin) { "Machine" } else { "User" }
$RegPath = if ($IsAdmin) { "System\CurrentControlSet\Control\Session Manager\Environment" } else { "Environment" }
$RegRoot = if ($IsAdmin) { "LocalMachine" } else { "CurrentUser" }

# 1. Registry Cleanup (EXTCOMP_PATH)
$RegKey = [Microsoft.Win32.Registry]::$RegRoot.OpenSubKey($RegPath, $true)
$RawPath = $RegKey.GetValue("EXTCOMP_PATH", "", [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)

# Cleanup: Remove empty strings, any path containing $nasmroot
$CleanPath = ($RawPath -split ';' | Where-Object { $_ -notlike "*$nasmroot*" }) -join ";"

$RegKey.SetValue("EXTCOMP_PATH", $CleanPath, [Microsoft.Win32.RegistryValueKind]::ExpandString)
$env:EXTCOMP_PATH = $CleanPath

$RegKey.Close()

Write-Host "[REMOVED] ($TargetScope) all '*$nasmroot*' removed from EXTCOMP_PATH" -ForegroundColor $ScopeColor
'@  -replace "VALUE_ROOT_PATH", $InstallPath

        $CleanMachineEnvContent | Out-File -FilePath $nasmCleanMachineEnvScript -Encoding utf8
        Write-Host "Created: $nasmCleanMachineEnvScript" -ForegroundColor Gray
        
        # --- Interaction: Prompt to remove persistent changes ---
        Write-Host ""
        $choice = Read-Host "Administrator rights required to Clean Machine Environment NASM changes? (y/n)"
        if ($choice -eq 'y' -or $choice -eq 'Y') {
            Write-Host "Executing $nasmCleanMachineEnvScript..." -ForegroundColor Yellow
            try {
                & $nasmCleanMachineEnvScript
            }
            catch {
                Write-Error "Failed to execute the Clean Machine Environment script: $($_.Exception.Message)"
                return
            }
        }
        else {
            Write-Error "Skipped Clean Machine Environment NASM changes."
            return
        }

        Remove-Item $nasmCleanMachineEnvScript -Recurse -Force -ErrorAction SilentlyContinue
    }

    # 2. Filesystem Clean (Requires checking for locked files)
    if (Test-Path $nasmEnvScript) {
        Write-Host "  [DELETING] $nasmEnvScript" -ForegroundColor Yellow
        Remove-Item $nasmEnvScript -Recurse -Force -ErrorAction SilentlyContinue
    }
    if (Test-Path $nasmMachineEnvScript) {
        Write-Host "  [DELETING] $nasmMachineEnvScript" -ForegroundColor Yellow
        Remove-Item $nasmMachineEnvScript -Recurse -Force -ErrorAction SilentlyContinue
    }
    if (Test-Path $InstallPath) {
        Write-Host "  [DELETING] $InstallPath" -ForegroundColor Yellow
        Remove-Item $InstallPath -Recurse -Force -ErrorAction SilentlyContinue
    }
    
    # remove local Env variables for current session
    Get-ChildItem Env:\NASM_* | ForEach-Object { Remove-Item Env:\$($_.Name) -ErrorAction SilentlyContinue }
    Get-ChildItem Env:\BINARY_NASM* | ForEach-Object { Remove-Item Env:\$($_.Name) -ErrorAction SilentlyContinue }

    foreach ($nasmtool in $nasmtools) {
        $target = Join-Path $GlobalBinDir $nasmtool
        if (Test-Path $target) { Remove-Item $target -Force -ErrorAction SilentlyContinue; Write-Host "  [REMOVED] Link: $nasmtool" -ForegroundColor Gray }
    }
    
    $CurrentPath = $env:PATH
    $CleanedPathList = $CurrentPath -split ';' | Where-Object { 
        -not [string]::IsNullOrWhitespace($_) -and 
        $_ -notlike "*$InstallPath*"
    }
    $NewPath = ($CleanedPathList -join ";").Replace(";;", ";")
    $NewPath = ($NewPath + ";").Replace(";;", ";")
    $env:PATH = $NewPath
    
    Write-Host "--- NASM Purge Complete ---" -ForegroundColor Green
}

$localVersion = "0.0.0"
$rawVersion = "0.0.0"
if (Test-Path $nasmExePath) {
    $rawVersion = (& $nasmExePath -v | Select-String "version\s+([0-9rc\.]+)").Matches.Value
    if ($rawVersion -match 'version\s+([0-9rc\.]+)') { 
        $localVersion = $Matches[1] 
        
        # Parse version formats like 3.02.0.rc7, 3.02.0rc7, 3.02.rc7, 3.02rc7 into 3.02.0.7
        $localVersion = $localVersion -replace '\.?rc', '.rc'
        if ($localVersion -match '^\d+\.\d+\.rc') {
            $localVersion = $localVersion -replace '\.rc', '.0.rc'
        }
        $localVersion = $localVersion -replace '\.rc', '.'
    }
}

if (Test-Path $versionFile) {
    $localVersion = (Get-Content $versionFile | ConvertFrom-Json).version
}

if ($NasmForceCleanup) {
    Invoke-NasmVersionPurge -InstallPath $nasmInstallDir
    $localVersion = "0.0.0"
}

# --- 2. Install or Skip ---
$vLocal  = [version]$localVersion
$vRemote = [version]$remoteComparableVersion

$isUpToDate = $false
if ($localVersion -ne "0.0.0") {
    if ($vLocal -ge $vRemote) {
        $isUpToDate = $true
    }
}

if ($isUpToDate) {
    Write-Host "[SKIP] NASM $localVersion is already installed and up to date at: $nasmExePath" -ForegroundColor Green
    Write-Host "NASM Version: $(& $nasmExePath -v)" -ForegroundColor Gray

    $nasmVersion = $localVersion

    if (-not (Test-Path $versionFile)) {
        $versionInfo = @{
            url        = $url;
            tag_name   = $tag_name;
            commit     = $tagCommit;
            version    = $localVersion;
            rawversion = $rawVersion;
            date       = (Get-Date).ToString("yyyy-MM-dd");
            updated_at = $updated_at;
            type       = "portable_dist";
        }
        $versionInfo | ConvertTo-Json | Out-File -FilePath $versionFile -Encoding utf8 -Force
    }
} else {
    Write-Host "[UPDATE] Local: $localVersion -> Remote: $remoteComparableVersion" -ForegroundColor Yellow
    
    if ($null -eq $downloadUrl) {
        Write-Error "Cannot proceed with installation. Failed to retrieve a valid download URL."
        return
    }

    if (Test-Path $nasmInstallDir) {
        Write-Host "[CLEANUP] Removing existing NASM installation at $nasmInstallDir..." -ForegroundColor Yellow
        Remove-Item -Path $nasmInstallDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    Write-Host "[INSTALL] Creating fresh directory: $nasmInstallDir" -ForegroundColor Cyan
    New-Item -Path $nasmInstallDir -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null
    New-Item -Path $nasmBinPath -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null

    try {
        $zipFile = Join-Path $env:TEMP "nasm-$remoteVersion.zip"

        Write-Host "Downloading NASM..." -ForegroundColor Cyan
        Invoke-WebRequest -Uri $downloadUrl -OutFile $zipFile

        Write-Host "Extracting to $nasmInstallDir..." -ForegroundColor Gray
        $tempExtractPath = Join-Path $env:TEMP "nasm_extract_$(Get-Random)"
        New-Item -Path $tempExtractPath -ItemType Directory -Force | Out-Null
        Expand-Archive -Path $zipFile -DestinationPath $tempExtractPath -Force

        # NASM unzips into a nested directory (e.g. nasm-2.16.03)
        Write-Host "Deploying files..." -ForegroundColor Gray
        $extractedFolder = Get-ChildItem -Path $tempExtractPath -Directory | Select-Object -First 1
        if ($extractedFolder -and (Test-Path (Join-Path $extractedFolder.FullName "nasm.exe"))) {
            Get-ChildItem -Path $extractedFolder.FullName -Filter "*.exe" | Move-Item -Destination $nasmBinPath -Force -ErrorAction SilentlyContinue
            Get-ChildItem -Path $extractedFolder.FullName -Exclude "*.exe" | Move-Item -Destination $nasmInstallDir -Force -ErrorAction SilentlyContinue
        } else {
            Get-ChildItem -Path $tempExtractPath -Filter "*.exe" | Move-Item -Destination $nasmBinPath -Force -ErrorAction SilentlyContinue
            Get-ChildItem -Path $tempExtractPath -Exclude "*.exe" | Move-Item -Destination $nasmInstallDir -Force -ErrorAction SilentlyContinue
        }
        
        $nasmVersion = $remoteComparableVersion
        if (Test-Path $nasmExePath) {
            $rawVersion = (& $nasmExePath -v | Select-String "version\s+([0-9rc\.]+)").Matches.Value
        }
        $versionInfo = @{
            url        = $url;
            tag_name   = $tag_name;
            commit     = $tagCommit;
            version    = $remoteComparableVersion;
            rawversion = $rawVersion;
            date       = (Get-Date).ToString("yyyy-MM-dd");
            updated_at = $updated_at;
            type       = "portable_dist";
        }
        $versionInfo | ConvertTo-Json | Out-File -FilePath $versionFile -Encoding utf8 -Force
    
        # Cleanup extraction debris
        Remove-Item $zipFile -Force -ErrorAction SilentlyContinue
        Remove-Item $tempExtractPath -Recurse -Force -ErrorAction SilentlyContinue

        Write-Host "NASM $remoteVersion installed successfully!" -ForegroundColor DarkGreen
    }
    catch {
        Write-Error "Failed to install NASM: $($_.Exception.Message)"
        return
    }
}

# --- 3. Finalize Helpers & Symlinks ---
if (Test-Path $nasmExePath) {
    Write-Host "Generating environment helper script..." -ForegroundColor Cyan

    $nasmBinPath = $nasmBinPath.TrimEnd('\')
    $nasmInstallDir = $nasmInstallDir.TrimEnd('\')
    $nasmExePath = Join-Path $nasmBinPath "nasm.exe"

    $EnvContent = @'
# NASM Environment Setup
$nasmroot = "VALUE_ROOT_PATH"
$nasmbin = "VALUE_BIN_PATH"
$nasmexe = "VALUE_EXE_PATH"
$nasmversion = "VALUE_VERSION"
$env:NASM_PATH = $nasmroot
$env:NASM_ROOT = $nasmroot
$env:NASM_BIN = $nasmbin
$env:BINARY_NASM = $nasmexe
if ($env:PATH -notlike "*$nasmbin*") { $env:PATH = $nasmbin + ";" + $env:PATH; $env:PATH = ($env:PATH).Replace(";;", ";") }
Write-Host "NASM Environment Loaded (Version: $nasmversion) (Bin: $nasmbin)" -ForegroundColor Green
Write-Host "NASM_ROOT: $env:NASM_ROOT" -ForegroundColor Gray
'@  -replace "VALUE_BIN_PATH", $nasmBinPath `
    -replace "VALUE_EXE_PATH", $nasmExePath `
    -replace "VALUE_ROOT_PATH", $nasmInstallDir `
    -replace "VALUE_VERSION", $nasmVersion

    $EnvContent | Out-File -FilePath $nasmEnvScript -Encoding utf8
    Write-Host "Created: $nasmEnvScript" -ForegroundColor Gray

    if (Test-Path $nasmEnvScript) { . $nasmEnvScript } else {
        Write-Error "nasm dep install finished but $nasmEnvScript was not created."
        return
    }
    
    # --- 10. Symlink to Global Binaries ---
    Write-Host "Creating global symlink to: $GlobalBinDir..." -ForegroundColor Cyan

    foreach ($nasmtool in $nasmtools) {
        $source = Join-Path $nasmBinPath $nasmtool
        $target = Join-Path $GlobalBinDir $nasmtool

        if (Test-Path $source) {
            if (Test-Path $target) { Remove-Item $target -Force -ErrorAction SilentlyContinue }
            try {
                New-Item -Path $target -ItemType SymbolicLink -Value $source -ErrorAction Stop | Out-Null
                Write-Host "[LINKED] $nasmtool" -ForegroundColor Gray
            } catch {
                New-Item -Path $target -ItemType HardLink -Value $source | Out-Null
                Write-Host "[HARDLINKED] $nasmtool (Global) -> $source" -ForegroundColor Gray
            }
        }
    }

    Write-Host "[LINKED] NASM is now globally available via %BINARIES_PATH%" -ForegroundColor Green
    Write-Host "NASM Version: $(& $nasmExePath -v)" -ForegroundColor Gray
    
    if ($NasmWithMachineEnvironment)
    {
        $MachineEnvContent = @'
# NASM Machine Environment Setup

# --- 0. Self-Elevation Logic ---
$IsAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$ScopeColor = "Cyan"

if (-not $IsAdmin) {
    Write-Host "Elevation required to set NASM system variables. Relaunching as Administrator..." -ForegroundColor Yellow
    $Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    foreach ($Parameter in $PSBoundParameters.GetEnumerator()) {
        if ($Parameter.Value -is [switch]) {
            if ($Parameter.Value) { $Arguments += " -$($Parameter.Key)" }
        }
        else {
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

$nasmroot = "VALUE_ROOT_PATH"
$nasmbin = "VALUE_BIN_PATH"
$nasmversion = "VALUE_VERSION"

$TargetScope = if ($IsAdmin) { "Machine" } else { "User" }
$RegPath = if ($IsAdmin) { "System\CurrentControlSet\Control\Session Manager\Environment" } else { "Environment" }
$RegRoot = if ($IsAdmin) { "LocalMachine" } else { "CurrentUser" }

$RegKey = [Microsoft.Win32.Registry]::$RegRoot.OpenSubKey($RegPath, $true)
$CurrentRawPath = $RegKey.GetValue("EXTCOMP_PATH", "", [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)

$CleanedPathList = $CurrentRawPath -split ';' | Where-Object { 
    -not [string]::IsNullOrWhitespace($_) -and 
    $_ -notlike "*$nasmroot*"
}

$NewRawPath = ($CleanedPathList -join ";").Replace(";;", ";")
$NewRawPath = ($NewRawPath + ";" + $nasmbin + ";").Replace(";;", ";")

Write-Host "[UPDATED] ($TargetScope) NASM path synced in EXTCOMP_PATH" -ForegroundColor $ScopeColor

$RegKey.SetValue("EXTCOMP_PATH", $NewRawPath, [Microsoft.Win32.RegistryValueKind]::ExpandString)
$env:EXTCOMP_PATH = $NewRawPath

$RegKey.Close()

$env:NASM_ROOT = $nasmroot
Write-Host "NASM Environment Loaded (Version: $nasmversion) (Bin: $nasmbin)" -ForegroundColor Green
Write-Host "NASM_ROOT: $env:NASM_ROOT" -ForegroundColor Gray
'@  -replace "VALUE_ROOT_PATH", $nasmInstallDir `
    -replace "VALUE_BIN_PATH", $nasmBinPath `
    -replace "VALUE_VERSION", $nasmVersion

        $MachineEnvContent | Out-File -FilePath $nasmMachineEnvScript -Encoding utf8
        Write-Host "Created: $nasmMachineEnvScript" -ForegroundColor Gray
        
        Write-Host ""
        $choice = Read-Host "Do you want to run the Machine Environment script now to persist NASM changes to the Registry? (y/n)"
        if ($choice -eq 'y' -or $choice -eq 'Y') {
            Write-Host "Executing $nasmMachineEnvScript..." -ForegroundColor Yellow
            try {
                & $nasmMachineEnvScript
            }
            catch {
                Write-Error "Failed to execute the Machine Environment script: $($_.Exception.Message)"
            }
        }
        else {
            Write-Host "Skipped persistent registry update. You can run it later at: $nasmMachineEnvScript" -ForegroundColor Gray
        }
    }
} else {
    Write-Error "nasm.exe was not found in the $nasmBinPath folder."
    $nasmtools | ForEach-Object { 
        $globalLinkPath = Join-Path $GlobalBinDir $_
        if (Test-Path $globalLinkPath) {
            Write-Host "Cleaning up dead symlink at $globalLinkPath..." -ForegroundColor Yellow
            Remove-Item $globalLinkPath -Force -ErrorAction SilentlyContinue
        } 
    }
    return
}
