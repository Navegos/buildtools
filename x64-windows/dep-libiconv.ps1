# SPDX-FileCopyrightText: Copyright (c) 2026 Navegos. @DevelVitorF. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
# project: buildtools
# file: x64-windows/dep-libiconv.ps1
# created: 2026-03-07
# lastModified: 2026-04-26

param (
    [Parameter(HelpMessage = "Target vcpkg LIBICONV triplet")]
    [string]$Triplet = "x64-windows",
    
    [Parameter(HelpMessage = "Force a full purge of the local LIBICONV version before continuing", Mandatory = $false)]
    [switch]$forceCleanup,
    
    [Parameter(HelpMessage = "Add's LIBICONV Machine Environment Variables. Requires Machine Administrator Rights.", Mandatory = $false)]
    [switch]$withMachineEnvironment
)

# Capture parameters
$libiconvWithMachineEnvironment = $withMachineEnvironment
$libiconvForceCleanup = $forceCleanup

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
if ([string]::IsNullOrWhitespace($env:BINARY_VCPKG) -or -not (Test-Path $env:BINARY_VCPKG)) {
    $vcpkgEnvScript = Join-Path $EnvironmentDir "env-vcpkg.ps1"
    if (Test-Path $vcpkgEnvScript) { . $vcpkgEnvScript }
    if ([string]::IsNullOrWhitespace($env:BINARY_VCPKG) -or -not (Test-Path $env:BINARY_VCPKG)) {
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
$libiconvEnvScript = Join-Path $EnvironmentDir "env-libiconv.ps1"
$libiconvMachineEnvScript = Join-Path $EnvironmentDir "machine-env-libiconv.ps1"

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

    if ($libiconvWithMachineEnvironment) {
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

$libiconvbinpath = "VALUE_ICONV_BIN_PATH"
$libiconvtoolsbinpath = "VALUE_ICONV_TOOLS_BIN_PATH"

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
'@  -replace "VALUE_ICONV_TOOLS_BIN_PATH", $libiconvToolsBinInstallPath -replace "VALUE_ICONV_BIN_PATH", $libiconvBinInstallPath

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

    # 2. Filesystem Clean (Requires checking for locked files)
    # delete everithing we create don't fail later
    if (Test-Path $libiconvEnvScript) {
        Write-Host "  [DELETING] $libiconvEnvScript" -ForegroundColor Yellow
        Remove-Item $libiconvEnvScript -Recurse -Force -ErrorAction SilentlyContinue
    }
    if (Test-Path $libiconvMachineEnvScript) {
        Write-Host "  [DELETING] $libiconvMachineEnvScript" -ForegroundColor Yellow
        Remove-Item $libiconvMachineEnvScript -Recurse -Force -ErrorAction SilentlyContinue
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
    
    # remove local Env variables for current session
    Get-ChildItem Env:\ICONV_PATH* | Remove-Item -ErrorAction SilentlyContinue
    Get-ChildItem Env:\ICONV_ROOT* | Remove-Item -ErrorAction SilentlyContinue
    Get-ChildItem Env:\ICONV_BIN* | Remove-Item -ErrorAction SilentlyContinue
    Get-ChildItem Env:\ICONV_TOOLS_BIN* | Remove-Item -ErrorAction SilentlyContinue
    Get-ChildItem Env:\ICONV_INCLUDE_DIR* | Remove-Item -ErrorAction SilentlyContinue
    Get-ChildItem Env:\ICONV_LIBRARY_DIR* | Remove-Item -ErrorAction SilentlyContinue
    Get-ChildItem Env:\BINARY_LIB_ICONV* | Remove-Item -ErrorAction SilentlyContinue
    Get-ChildItem Env:\SHARED_LIB_ICONV* | Remove-Item -ErrorAction SilentlyContinue
    Get-ChildItem Env:\BINARY_LIB_CHARSET* | Remove-Item -ErrorAction SilentlyContinue
    Get-ChildItem Env:\SHARED_LIB_CHARSET* | Remove-Item -ErrorAction SilentlyContinue
    Get-ChildItem Env:\ICONV_LIB_NAME* | Remove-Item -ErrorAction SilentlyContinue
    Get-ChildItem Env:\CHARSET_LIB_NAME* | Remove-Item -ErrorAction SilentlyContinue
    Get-ChildItem Env:\ICONV_VERSION* | Remove-Item -ErrorAction SilentlyContinue
    Get-ChildItem Env:\ICONV_MAJOR* | Remove-Item -ErrorAction SilentlyContinue
    Get-ChildItem Env:\ICONV_MINOR* | Remove-Item -ErrorAction SilentlyContinue
    Get-ChildItem Env:\ICONV_PATCH* | Remove-Item -ErrorAction SilentlyContinue
    Get-ChildItem Env:\ICONV_ABI_VERSION* | Remove-Item -ErrorAction SilentlyContinue
    Get-ChildItem Env:\ICONV_SO_VERSION* | Remove-Item -ErrorAction SilentlyContinue
    Get-ChildItem Env:\CHARSET_ABI_VERSION* | Remove-Item -ErrorAction SilentlyContinue
    Get-ChildItem Env:\CHARSET_SO_VERSION* | Remove-Item -ErrorAction SilentlyContinue
    
    $CurrentCMakePrefixPath = $env:CMAKE_PREFIX_PATH
    $CleanedCMakePrefixPathList = $CurrentCMakePrefixPath -split ';' | Where-Object { 
        -not [string]::IsNullOrWhitespace($_) -and 
        $_ -notlike "*$InstallPath*"
    }
    $NewCMakePrefixPath = ($CleanedCMakePrefixPathList -join ";").Replace(";;", ";")
    $NewCMakePrefixPath = ($NewCMakePrefixPath + ";").Replace(";;", ";")
    $env:CMAKE_PREFIX_PATH = $NewCMakePrefixPath
    
    $CurrentIncludePath = $env:INCLUDE
    $CleanedIncludePathList = $CurrentIncludePath -split ';' | Where-Object { 
        -not [string]::IsNullOrWhitespace($_) -and 
        $_ -notlike "*$InstallPath*"
    }
    $NewIncludePath = ($CleanedIncludePathList -join ";").Replace(";;", ";")
    $NewIncludePath = ($NewIncludePath + ";").Replace(";;", ";")
    $env:INCLUDE = $NewIncludePath
    
    $CurrentLibPath = $env:LIB
    $CleanedLibPathList = $CurrentLibPath -split ';' | Where-Object { 
        -not [string]::IsNullOrWhitespace($_) -and 
        $_ -notlike "*$InstallPath*"
    }
    $NewLibPath = ($CleanedLibPathList -join ";").Replace(";;", ";")
    $NewLibPath = ($NewLibPath + ";").Replace(";;", ";")
    $env:LIB = $NewLibPath
    
    $CurrentPath = $env:PATH
    $CleanedPathList = $CurrentPath -split ';' | Where-Object { 
        -not [string]::IsNullOrWhitespace($_) -and 
        $_ -notlike "*$InstallPath*"
    }
    $NewPath = ($CleanedPathList -join ";").Replace(";;", ";")
    $NewPath = ($NewPath + ";").Replace(";;", ";")
    $env:PATH = $NewPath
    
    Write-Host "--- LIBICONV Purge Complete ---" -ForegroundColor Green
}

$libiconvLibName = "iconv"

# Fix this using vcpkg to get LIBICONV version
$localVersion = "0.0.0"
$rawVersion = "0.0.0"
$binaryversion = "0"

if (Test-Path (Join-Path $libiconvLibDir "$libiconvLibName.lib")) {
    $rawVersion = (vcpkg list libiconv:$Triplet | Select-Object -First 1).Trim()
    if ($rawVersion -match '^(\d+\.\d+(\.\d+)?)') { $localVersion = $Matches[1] }
}

if (Test-Path $versionFile) {
    $localVersion = (Get-Content $versionFile | ConvertFrom-Json).version
}

if ($libiconvForceCleanup) {
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
            charsetabiversion = $binaryversion;
            charsetsoversion  = $binaryversion;
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
    $binaryversion = ([version]$remoteVersion).Major
    if (Test-Path (Join-Path $libiconvLibDir "$libiconvLibName.lib")) {
        $rawVersion = (vcpkg list libiconv:$Triplet | Select-Object -First 1).Trim()
    }
    $versionInfo = @{
        url        = $url;
        tag_name   = $tag_name;
        commit     = $tagCommit;
        version    = $remoteVersion;
        rawversion = $rawVersion;
        abiversion = $binaryversion;
        soversion  = $binaryversion;
        charsetabiversion = $binaryversion;
        charsetsoversion  = $binaryversion;
        date       = (Get-Date).ToString("yyyy-MM-dd");
        updated_at = $updated_at;
        type       = "build_tool";
    }
    $versionInfo | ConvertTo-Json | Out-File -FilePath $versionFile -Encoding utf8 -Force
}

# Finalize Environment Helper
if (Test-Path (Join-Path $libiconvLibDir "$libiconvLibName.lib")) {
    # Generate Environment Helper with Clean Paths
    $libiconvInstallDir = $libiconvInstallDir.TrimEnd('\')
    $libiconvIncludeDir = $libiconvIncludeDir.TrimEnd('\')
    $libiconvLibDir     = $libiconvLibDir.TrimEnd('\')
    $libiconvBinPath    = $libiconvBinPath.TrimEnd('\')
    $libiconvToolsBinPath = $libiconvToolsBinPath.TrimEnd('\')
    $libiconvCMakePath  = $libiconvInstallDir.Replace('\', '/')
    
    $libName = $libiconvLibName
    $charsetName = "charset"
    $iconvAbi = "0"
    $charsetAbi = "0"

    # Detect iconv ABI (usually 2)
    $iconvDll = Get-ChildItem -Path $libiconvBinPath -Filter "$libName-*.dll" | Select-Object -First 1
    if ($iconvDll.Name -match "-(\d+)\.dll$") {
        $iconvAbi = $matches[1]
    }
    
    # Detect charset ABI (usually 1)
    $charsetDll = Get-ChildItem -Path $libiconvBinPath -Filter "$charsetName-*.dll" | Select-Object -First 1
    if ($charsetDll.Name -match "-(\d+)\.dll$") {
        $charsetAbi = $matches[1]
    }

    $versionInfo.abiversion = $iconvAbi
    $versionInfo.soversion = $iconvAbi
    $versionInfo.charsetabiversion = $charsetAbi
    $versionInfo.charsetsoversion = $charsetAbi

    $versionInfo | ConvertTo-Json | Out-File -FilePath $versionFile -Encoding utf8 -Force

    $SharedLib = Join-Path $libiconvLibDir "$libName.lib"
    $BinaryLib = Join-Path $libiconvBinPath "$libName-$iconvAbi.dll"
    
    $SharedCharsetLib = Join-Path $libiconvLibDir "$charsetName.lib"
    $BinaryCharsetLib = Join-Path $libiconvBinPath "$charsetName-$charsetAbi.dll"

    # --- 3. Create Environment Helper ---
    Write-Host "Generating environment helper script..." -ForegroundColor Cyan

    # Using a literal here-string with -replace to avoid accidental expansion of $env:PATH during creation
    $EnvContent = @'
# LIBICONV Environment Setup
$libiconvroot = "VALUE_ROOT_PATH"
$libiconvinclude = "VALUE_INCLUDE_PATH"
$libiconvlibrary = "VALUE_LIB_PATH"
$libiconvbin = "VALUE_BIN_PATH"
$libiconvtoolsbin = "VALUE_TOOLS_BIN_PATH"
$libiconvversion = "VALUE_VERSION"
$libiconvabiversion = "VALUE_ABI_VERSION"
$libiconvsoversion = "VALUE_SO_VERSION"
$charsetabiversion = "VALUE_CHARSET_ABI_VERSION"
$charsetsoversion = "VALUE_CHARSET_SO_VERSION"
$libiconvbinary = "VALUE_BINARY"
$libiconvshared = "VALUE_SHARED"
$charsetbinary = "VALUE_CHARSET_BINARY"
$charsetshared = "VALUE_CHARSET_SHARED"
$libiconvlibname = "VALUE_LIB_NAME"
$charsetlibname = "VALUE_CHARSET_LIB_NAME"
$libiconvcmakepath = "VALUE_CMAKE_PATH"
$env:ICONV_PATH = $libiconvroot
$env:ICONV_ROOT = $libiconvroot
$env:ICONV_BIN = $libiconvbin
$env:ICONV_TOOLS_BIN = $libiconvtoolsbin
$env:ICONV_INCLUDE_DIR = $libiconvinclude
$env:ICONV_LIBRARY_DIR = $libiconvlibrary
$env:BINARY_LIB_ICONV = $libiconvbinary
$env:SHARED_LIB_ICONV = $libiconvshared
$env:BINARY_LIB_CHARSET = $charsetbinary
$env:SHARED_LIB_CHARSET = $charsetshared
$env:ICONV_LIB_NAME = $libiconvlibname
$env:CHARSET_LIB_NAME = $charsetlibname
$env:ICONV_VERSION = $libiconvversion
$env:ICONV_MAJOR = ([version]$libiconvversion).Major
$env:ICONV_MINOR = ([version]$libiconvversion).Minor
$env:ICONV_PATCH = ([version]$libiconvversion).Patch
$env:ICONV_ABI_VERSION = $libiconvabiversion
$env:ICONV_SO_VERSION = $libiconvsoversion
$env:CHARSET_ABI_VERSION = $charsetabiversion
$env:CHARSET_SO_VERSION = $charsetsoversion
if ($env:CMAKE_PREFIX_PATH -notlike "*$libiconvcmakepath*") { $env:CMAKE_PREFIX_PATH = $libiconvcmakepath + ";" + $env:CMAKE_PREFIX_PATH; $env:CMAKE_PREFIX_PATH = ($env:CMAKE_PREFIX_PATH).Replace(";;", ";") }
if ($env:INCLUDE -notlike "*$libiconvinclude*") { $env:INCLUDE = $libiconvinclude + ";" + $env:INCLUDE; $env:INCLUDE = ($env:INCLUDE).Replace(";;", ";") }
if ($env:LIB -notlike "*$libiconvlibrary*") { $env:LIB = $libiconvlibrary + ";" + $env:LIB; $env:LIB = ($env:LIB).Replace(";;", ";") }
"$libiconvbin", "$libiconvtoolsbin" | ForEach-Object { if ($env:PATH -notlike "*$_*") { $env:PATH = $_ + ";" + $env:PATH; $env:PATH = ($env:PATH).Replace(";;", ";") } }
Write-Host "LIBICONV Environment Loaded (Version: $libiconvversion) (Bin: $libiconvbin)" -ForegroundColor Green
Write-Host "ICONV_ROOT: $env:ICONV_ROOT" -ForegroundColor Gray
'@  -replace "VALUE_ROOT_PATH", $libiconvInstallDir `
    -replace "VALUE_INCLUDE_PATH", $libiconvIncludeDir `
    -replace "VALUE_LIB_PATH", $libiconvLibDir `
    -replace "VALUE_BIN_PATH", $libiconvBinPath `
    -replace "VALUE_TOOLS_BIN_PATH", $libiconvToolsBinPath `
    -replace "VALUE_VERSION", $libiconvVersion `
    -replace "VALUE_ABI_VERSION", $iconvAbi `
    -replace "VALUE_SO_VERSION", $iconvAbi `
    -replace "VALUE_CHARSET_ABI_VERSION", $charsetAbi `
    -replace "VALUE_CHARSET_SO_VERSION", $charsetAbi `
    -replace "VALUE_SHARED", $SharedLib `
    -replace "VALUE_BINARY", $BinaryLib `
    -replace "VALUE_CHARSET_SHARED", $SharedCharsetLib `
    -replace "VALUE_CHARSET_BINARY", $BinaryCharsetLib `
    -replace "VALUE_LIB_NAME", $libName `
    -replace "VALUE_CHARSET_LIB_NAME", $charsetName `
    -replace "VALUE_CMAKE_PATH", $libiconvCMakePath

    $EnvContent | Out-File -FilePath $libiconvEnvScript -Encoding utf8
    Write-Host "Created: $libiconvEnvScript" -ForegroundColor Gray
    
    # Update Current Session
    if (Test-Path $libiconvEnvScript) { . $libiconvEnvScript } else {
        Write-Error "libiconv dep install finished but $libiconvEnvScript was not created."
        return
    }
    Write-Host "libiconv Version: $(vcpkg list libiconv:$Triplet | Select-Object -First 1)" -ForegroundColor Gray
    
    if ($libiconvWithMachineEnvironment)
    {
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

$env:ICONV_ROOT = $libiconvroot
Write-Host "libiconv Environment Loaded (Version: $libiconvversion) (Bin: $libiconvtoolsbin)" -ForegroundColor Green
Write-Host "ICONV_ROOT: $env:ICONV_ROOT" -ForegroundColor Gray
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
