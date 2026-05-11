# SPDX-FileCopyrightText: Copyright (c) 2026 Navegos. @DevelVitorF. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
# project: buildtools
# file: x64-windows/dep-msmpi.ps1
# created: 2026-04-30
# lastModified: 2026-05-11

param (
    [Parameter(HelpMessage = "Force a full purge of the local MS-MPI version before continuing", Mandatory = $false)]
    [switch]$forceCleanup,
    
    [Parameter(HelpMessage = "Add's MS-MPI Machine Environment Variables. Requires Machine Administrator Rights.", Mandatory = $false)]
    [switch]$withMachineEnvironment
)

# Capture parameters
$msmpiForceCleanup = $forceCleanup
$msmpiWithMachineEnvironment = $withMachineEnvironment

# 1. Bootstrap Environment if variables are missing
if ([string]::IsNullOrWhitespace($env:ENVIRONMENT_PATH) -or -not (Test-Path $env:ENVIRONMENT_PATH) -or [string]::IsNullOrWhitespace($env:BINARIES_PATH) -or -not (Test-Path $env:BINARIES_PATH) -or [string]::IsNullOrWhitespace($env:LIBRARIES_PATH) -or -not (Test-Path $env:LIBRARIES_PATH) -or [string]::IsNullOrWhitespace($env:BUILDTOOLS_PATH) -or -not (Test-Path $env:BUILDTOOLS_PATH)) {
    Write-Error "User Environment variables missing. Please run add-user-paths.ps1 -LibrariesDir 'Path/for/Libraries' -BinariesDir 'Path/for/Binaries' -EnvironmentDir 'Path/for/Environment' -BuildToolsDir 'Path/for/BuildTools'"
    return
}

$EnvironmentDir = "$env:ENVIRONMENT_PATH"

# --- 1. Initialize Visual Studio 2026 Dev Environment dependencie requirement ---
$DevShellBootstrapScript = Join-Path $PSScriptRoot "dev-shell.ps1"
if (Test-Path $DevShellBootstrapScript) { . $DevShellBootstrapScript } else {
    Write-Error "Required dependency '$DevShellBootstrapScript' not found!"
    return
}

Write-Host "--- Microsoft MPI (MS-MPI) Management ---" -ForegroundColor Cyan

$GlobalBinDir = "$env:BINARIES_PATH"
$mpitools = @("mpiexec.exe", "smpd.exe", "msmpilaunchsvc.exe")

# --- 3. Resolve Paths ---
$msmpiBinPath = Join-Path $env:ProgramFiles "Microsoft MPI\Bin"
$msmpiSdkPath = Join-Path ${env:ProgramFiles(x86)} "Microsoft SDKs\MPI"
$msmpiIncludeDir = Join-Path $msmpiSdkPath "Include"
$msmpiLibDir = Join-Path $msmpiSdkPath "Lib\x64"
$msmpiExePath = Join-Path $msmpiBinPath "mpiexec.exe"
$versionFile = Join-Path $msmpiSdkPath "version.json"
$msmpiEnvScript = Join-Path $EnvironmentDir "env-msmpi.ps1"
$msmpiMachineEnvScript = Join-Path $EnvironmentDir "machine-env-msmpi.ps1"

# Version Detection
$remoteVersion = "0.0.0"
$url = "N/A"
$tag_name = "0.0.0"
$updated_at = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssZ")
$tagCommit = "N/A"

try {
    Write-Host "Fetching latest MS-MPI version from WinGet..." -ForegroundColor Gray
    $wingetOutput = winget show --id Microsoft.msmpi --source winget --accept-source-agreements 2>&1
    
    $versionMatch = $wingetOutput | Select-String -Pattern 'Version:\s*(.+)'
    if ($versionMatch) {
        $remoteVersionString = $versionMatch.Matches.Groups[1].Value.Trim()
        if ($remoteVersionString -match '^(\d+\.\d+(\.\d+)?)') { 
            $remoteVersion = $Matches[1] 
            $tag_name = "v$remoteVersion"
        }
    }
    
    $urlMatch = $wingetOutput | Select-String -Pattern 'Installer URL:\s*(.+)'
    if ($urlMatch) { $url = $urlMatch.Matches.Groups[1].Value.Trim() }
    
    if ($remoteVersion -eq "0.0.0") { throw "Failed to parse version from WinGet output." }
}
catch {
    Write-Warning "Could not retrieve MS-MPI info from WinGet. Using 0.0.0 for remote."
    $url = "ERR_WINGET_FAILED"
    $tagCommit = "N/A"
}

# --- 1. Cleanup Mechanism ---
function Invoke-MSMPIVersionPurge {
    Write-Host "--- Initiating MS-MPI Purge ---" -ForegroundColor Cyan

    if ($msmpiWithMachineEnvironment) {
        $msmpiCleanMachineEnvScript = Join-Path $env:TEMP "clean-machine-env-msmpi.ps1"

        # Generating Clean Machine Environment wich removes the persist registry machine Environment
        $CleanMachineEnvContent = @'
# MS-MPI Clean Machine Environment Setup

# --- 0. Self-Elevation Logic ---
$IsAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $IsAdmin) {
    Write-Host "Elevation required to clean MS-MPI system variables. Relaunching as Administrator..." -ForegroundColor Yellow
    $Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    try {
        Start-Process pwsh.exe -ArgumentList $Arguments -Verb RunAs -Wait
    }
    catch {
        Start-Process powershell.exe -ArgumentList $Arguments -Verb RunAs -Wait
    }
    exit
}

$ScopeColor = "Cyan"

$TargetScope = "Machine"
$RegPath = "System\CurrentControlSet\Control\Session Manager\Environment"
$RegRoot = "LocalMachine"

# 1. Registry Cleanup (EXTCOMP_PATH)
$RegKey = [Microsoft.Win32.Registry]::$RegRoot.OpenSubKey($RegPath, $true)

# Remove MS-MPI Specific Variables
$VarsToRemove = @("MSMPI_BIN", "MSMPI_INC", "MSMPI_LIB32", "MSMPI_LIB64", "MSMPI_ROOT")
foreach ($VarName in $VarsToRemove) {
    [Environment]::SetEnvironmentVariable($VarName, [NullString]::Value, $TargetScope)
    try { if ($RegKey.GetValue($VarName)) { $RegKey.DeleteValue($VarName, $false) } } catch {}
    Write-Host "[REMOVED] ($TargetScope) '$VarName' removed from system variables" -ForegroundColor $ScopeColor
}

$msmpibinpath = "VALUE_MSMPI_BIN_PATH"

# Cleanup PATH entries
$RawPath = $RegKey.GetValue("EXTCOMP_PATH", "", [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)

$CleanPath = ($RawPath -split ';' | Where-Object { $_ -notlike "*$msmpibinpath*" }) -join ";"

$RegKey.SetValue("EXTCOMP_PATH", $CleanPath, [Microsoft.Win32.RegistryValueKind]::ExpandString)
$env:EXTCOMP_PATH = $CleanPath

$RegKey.Close()

Write-Host "[REMOVED] ($TargetScope) all '*$msmpibinpath*' removed from EXTCOMP_PATH" -ForegroundColor $ScopeColor
'@  -replace "VALUE_MSMPI_BIN_PATH", $msmpiBinPath

        $CleanMachineEnvContent | Out-File -FilePath $msmpiCleanMachineEnvScript -Encoding utf8
        Write-Host "Created: $msmpiCleanMachineEnvScript" -ForegroundColor Gray
        
        # --- Interaction: Prompt to remove persistent changes ---
        Write-Host ""
        $choice = Read-Host "Administrator rights required to Clean Machine Environment MS-MPI changes? (y/n)"
        if ($choice -eq 'y' -or $choice -eq 'Y') {
            Write-Host "Executing $msmpiCleanMachineEnvScript..." -ForegroundColor Yellow
            try {
                & $msmpiCleanMachineEnvScript
            }
            catch {
                Write-Error "Failed to execute the Clean Machine Environment script: $($_.Exception.Message)"
                return
            }
        }
        else {
            Write-Error "Skipped Clean Machine Environment MS-MPI changes."
            return
        }

        Remove-Item $msmpiCleanMachineEnvScript -Recurse -Force -ErrorAction SilentlyContinue
    }
    
    # Filesystem Clean
    if (Test-Path $msmpiEnvScript) {
        Remove-Item $msmpiEnvScript -Recurse -Force -ErrorAction SilentlyContinue
    }
    if (Test-Path $msmpiMachineEnvScript) {
        Remove-Item $msmpiMachineEnvScript -Recurse -Force -ErrorAction SilentlyContinue
    }

    # --- 1. Uninstall via WinGet / Fallbacks ---
    $msmpiUninstallScript = Join-Path $env:TEMP "uninstall-msmpi.ps1"
    
    $UninstallScriptContent = @'
# MS-MPI Uninstall Script

# --- 0. Self-Elevation Logic ---
$IsAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $IsAdmin) {
    Write-Host "Elevation required to uninstall MS-MPI. Relaunching as Administrator..." -ForegroundColor Yellow
    $Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    try {
        Start-Process pwsh.exe -ArgumentList $Arguments -Verb RunAs -Wait
    }
    catch {
        Start-Process powershell.exe -ArgumentList $Arguments -Verb RunAs -Wait
    }
    exit
}

$msmpiexepath = "VALUE_MSMPI_EXE_PATH"

if (Get-Command winget -ErrorAction SilentlyContinue) {
    Write-Host "Uninstalling MS-MPI via WinGet..." -ForegroundColor Yellow
    winget uninstall --id Microsoft.msmpisdk --silent --accept-source-agreements | Out-Null
    winget uninstall --id Microsoft.msmpi --silent --accept-source-agreements | Out-Null
}
elseif (Test-Path $msmpiexepath) {
    Write-Host "Uninstalling Microsoft MPI Runtime (Legacy)..." -ForegroundColor Yellow
    $setupPath = Join-Path $env:TEMP "msmpisetup_uninstall.exe"
    if (-not (Test-Path $setupPath)) {
        try {
            $repoMpi = "microsoft/Microsoft-MPI"
            $latestMpiRelease = Invoke-RestMethod -Uri "https://api.github.com/repos/$repoMpi/releases/latest"
            $setupUrl = ($latestMpiRelease.assets | Where-Object { $_.name -eq "msmpisetup.exe" }).browser_download_url
            Invoke-WebRequest -Uri $setupUrl -OutFile $setupPath
        } catch {
            Write-Warning "Failed to download legacy uninstaller: $($_.Exception.Message)"
        }
    }
    if (Test-Path $setupPath) {
        Start-Process -FilePath $setupPath -ArgumentList "-unattend -uninstall" -Wait -NoNewWindow
    }
}
'@ -replace "VALUE_MSMPI_EXE_PATH", $msmpiExePath

    $UninstallScriptContent | Out-File -FilePath $msmpiUninstallScript -Encoding utf8
    Write-Host "Created: $msmpiUninstallScript" -ForegroundColor Gray
    
    Write-Host "Executing $msmpiUninstallScript..." -ForegroundColor Yellow
    try {
        & $msmpiUninstallScript
    }
    catch {
        Write-Error "Failed to execute the Uninstall script: $($_.Exception.Message)"
    }
    
    Remove-Item $msmpiUninstallScript -Force -ErrorAction SilentlyContinue
    
    # Session variable cleanup
    Get-ChildItem Env:\MSMPI_* | ForEach-Object { Remove-Item Env:\$($_.Name) -ErrorAction SilentlyContinue }
    Get-ChildItem Env:\BINARY_LIB_MSMPI* | ForEach-Object { Remove-Item Env:\$($_.Name) -ErrorAction SilentlyContinue }
    Get-ChildItem Env:\SHARED_LIB_MSMPI* | ForEach-Object { Remove-Item Env:\$($_.Name) -ErrorAction SilentlyContinue }
    
    foreach ($tool in $mpitools) {
        $target = Join-Path $GlobalBinDir $tool
        if (Test-Path $target) { Remove-Item $target -Force -ErrorAction SilentlyContinue; Write-Host "  [REMOVED] Link: $tool" -ForegroundColor Gray }
    }
    
    $CurrentCMakePrefixPath = $env:CMAKE_PREFIX_PATH
    $CleanedCMakePrefixPathList = $CurrentCMakePrefixPath -split ';' | Where-Object { 
        -not [string]::IsNullOrWhitespace($_) -and 
        $_ -notlike "*Microsoft MPI*"
    }
    $NewCMakePrefixPath = ($CleanedCMakePrefixPathList -join ";").Replace(";;", ";")
    $NewCMakePrefixPath = ($NewCMakePrefixPath + ";").Replace(";;", ";")
    $env:CMAKE_PREFIX_PATH = $NewCMakePrefixPath
    
    $CurrentIncludePath = $env:INCLUDE
    $CleanedIncludePathList = $CurrentIncludePath -split ';' | Where-Object { 
        -not [string]::IsNullOrWhitespace($_) -and 
        $_ -notlike "*Microsoft MPI*"
    }
    $NewIncludePath = ($CleanedIncludePathList -join ";").Replace(";;", ";")
    $NewIncludePath = ($NewIncludePath + ";").Replace(";;", ";")
    $env:INCLUDE = $NewIncludePath
    
    $CurrentLibPath = $env:LIB
    $CleanedLibPathList = $CurrentLibPath -split ';' | Where-Object { 
        -not [string]::IsNullOrWhitespace($_) -and 
        $_ -notlike "*Microsoft MPI*"
    }
    $NewLibPath = ($CleanedLibPathList -join ";").Replace(";;", ";")
    $NewLibPath = ($NewLibPath + ";").Replace(";;", ";")
    $env:LIB = $NewLibPath
    
    $CurrentPath = $env:PATH
    $CleanedPathList = $CurrentPath -split ';' | Where-Object { 
        -not [string]::IsNullOrWhitespace($_) -and 
        $_ -notlike "*Microsoft MPI*"
    }
    $NewPath = ($CleanedPathList -join ";").Replace(";;", ";")
    $NewPath = ($NewPath + ";").Replace(";;", ";")
    $env:PATH = $NewPath
    
    Write-Host "--- MS-MPI Purge Complete ---" -ForegroundColor Green
}

$localVersion = "0.0.0"
$rawVersion = "0.0.0"
$binaryversion = "0"

if (Test-Path $msmpiExePath) {
    $rawVersion = (& $msmpiExePath -help | Select-String "Version").ToString().Trim()
    if ($rawVersion -match 'Version\s+(\d+\.\d+(\.\d+)?)') { $localVersion = $Matches[1] }
}

if (Test-Path $versionFile) {
    $localVersion = (Get-Content $versionFile | ConvertFrom-Json).version
}

if ($msmpiForceCleanup) {
    Invoke-MSMPIVersionPurge
    $localVersion = "0.0.0"
}

function Save-MSMPIVersionInfo {
    param([hashtable]$versionInfo, [string]$versionFile, [string]$msmpiSdkPath)
    
    $writeVersionScript = Join-Path $env:TEMP "write-msmpi-version.ps1"
    $jsonString = $versionInfo | ConvertTo-Json
    
    $ScriptContent = @"
`$IsAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not `$IsAdmin) {
    `$Arguments = "-NoProfile -ExecutionPolicy Bypass -File ``"`$PSCommandPath``""
    try { Start-Process pwsh.exe -ArgumentList `$Arguments -Verb RunAs -Wait }
    catch { Start-Process powershell.exe -ArgumentList `$Arguments -Verb RunAs -Wait }
    exit
}
if (-not (Test-Path '$msmpiSdkPath')) { New-Item -Path '$msmpiSdkPath' -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null }
`$jsonContent = @'
$jsonString
'@
`$jsonContent | Out-File -FilePath '$versionFile' -Encoding utf8 -Force
"@
    $ScriptContent | Out-File -FilePath $writeVersionScript -Encoding utf8
    & $writeVersionScript
    Remove-Item $writeVersionScript -Force -ErrorAction SilentlyContinue
}

# --- 2. Install or Skip ---
function Install-Or-Update-MSMPI {
    Write-Host "--- MS-MPI Provisioning ---" -ForegroundColor Cyan
    
    $msmpiInstallScript = Join-Path $env:TEMP "install-msmpi.ps1"
    
    $InstallScriptContent = @'
# MS-MPI Install Script

# --- 0. Self-Elevation Logic ---
$IsAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $IsAdmin) {
    Write-Host "Elevation required to install MS-MPI. Relaunching as Administrator..." -ForegroundColor Yellow
    $Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    try {
        Start-Process pwsh.exe -ArgumentList $Arguments -Verb RunAs -Wait
    }
    catch {
        Start-Process powershell.exe -ArgumentList $Arguments -Verb RunAs -Wait
    }
    exit
}

$success = $false
if (Get-Command winget -ErrorAction SilentlyContinue) {
    Write-Host "Processing MS-MPI Runtime via WinGet..." -ForegroundColor Gray
    winget install --id Microsoft.msmpi --source winget --silent --accept-package-agreements --accept-source-agreements 2>&1 | Out-Null
    $exit1 = $LASTEXITCODE
    
    Write-Host "Processing MS-MPI SDK via WinGet..." -ForegroundColor Gray
    winget install --id Microsoft.msmpisdk --source winget --silent --accept-package-agreements --accept-source-agreements 2>&1 | Out-Null
    $exit2 = $LASTEXITCODE
    
    $validExits = @(0, -1978335178, -1978335189)
    if (($validExits -contains $exit1) -and ($validExits -contains $exit2)) {
        Write-Host "[SUCCESS] MS-MPI provisioned via WinGet." -ForegroundColor Green
        $success = $true

        # The MS-MPI installer aggressively prepends its Bin directory to the Machine PATH.
        # Remove it to maintain isolated environments.
        Write-Host "Scrubbing MS-MPI from Machine PATH..." -ForegroundColor Cyan
        $RegPath = "System\CurrentControlSet\Control\Session Manager\Environment"
        $RegKey = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey($RegPath, $true)
        $CurrentRawPath = $RegKey.GetValue("Path", "", [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
        $CleanedPathList = $CurrentRawPath -split ';' | Where-Object { 
            -not [string]::IsNullOrWhitespace($_) -and 
            $_ -notlike "*Microsoft MPI\Bin*"
        }
        $NewRawPath = ($CleanedPathList -join ";").Replace(";;", ";")
        $NewRawPath = ($NewRawPath + ";").Replace(";;", ";")
        $RegKey.SetValue("Path", $NewRawPath, [Microsoft.Win32.RegistryValueKind]::ExpandString)
        $RegKey.Close()
        Write-Host "[CLEANED] Default MS-MPI entries removed from standard Windows Path." -ForegroundColor Gray
    }
}

if (-not $success) {
    Write-Error "WinGet not found or failed to install MS-MPI. Please check your WinGet installation or manually install Microsoft MPI."
    Start-Sleep -Seconds 5
}
'@

    $InstallScriptContent | Out-File -FilePath $msmpiInstallScript -Encoding utf8
    Write-Host "Created: $msmpiInstallScript" -ForegroundColor Gray
    
    Write-Host "Executing $msmpiInstallScript..." -ForegroundColor Yellow
    try {
        & $msmpiInstallScript
    }
    catch {
        Write-Error "Failed to execute the Install script: $($_.Exception.Message)"
    }
    
    Remove-Item $msmpiInstallScript -Force -ErrorAction SilentlyContinue
}

$vLocal = [version]"0.0.0"
$vRemote = [version]"0.0.0"

if ($localVersion -match '^(\d+\.\d+(\.\d+)?)') { $vLocal = [version]($localVersion -replace '#.*', '') }
if ($remoteVersion -match '^(\d+\.\d+(\.\d+)?)') { $vRemote = [version]($remoteVersion -replace '#.*', '') }

if ($vLocal -ge $vRemote -and $localVersion -ne "0.0.0") {
    Write-Host "[SKIP] MS-MPI $localVersion is already installed and up to date at: $msmpiSdkPath" -ForegroundColor Green

    $msmpiVersion = $localVersion
    $binaryversion = ([version]$localVersion).Major
    if (-not (Test-Path $versionFile)) {
        $versionInfo = @{
            url        = $url;
            tag_name   = $tag_name;
            commit     = $tagCommit;
            version    = $localVersion;
            rawversion = $rawVersion;
            abiversion = $binaryversion;
            soversion  = $binaryversion;
            date       = (Get-Date).ToString("yyyy-MM-dd");
            updated_at = $updated_at;
            type       = "build_tool";
        }
        Save-MSMPIVersionInfo -versionInfo $versionInfo -versionFile $versionFile -msmpiSdkPath $msmpiSdkPath
    }
} else {
    Write-Host "[UPDATE] Local: $localVersion -> Remote: $remoteVersion" -ForegroundColor Yellow
    
    Install-Or-Update-MSMPI

    $msmpiVersion = $remoteVersion
    $binaryversion = ([version]$remoteVersion).Major
    if (Test-Path $msmpiExePath) {
        $rawVersion = (& $msmpiExePath -help | Select-String "Version").ToString().Trim()
    }
    
    $versionInfo = @{
        url        = $url;
        tag_name   = $tag_name;
        commit     = $tagCommit;
        version    = $remoteVersion;
        rawversion = $rawVersion;
        abiversion = $binaryversion;
        soversion  = $binaryversion;
        date       = (Get-Date).ToString("yyyy-MM-dd");
        updated_at = $updated_at;
        type       = "build_tool";
    }
    Save-MSMPIVersionInfo -versionInfo $versionInfo -versionFile $versionFile -msmpiSdkPath $msmpiSdkPath
}

# Finalize Environment Helper
if (Test-Path $msmpiExePath) {
    # Generate Environment Helper with Clean Paths
    $msmpiBinPath = $msmpiBinPath.TrimEnd('\')
    $msmpiIncludeDir = $msmpiIncludeDir.TrimEnd('\')
    $msmpiLibDir = $msmpiLibDir.TrimEnd('\')
    $msmpiCMakePath = $msmpiSdkPath.Replace('\', '/')
    
    $msmpiLibName = "msmpi"
    
    $SharedLib = Join-Path $msmpiLibDir "msmpi.lib"
    $BinaryLib = Join-Path $msmpiBinPath "msmpi.dll"
    if (-not (Test-Path $BinaryLib)) { $BinaryLib = Join-Path $env:windir "System32\msmpi.dll" }
    
    # --- 3. Create Environment Helper ---
    Write-Host "Generating environment helper script..." -ForegroundColor Cyan

    $EnvContent = @'
# MS-MPI Environment Setup
$msmpiroot = "VALUE_ROOT_PATH"
$msmpiinclude = "VALUE_INCLUDE_PATH"
$msmpilibrary = "VALUE_LIB_PATH"
$msmpibin = "VALUE_BIN_PATH"
$msmpiversion = "VALUE_VERSION"
$msmpiabiversion = "VALUE_ABI_VERSION"
$msmpisoversion = "VALUE_SO_VERSION"
$msmpibinary = "VALUE_BINARY"
$msmpishared = "VALUE_SHARED"
$msmpilibname = "VALUE_LIB_NAME"
$msmpicmakepath = "VALUE_CMAKE_PATH"
$env:MSMPI_PATH = $msmpiroot
$env:MSMPI_ROOT = $msmpiroot
$env:MSMPI_BIN = $msmpibin
$env:MSMPI_INC = $msmpiinclude
$env:MSMPI_LIB64 = $msmpilibrary
$env:MSMPI_INCLUDE_DIR = $msmpiinclude
$env:MSMPI_LIBRARY_DIR = $msmpilibrary
$env:BINARY_LIB_MSMPI = $msmpibinary
$env:SHARED_LIB_MSMPI = $msmpishared
$env:MSMPI_LIB_NAME = $msmpilibname
$env:MSMPI_VERSION = $msmpiversion
$env:MSMPI_MAJOR = ([version]$msmpiversion).Major
$env:MSMPI_MINOR = ([version]$msmpiversion).Minor
$env:MSMPI_PATCH = ([version]$msmpiversion).Patch
$env:MSMPI_ABI_VERSION = $msmpiabiversion
$env:MSMPI_SO_VERSION = $msmpisoversion
if ($env:CMAKE_PREFIX_PATH -notlike "*$msmpicmakepath*") { $env:CMAKE_PREFIX_PATH = $msmpicmakepath + ";" + $env:CMAKE_PREFIX_PATH; $env:CMAKE_PREFIX_PATH = ($env:CMAKE_PREFIX_PATH).Replace(";;", ";") }
if ($env:INCLUDE -notlike "*$msmpiinclude*") { $env:INCLUDE = $msmpiinclude + ";" + $env:INCLUDE; $env:INCLUDE = ($env:INCLUDE).Replace(";;", ";") }
if ($env:LIB -notlike "*$msmpilibrary*") { $env:LIB = $msmpilibrary + ";" + $env:LIB; $env:LIB = ($env:LIB).Replace(";;", ";") }
if ($env:PATH -notlike "*$msmpibin*") { $env:PATH = $msmpibin + ";" + $env:PATH; $env:PATH = ($env:PATH).Replace(";;", ";") }
Write-Host "MS-MPI Environment Loaded (Version: $msmpiversion) (Bin: $msmpibin)" -ForegroundColor Green
Write-Host "MSMPI_ROOT: $env:MSMPI_ROOT" -ForegroundColor Gray
'@  -replace "VALUE_INCLUDE_PATH", $msmpiIncludeDir `
    -replace "VALUE_ROOT_PATH", $msmpiSdkPath `
    -replace "VALUE_LIB_PATH", $msmpiLibDir `
    -replace "VALUE_BIN_PATH", $msmpiBinPath `
    -replace "VALUE_VERSION", $msmpiVersion `
    -replace "VALUE_ABI_VERSION", $binaryversion `
    -replace "VALUE_SO_VERSION", $binaryversion `
    -replace "VALUE_SHARED", $SharedLib `
    -replace "VALUE_BINARY", $BinaryLib `
    -replace "VALUE_LIB_NAME", $msmpiLibName `
    -replace "VALUE_CMAKE_PATH", $msmpiCMakePath

    $EnvContent | Out-File -FilePath $msmpiEnvScript -Encoding utf8
    Write-Host "Created: $msmpiEnvScript" -ForegroundColor Gray
    
    # Update Current Session
    if (Test-Path $msmpiEnvScript) { . $msmpiEnvScript } else {
        Write-Error "MS-MPI install finished but $msmpiEnvScript was not created."
        return
    }

    # --- Symlinks for standard MPI commands ---
    Write-Host "Creating global symlinks to: $GlobalBinDir..." -ForegroundColor Cyan
    foreach ($tool in $mpitools) {
        $source = Join-Path $msmpiBinPath $tool
        $target = Join-Path $GlobalBinDir $tool
        if (Test-Path $source) {
            if (Test-Path $target) { Remove-Item $target -Force -ErrorAction SilentlyContinue }
            try {
                New-Item -Path $target -ItemType SymbolicLink -Value $source -ErrorAction Stop | Out-Null
                Write-Host "[LINKED] $tool" -ForegroundColor Gray
            } catch {
                New-Item -Path $target -ItemType HardLink -Value $source | Out-Null
            }
        }
    }
    Write-Host "[LINKED] MS-MPI is now globally available via %BINARIES_PATH%" -ForegroundColor Green
    
    if ($msmpiWithMachineEnvironment)
    {
        # Generating Machine Environment
        $MachineEnvContent = @'
# MS-MPI Machine Environment Setup

# --- 0. Self-Elevation Logic ---
$IsAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$ScopeColor = "Cyan"

if (-not $IsAdmin) {
    Write-Host "Elevation required to set MS-MPI system variables. Relaunching as Administrator..." -ForegroundColor Yellow
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

$msmpiroot = "VALUE_ROOT_PATH"
$msmpiinc = "VALUE_INCLUDE_PATH"
$msmpilib = "VALUE_LIB_PATH"
$msmpibin = "VALUE_BIN_PATH"
$msmpiversion = "VALUE_VERSION"

$TargetScope = "Machine"
$RegPath = "System\CurrentControlSet\Control\Session Manager\Environment"
$RegRoot = "LocalMachine"

$RegKey = [Microsoft.Win32.Registry]::$RegRoot.OpenSubKey($RegPath, $true)

[Environment]::SetEnvironmentVariable("MSMPI_INC", $msmpiinc, $TargetScope)
[Environment]::SetEnvironmentVariable("MSMPI_LIB64", $msmpilib, $TargetScope)

$CurrentRawPath = $RegKey.GetValue("EXTCOMP_PATH", "", [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)

# Cleanup: Remove empty strings, any path containing $msmpibin, and the current target (to avoid dups)
$CleanedPathList = $CurrentRawPath -split ';' | Where-Object { 
    -not [string]::IsNullOrWhitespace($_) -and 
    $_ -notlike "*$msmpibin*"
}

$NewRawPath = ($CleanedPathList -join ";").Replace(";;", ";")

$TargetPath = $msmpibin

# Rebuild
$NewRawPath = ($NewRawPath + ";" + $TargetPath + ";").Replace(";;", ";")
Write-Host "[UPDATED] ($TargetScope) '$msmpibin' synced in EXTCOMP_PATH" -ForegroundColor $ScopeColor

$RegKey.SetValue("EXTCOMP_PATH", $NewRawPath, [Microsoft.Win32.RegistryValueKind]::ExpandString)
$env:EXTCOMP_PATH = $NewRawPath

$RegKey.Close()

$env:MSMPI_ROOT = $msmpiroot
Write-Host "MS-MPI Environment Loaded (Version: $msmpiversion) (Bin: $msmpibin)" -ForegroundColor Green
Write-Host "MSMPI_ROOT: $env:MSMPI_ROOT" -ForegroundColor Gray
'@  -replace "VALUE_INCLUDE_PATH", $msmpiIncludeDir `
    -replace "VALUE_ROOT_PATH", $msmpiInstallDir `
    -replace "VALUE_LIB_PATH", $msmpiLibDir `
    -replace "VALUE_BIN_PATH", $msmpiBinPath `
    -replace "VALUE_VERSION", $msmpiVersion

        $MachineEnvContent | Out-File -FilePath $msmpiMachineEnvScript -Encoding utf8
        Write-Host "Created: $msmpiMachineEnvScript" -ForegroundColor Gray
        
        # --- Interaction: Prompt to apply persistent changes ---
        Write-Host ""
        $choice = Read-Host "Do you want to run the Machine Environment script now to persist MS-MPI changes to the Registry? (y/n)"
        if ($choice -eq 'y' -or $choice -eq 'Y') {
            Write-Host "Executing $msmpiMachineEnvScript..." -ForegroundColor Yellow
            try {
                & $msmpiMachineEnvScript
            }
            catch {
                Write-Error "Failed to execute the Machine Environment script: $($_.Exception.Message)"
            }
        }
        else {
            Write-Host "Skipped persistent registry update. You can run it later at: $msmpiMachineEnvScript" -ForegroundColor Gray
        }
    }
} else {
    Write-Error "mpiexec.exe was not found in the $msmpiBinPath folder."
    return
}
