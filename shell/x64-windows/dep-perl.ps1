# SPDX-FileCopyrightText: Copyright (c) 2026 Navegos. @DevelVitorF. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
# project: buildtools
# file: x64-windows/dep-perl.ps1
# created: 2026-05-01
# lastModified: 2026-05-11

param (
    [Parameter(HelpMessage = "Path for Perl storage", Mandatory = $false)]
    [string]$perlInstallDir = "$env:LIBRARIES_PATH\strawberry",

    [Parameter(HelpMessage = "Force a full purge of the local Perl version before continuing", Mandatory = $false)]
    [switch]$forceCleanup,
    
    [Parameter(HelpMessage = "Add's Perl Machine Environment Variables. Requires Machine Administrator Rights.", Mandatory = $false)]
    [switch]$withMachineEnvironment
)

# Capture parameters
$PerlWithMachineEnvironment = $withMachineEnvironment
$PerlForceCleanup = $forceCleanup

if ([string]::IsNullOrWhitespace($env:ENVIRONMENT_PATH) -or -not (Test-Path $env:ENVIRONMENT_PATH) -or [string]::IsNullOrWhitespace($env:BINARIES_PATH) -or -not (Test-Path $env:BINARIES_PATH) -or [string]::IsNullOrWhitespace($env:LIBRARIES_PATH) -or -not (Test-Path $env:LIBRARIES_PATH) -or [string]::IsNullOrWhitespace($env:BUILDTOOLS_PATH) -or -not (Test-Path $env:BUILDTOOLS_PATH)) {
    Write-Error "User Environment variables missing. Please run add-user-paths.ps1 -LibrariesDir 'Path/for/Libraries' -BinariesDir 'Path/for/Binaries' -EnvironmentDir 'Path/for/Environment' -BuildToolsDir 'Path/for/BuildTools'"
    return
}

$EnvironmentDir = "$env:ENVIRONMENT_PATH"

# if Symlink present delete
$GlobalBinDir = "$env:BINARIES_PATH"
$perltools = @("perl.exe", "wperl.exe", "parl.exe", "parldyn.exe", "perldoc.bat", "cpan.bat", "cpan2dist.bat", "cpanm.bat", "cpan-outdated.bat", "cpanp.bat", "cpanp-run-perl.bat")
foreach ($perltool in $perltools) {
    $target = Join-Path $GlobalBinDir $perltool
    if (Test-Path $target) { Remove-Item $target -Force -ErrorAction SilentlyContinue }
}

$perlBinPath = Join-Path $perlInstallDir "perl\bin"
$perlSiteBinPath = Join-Path $perlInstallDir "perl\site\bin"
$perlCBinPath = Join-Path $perlInstallDir "c\bin"
$perlExePath = Join-Path $perlBinPath "perl.exe"
$versionFile = Join-Path $perlInstallDir "version.json"
$perlEnvScript = Join-Path $EnvironmentDir "env-perl.ps1"
$perlMachineEnvScript = Join-Path $EnvironmentDir "machine-env-perl.ps1"

# Version Detection
$repo = "StrawberryPerl/Perl-Dist-Strawberry"
try {
    Write-Host "Fetching latest Strawberry Perl release from GitHub..." -ForegroundColor Gray
    $latestRelease = Invoke-RestMethod -Uri "https://api.github.com/repos/$repo/releases/latest"
    $url = $latestRelease.url
    $tag_name = $latestRelease.tag_name
    $updated_at = $latestRelease.updated_at
    $remoteVersionString = "$($latestRelease.name) $tag_name"
    $refTags = Invoke-RestMethod -Uri "https://api.github.com/repos/$repo/git/ref/tags/$tag_name"
    $tagCommit = $refTags.object.sha

    $remoteVersion = "0.0.0"
    # Clean remote version for comparison (e.g., "Strawberry Perl 5.42.2.1..." -> "5.42.2.1")
    if ($remoteVersionString -match '(\d+\.\d+\.\d+(\.\d+)?)') { $remoteVersion = $Matches[1] }
    
    $asset = $latestRelease.assets | Where-Object { $_.name -match "64bit-portable\.zip$" } | Select-Object -First 1
    if (-not $asset) { throw "Could not find a 64-bit portable zip in the latest release." }
    
    $downloadUrl = $asset.browser_download_url
} catch {
    Write-Warning "Could not connect to GitHub. Using 0.0.0 for remote."
    $url = "ERR_CONNECTION_TIMED_OUT"
    $tag_name = "0.0.0"
    $updated_at = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssZ")
    $remoteVersion = "0.0.0"
    $tagCommit = "0000000000000000000000000000000000000000"
    $downloadUrl = $null
}

# --- 1. Cleanup Mechanism ---
function Invoke-PerlVersionPurge {
    param ([string]$InstallPath)
    Write-Host "--- Initiating Perl Purge ---" -ForegroundColor Cyan

    if ($PerlWithMachineEnvironment)
    {
        $perlCleanMachineEnvScript = Join-Path $env:TEMP "clean-machine-env-perl.ps1"

        # Generating Clean Machine Environment wich removes the persist registry machine Environment
        $CleanMachineEnvContent = @'
# Perl Clean Machine Environment Setup

# --- 0. Self-Elevation Logic ---
$IsAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$ScopeColor = "Cyan"

if (-not $IsAdmin) {
    Write-Host "Elevation required to clean Perl system variables. Relaunching as Administrator..." -ForegroundColor Yellow
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

$perlroot = "VALUE_ROOT_PATH"

$TargetScope = if ($IsAdmin) { "Machine" } else { "User" }
$RegPath = if ($IsAdmin) { "System\CurrentControlSet\Control\Session Manager\Environment" } else { "Environment" }
$RegRoot = if ($IsAdmin) { "LocalMachine" } else { "CurrentUser" }

# 1. Registry Cleanup (EXTCOMP_PATH)
$RegKey = [Microsoft.Win32.Registry]::$RegRoot.OpenSubKey($RegPath, $true)

# Open the registry key directly to read the RAW (unexpanded) string
$RawPath = $RegKey.GetValue("EXTCOMP_PATH", "", [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)

# Cleanup: Remove empty strings, any path containing $perlroot,
$CleanPath = ($RawPath -split ';' | Where-Object { $_ -notlike "*$perlroot*" }) -join ";"

# Save as ExpandString
$RegKey.SetValue("EXTCOMP_PATH", $CleanPath, [Microsoft.Win32.RegistryValueKind]::ExpandString)
$env:EXTCOMP_PATH = $CleanPath

$RegKey.Close()

Write-Host "[REMOVED] ($TargetScope) all '*$perlroot*' removed from EXTCOMP_PATH" -ForegroundColor $ScopeColor
'@  -replace "VALUE_ROOT_PATH", $InstallPath

        $CleanMachineEnvContent | Out-File -FilePath $perlCleanMachineEnvScript -Encoding utf8
        Write-Host "Created: $perlCleanMachineEnvScript" -ForegroundColor Gray
        
        # --- Interaction: Prompt to remove persistent changes ---
        Write-Host ""
        $choice = Read-Host "Administrator rights required to Clean Machine Environment Perl changes? (y/n)"
        if ($choice -eq 'y' -or $choice -eq 'Y') {
            Write-Host "Executing $perlCleanMachineEnvScript..." -ForegroundColor Yellow
            try {
                # Start the generated script. It handles its own elevation logic.
                & $perlCleanMachineEnvScript
            }
            catch {
                Write-Error "Failed to execute the Clean Machine Environment script: $($_.Exception.Message)"
                return
            }
        }
        else {
            Write-Error "Skipped Clean Machine Environment Perl changes."
            return
        }

        # Cleanup
        Remove-Item $perlCleanMachineEnvScript -Recurse -Force -ErrorAction SilentlyContinue
    }

    # 2. Filesystem Clean (Requires checking for locked files)
    # delete everithing we create don't fail later
    if (Test-Path $perlEnvScript) {
        Write-Host "  [DELETING] $perlEnvScript" -ForegroundColor Yellow
        Remove-Item $perlEnvScript -Recurse -Force -ErrorAction SilentlyContinue
    }
    if (Test-Path $perlMachineEnvScript) {
        Write-Host "  [DELETING] $perlMachineEnvScript" -ForegroundColor Yellow
        Remove-Item $perlMachineEnvScript -Recurse -Force -ErrorAction SilentlyContinue
    }
    if (Test-Path $InstallPath) {
        Write-Host "  [DELETING] $InstallPath" -ForegroundColor Yellow
        Remove-Item $InstallPath -Recurse -Force -ErrorAction SilentlyContinue
    }
    
    foreach ($perltool in $perltools) {
        $target = Join-Path $GlobalBinDir $perltool
        if (Test-Path $target) { Remove-Item $target -Force -ErrorAction SilentlyContinue; Write-Host "  [REMOVED] Link: $perltool" -ForegroundColor Gray }
    }
    
    # remove local Env variables for current session
    Get-ChildItem Env:\PERL_* | ForEach-Object { Remove-Item Env:\$($_.Name) -ErrorAction SilentlyContinue }
    Get-ChildItem Env:\BINARY_PERL* | ForEach-Object { Remove-Item Env:\$($_.Name) -ErrorAction SilentlyContinue }

    $CurrentPath = $env:PATH
    $CleanedPathList = $CurrentPath -split ';' | Where-Object { 
        -not [string]::IsNullOrWhitespace($_) -and 
        $_ -notlike "*$InstallPath*"
    }
    $NewPath = ($CleanedPathList -join ";").Replace(";;", ";")
    $NewPath = ($NewPath + ";").Replace(";;", ";")
    $env:PATH = $NewPath
    
    Write-Host "--- Perl Purge Complete ---" -ForegroundColor Green
}

$localVersion = "0.0.0"
$rawVersion = "0.0.0"
if (Test-Path $perlExePath) {
    $rawVersion = (& $perlExePath --version | Select-String "v\d+\.\d+\.\d+").Matches.Value
    if ($rawVersion -match 'v(\d+\.\d+\.\d+(\.\d+)?)') { $localVersion = $Matches[1] }
}

if (Test-Path $versionFile) {
    $localVersion = (Get-Content $versionFile | ConvertFrom-Json).version
}

if ($PerlForceCleanup) {
    Invoke-PerlVersionPurge -InstallPath $perlInstallDir
    # Reset trackers to force a fresh install
    $localVersion = "0.0.0"
}

# --- 2. Install or Skip ---
$vLocal  = [version]$localVersion
$vRemote = [version]$remoteVersion

if ($vLocal -ge $vRemote -and $localVersion -ne "0.0.0") {
    Write-Host "[SKIP] Perl $localVersion is already installed and up to date at: $perlExePath" -ForegroundColor Green
    Write-Host "Perl Version: $(& $perlExePath --version | Select-String "v\d+\.\d+\.\d+")" -ForegroundColor Gray

    $perlVersion = $localVersion

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
    Write-Host "[UPDATE] Local: $localVersion -> Remote: $remoteVersion" -ForegroundColor Yellow
    
    if ($null -eq $downloadUrl) {
        Write-Error "Cannot proceed with installation. Failed to retrieve a valid download URL."
        return
    }

    # --- 2. Prepare Clean Install Directory ---
    if (Test-Path $perlInstallDir) {
        Write-Host "[CLEANUP] Removing existing Perl installation at $perlInstallDir..." -ForegroundColor Yellow
        Remove-Item -Path $perlInstallDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    # Create a brand new, empty directory
    Write-Host "[INSTALL] Creating fresh directory: $perlInstallDir" -ForegroundColor Cyan
    New-Item -Path $perlInstallDir -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null

    try {
        $zipFile = Join-Path $env:TEMP "strawberry-perl.zip"

        Write-Host "Downloading Strawberry Perl Portable..." -ForegroundColor Cyan
        Invoke-WebRequest -Uri $downloadUrl -OutFile $zipFile

        Write-Host "Extracting to $perlInstallDir (This may take a moment)..." -ForegroundColor Gray
        $tempExtractPath = Join-Path $env:TEMP "perl_extract_$(Get-Random)"
        New-Item -Path $tempExtractPath -ItemType Directory -Force | Out-Null
        Expand-Archive -Path $zipFile -DestinationPath $tempExtractPath -Force

        # Portable Perl unzips flat into the directory (contains perl/, c/, cpan/, etc.)
        Write-Host "Deploying files..." -ForegroundColor Gray
        Get-ChildItem -Path $tempExtractPath | Move-Item -Destination $perlInstallDir -Force -ErrorAction SilentlyContinue
        
        $relocScript = Join-Path $perlInstallDir "relocation.pl.bat"
        if (Test-Path $relocScript) {
            Write-Host "Running Perl relocation script..." -ForegroundColor Cyan
            Push-Location $perlInstallDir
            & cmd /c "relocation.pl.bat"
            Pop-Location
        }

        $perlVersion = $remoteVersion
        if (Test-Path $perlExePath) {
            $rawVersion = (& $perlExePath --version | Select-String "v\d+\.\d+\.\d+").Matches.Value
        }
        $versionInfo = @{
            url        = $url;
            tag_name   = $tag_name;
            commit     = $tagCommit;
            version    = $remoteVersion;
            rawversion = $rawVersion;
            date       = (Get-Date).ToString("yyyy-MM-dd");
            updated_at = $updated_at;
            type       = "portable_dist";
        }
        $versionInfo | ConvertTo-Json | Out-File -FilePath $versionFile -Encoding utf8 -Force
    
        # Cleanup extraction debris
        Remove-Item $zipFile -Force -ErrorAction SilentlyContinue
        Remove-Item $tempExtractPath -Recurse -Force -ErrorAction SilentlyContinue

        Write-Host "Perl $remoteVersion installed successfully!" -ForegroundColor DarkGreen
    }
    catch {
        Write-Error "Failed to install Perl: $($_.Exception.Message)"
        return # Stop execution on failure
    }
}

# --- 3. Finalize Helpers & Symlinks ---
if (Test-Path $perlExePath) {
    # Helper Script Generation
    Write-Host "Generating environment helper script..." -ForegroundColor Cyan

    # Generate Environment Helper with Clean Paths
    $perlBinPath = $perlBinPath.TrimEnd('\')
    $perlSiteBinPath = $perlSiteBinPath.TrimEnd('\')
    $perlCBinPath = $perlCBinPath.TrimEnd('\')
    $perlInstallDir = $perlInstallDir.TrimEnd('\')
    $perlExePath = Join-Path $perlBinPath "perl.exe"

    # Using a literal here-string with -replace to avoid accidental expansion of $env:PATH during creation
    $EnvContent = @'
# PERL Environment Setup
$perlroot = "VALUE_ROOT_PATH"
$perlbin = "VALUE_BIN_PATH"
$perlsitebin = "VALUE_SITE_BIN_PATH"
$perlcbin = "VALUE_C_BIN_PATH"
$perlexe = "VALUE_EXE_PATH"
$perlversion = "VALUE_VERSION"
$env:PERL_PATH = $perlroot
$env:PERL_ROOT = $perlroot
$env:PERL_BIN = "$perlbin;$perlsitebin;$perlcbin"
$env:BINARY_PERL = $perlexe
"$perlcbin", "$perlsitebin", "$perlbin" | ForEach-Object { if ($env:PATH -notlike "*$_*") { $env:PATH = $_ + ";" + $env:PATH; $env:PATH = ($env:PATH).Replace(";;", ";") } }
Write-Host "Perl Environment Loaded (Version: $perlversion) (Bin: $perlbin)" -ForegroundColor Green
Write-Host "PERL_ROOT: $env:PERL_ROOT" -ForegroundColor Gray
'@  -replace "VALUE_BIN_PATH", $perlBinPath `
    -replace "VALUE_SITE_BIN_PATH", $perlSiteBinPath `
    -replace "VALUE_C_BIN_PATH", $perlCBinPath `
    -replace "VALUE_EXE_PATH", $perlExePath `
    -replace "VALUE_ROOT_PATH", $perlInstallDir `
    -replace "VALUE_VERSION", $perlVersion

    $EnvContent | Out-File -FilePath $perlEnvScript -Encoding utf8
    Write-Host "Created: $perlEnvScript" -ForegroundColor Gray

    # Update Current Session
    if (Test-Path $perlEnvScript) { . $perlEnvScript } else {
        Write-Error "perl dep install finished but $perlEnvScript was not created."
        return
    }
    
    # --- 10. Symlink to Global Binaries ---
    Write-Host "Creating global symlink to: $GlobalBinDir..." -ForegroundColor Cyan

    # Create Symlink
    foreach ($perltool in $perltools) {
        $source = Join-Path $perlBinPath $perltool
        $target = Join-Path $GlobalBinDir $perltool

        if (Test-Path $source) {
            if (Test-Path $target) { Remove-Item $target -Force -ErrorAction SilentlyContinue }
            try {
                New-Item -Path $target -ItemType SymbolicLink -Value $source -ErrorAction Stop | Out-Null
                Write-Host "[LINKED] $perltool" -ForegroundColor Gray
            } catch {
                # Fallback to hardlink if developer mode is off/insufficient permissions
                New-Item -Path $target -ItemType HardLink -Value $source | Out-Null
                Write-Host "[HARDLINKED] $perltool (Global) -> $source" -ForegroundColor Gray
            }
        }
    }

    Write-Host "[LINKED] Perl is now globally available via %BINARIES_PATH%" -ForegroundColor Green

    Write-Host "Perl Version: $(& $perlExePath --version | Select-String "v\d+\.\d+\.\d+")" -ForegroundColor Gray
    
    Write-Host "Checking for Text::Template module..." -ForegroundColor Cyan
    & $perlExePath -MText::Template -e 1 2>$null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Installing Text::Template module via cpanm..." -ForegroundColor Yellow
        $cpanmPath = Join-Path $perlBinPath "cpanm.bat"
        if (Test-Path $cpanmPath) {
            # installing Text::Template for openssl
            & $cpanmPath --notest Text::Template
        } else {
            Write-Warning "cpanm.bat not found at $cpanmPath"
        }
    } else {
        Write-Host "Text::Template module is already installed." -ForegroundColor Green
    }

    if ($PerlWithMachineEnvironment)
    {
        # Generating Machine Environment wich add to the persist registry machine Environment
        $MachineEnvContent = @'
# Perl Machine Environment Setup

# --- 0. Self-Elevation Logic ---
$IsAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$ScopeColor = "Cyan"

if (-not $IsAdmin) {
    Write-Host "Elevation required to set Perl system variables. Relaunching as Administrator..." -ForegroundColor Yellow
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

$perlroot = "VALUE_ROOT_PATH"
$perlbin = "VALUE_BIN_PATH"
$perlsitebin = "VALUE_SITE_BIN_PATH"
$perlcbin = "VALUE_C_BIN_PATH"
$perlversion = "VALUE_VERSION"

$TargetScope = if ($IsAdmin) { "Machine" } else { "User" }
$RegPath = if ($IsAdmin) { "System\CurrentControlSet\Control\Session Manager\Environment" } else { "Environment" }
$RegRoot = if ($IsAdmin) { "LocalMachine" } else { "CurrentUser" }

# Open the registry key once
$RegKey = [Microsoft.Win32.Registry]::$RegRoot.OpenSubKey($RegPath, $true)

# Open the registry key directly to read the RAW (unexpanded) string
$CurrentRawPath = $RegKey.GetValue("EXTCOMP_PATH", "", [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)

# Cleanup: Remove empty strings, any path containing $perlroot, and the current target (to avoid dups)
$CleanedPathList = $CurrentRawPath -split ';' | Where-Object { 
    -not [string]::IsNullOrWhitespace($_) -and 
    $_ -notlike "*$perlroot*"
}

$NewRawPath = ($CleanedPathList -join ";").Replace(";;", ";")

$TargetPaths = @($perlbin, $perlsitebin, $perlcbin)

# Rebuild
foreach ($p in $TargetPaths) {
    $NewRawPath = ($NewRawPath + ";" + $p + ";").Replace(";;", ";")
}
Write-Host "[UPDATED] ($TargetScope) Perl paths synced in EXTCOMP_PATH" -ForegroundColor $ScopeColor

# Save as ExpandString
$RegKey.SetValue("EXTCOMP_PATH", $NewRawPath, [Microsoft.Win32.RegistryValueKind]::ExpandString)
$env:EXTCOMP_PATH = $NewRawPath

$RegKey.Close()

$env:PERL_ROOT = $perlroot
Write-Host "Perl Environment Loaded (Version: $perlversion) (Bin: $perlbin)" -ForegroundColor Green
Write-Host "PERL_ROOT: $env:PERL_ROOT" -ForegroundColor Gray
'@  -replace "VALUE_ROOT_PATH", $perlInstallDir `
    -replace "VALUE_BIN_PATH", $perlBinPath `
    -replace "VALUE_SITE_BIN_PATH", $perlSiteBinPath `
    -replace "VALUE_C_BIN_PATH", $perlCBinPath `
    -replace "VALUE_VERSION", $perlVersion

        $MachineEnvContent | Out-File -FilePath $perlMachineEnvScript -Encoding utf8
        Write-Host "Created: $perlMachineEnvScript" -ForegroundColor Gray
        
        # --- Interaction: Prompt to apply persistent changes ---
        Write-Host ""
        $choice = Read-Host "Do you want to run the Machine Environment script now to persist Perl changes to the Registry? (y/n)"
        if ($choice -eq 'y' -or $choice -eq 'Y') {
            Write-Host "Executing $perlMachineEnvScript..." -ForegroundColor Yellow
            try {
                # Start the generated script. It handles its own elevation logic.
                & $perlMachineEnvScript
            }
            catch {
                Write-Error "Failed to execute the Machine Environment script: $($_.Exception.Message)"
            }
        }
        else {
            Write-Host "Skipped persistent registry update. You can run it later at: $perlMachineEnvScript" -ForegroundColor Gray
        }
    }
} else {
    Write-Error "perl.exe was not found in the $perlBinPath folder."
    $perltools | ForEach-Object { 
        $globalLinkPath = Join-Path $GlobalBinDir $_
        if (Test-Path $globalLinkPath) {
            Write-Host "Cleaning up dead symlink at $globalLinkPath..." -ForegroundColor Yellow
            Remove-Item $globalLinkPath -Force -ErrorAction SilentlyContinue
        } 
    }
    return
}
