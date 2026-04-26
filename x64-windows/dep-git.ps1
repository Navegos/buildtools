# SPDX-FileCopyrightText: Copyright (c) 2026 Navegos. @DevelVitorF. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
# project: buildtools
# file: x64-windows/dep-git.ps1
# created: 2026-03-14
# lastModified: 2026-04-26

param (
    [Parameter(HelpMessage = "Path for git Installation", Mandatory = $false)]
    [string]$gitInstallDir = $(Join-Path $env:ProgramFiles "Git"),
    
    [Parameter(HelpMessage = "Force a full purge of the local GIT version before continuing", Mandatory = $false)]
    [switch]$forceCleanup
)

# Capture parameters
$GitForceCleanup = $forceCleanup

# --- 0. Self-Elevation Logic ---
$IsAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $IsAdmin) {
    Write-Host "Elevation required to install/update Git. Relaunching as Administrator..." -ForegroundColor Yellow
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

# 1. Bootstrap Environment if variables are missing
if ([string]::IsNullOrWhitespace($env:ENVIRONMENT_PATH) -or -not (Test-Path $env:ENVIRONMENT_PATH) -or [string]::IsNullOrWhitespace($env:BINARIES_PATH) -or -not (Test-Path $env:BINARIES_PATH) -or [string]::IsNullOrWhitespace($env:LIBRARIES_PATH) -or -not (Test-Path $env:LIBRARIES_PATH)) {
    Write-Error "User Environment variables missing. Please run adduserpaths.ps1 -LibrariesDir 'Path\for\Libraries' BinariesDir 'Path\for\Binaries' -EnvironmentDir 'Path\for\Environment'"
    return
}

Write-Host "--- Git Management ---" -ForegroundColor Cyan

$EnvironmentDir = "$env:ENVIRONMENT_PATH"

# if Symlink present delete
$GlobalBinDir = "$env:BINARIES_PATH"
$gittools = @("git.exe", "git-gui.exe", "gitk.exe", "git-lfs.exe", "git-bash.exe", "git-cmd.exe") # not adding usr/bin because it will breack
foreach ($gitool in $gittools) {
    $target = Join-Path $GlobalBinDir $gitool
    if (Test-Path $target) { Remove-Item $target -Force -ErrorAction SilentlyContinue }
}

$gitBinPath = Join-Path $gitInstallDir "cmd"
$gitExePath = Join-Path $gitBinPath "git.exe"
$versionFile = Join-Path $gitInstallDir "version.json"
$gitEnvScript = Join-Path $EnvironmentDir "env-git.ps1"

# Version Detection
$repo = "git-for-windows/git"
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
}
catch {
    Write-Warning "Could not connect to GitHub. Using 0.0.0 for remote."
    $url = "ERR_CONNECTION_TIMED_OUT"
    $tag_name = "0.0.0"
    $updated_at = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssZ")
    $remoteVersion = "0.0.0"
    $tagCommit = "0000000000000000000000000000000000000000"
}

$TargetScope = if ($IsAdmin) { "Machine" } else { "User" }
$RegPath = if ($IsAdmin) { "System\CurrentControlSet\Control\Session Manager\Environment" } else { "Environment" }
$RegRoot = if ($IsAdmin) { "LocalMachine" } else { "CurrentUser" }

# --- 1. Cleanup Mechanism ---
function Invoke-GitVersionPurge {
    param ([string]$InstallPath)
    Write-Host "--- Initiating Git Purge ---" -ForegroundColor Cyan

    # 1. Official Uninstaller Check
    $uninstaller = Join-Path $InstallPath "unins000.exe"
    if (Test-Path $uninstaller) {
        Write-Host "Found official uninstaller. Running silent uninstall..." -ForegroundColor Yellow
        Start-Process -FilePath $uninstaller -ArgumentList "/VERYSILENT /SUPPRESSMSGBOXES /NORESTART" -Wait
    }

    # 2. Registry Cleanup (TOOLS_PATH & EXTCOMP_PATH)
    $RegKey = [Microsoft.Win32.Registry]::$RegRoot.OpenSubKey($RegPath, $true)
    foreach ($VarName in @("TOOLS_PATH", "EXTCOMP_PATH")) {
        # Open the registry key directly to read the RAW (unexpanded) string
        $RawPath = $RegKey.GetValue($VarName, "", [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)

        # Cleanup: Remove empty strings, any path containing $VarName,
        $CleanPath = ($RawPath -split ';' | Where-Object { $_ -notlike "*$InstallPath*" }) -join ";"

        # Save as ExpandString
        $RegKey.SetValue($VarName, $CleanPath, [Microsoft.Win32.RegistryValueKind]::ExpandString)

        Write-Host "  [CLEANED] $VarName" -ForegroundColor Gray
    }
    $RegKey.Close()
    
    # 2. Filesystem Clean (Requires checking for locked files)
    # delete everithing we create don't fail later
    if (Test-Path $gitEnvScript) {
        Write-Host "  [DELETING] $gitEnvScript" -ForegroundColor Yellow
        Remove-Item $gitEnvScript -Recurse -Force -ErrorAction SilentlyContinue
    }
    if (Test-Path $InstallPath) {
        Write-Host "  [DELETING] $InstallPath" -ForegroundColor Yellow
        Remove-Item $InstallPath -Recurse -Force -ErrorAction SilentlyContinue
    }
    
    # remove local Env variables for current session
    Get-ChildItem Env:\GIT_PATH* | Remove-Item -ErrorAction SilentlyContinue
    Get-ChildItem Env:\GIT_ROOT* | Remove-Item -ErrorAction SilentlyContinue
    Get-ChildItem Env:\GIT_BIN* | Remove-Item -ErrorAction SilentlyContinue

    Write-Host "--- Git Purge Complete ---" -ForegroundColor Green
}

$localVersion = "0.0.0"
$rawVersion = "0.0.0"
if (Test-Path $gitExePath) {
    $rawVersion = (& $gitExePath --version).Trim()
    if ($rawVersion -match '^(\d+\.\d+\.\d+)') { $localVersion = $Matches[1] }
}

if (Test-Path $versionFile) {
    $localVersion = (Get-Content $versionFile | ConvertFrom-Json).version
}

if ($GitForceCleanup) {
    Invoke-GitVersionPurge -InstallPath $gitInstallDir
    # Reset trackers to force a fresh install
    $localVersion = "0.0.0"
}

# --- 2. Install or Skip ---
$vLocal = [version]$localVersion
$vRemote = [version]$remoteVersion

# --- 1. Detect and Install/Update via WinGet ---
function Install-Or-Update-Git {
    Write-Host "--- Git Provisioning ---" -ForegroundColor Cyan
    
    # Components mapping:
    # ext\shell\here: Explorer integration (Bash/Gui Here)
    # gitlfs: Git LFS Support
    # assoc: .git configuration association
    # assoc_sh: .sh files association
    # terminal: Windows Terminal profile
    # scalar: Scalar addon
    $components = "icons\quicklaunch,ext\shell\here,gitlfs,assoc,assoc_sh,terminal,scalar"

    $installArgs = "/VERYSILENT " +
                   "/NORESTART " +
                   "/NOCANCEL " +
                   "/SP- " +
                   "/CLOSEAPPLICATIONS " +
                   "/DIR=`"$gitInstallDir`" " +
                   "/COMPONENTS=`"$components`" " +
                   "/Editor=Notepad " +                    # Use notepad as default editor
                   "/DefaultBranchName=main " +            # Override default branch to 'main'
                   "/PathOption=BashOnly " +               # Use Git from Bash/Cmd (no wrapper impact)
                   "/SSHOption=OpenSSH " +                 # Use bundled OpenSSH
                   "/HTTPSOption=WinSSL " +                # Use Native Windows Secure Channel
                   "/LineEndings=CheckinWindows " +        # Checkout Windows-style, commit Unix-style
                   "/TerminalOption=MinTTY " +             # Use MinTTY
                   "/PullRebaseOption=Merge " +            # Fast forward or merge
                   "/CredentialManager=Core " +            # Git Credential Manager
                   "/EnableFSCache=Yes " +                 # Enable file system caching
                   "/EnableSymlinks=Yes"                   # Enable symbolic links

    if (Get-Command winget -ErrorAction SilentlyContinue) {
        Write-Host "Processing via WinGet..." -ForegroundColor Gray
        # Capture both standard output and errors
        # We use 'install' with --override to force our specific parameters
        # If already installed, winget will handle the configuration update
        $installOutput = winget install --id Git.Git --source winget --silent `
                         --accept-package-agreements --accept-source-agreements `
                         --override "$installArgs" 2>&1

        $exitCode = $LASTEXITCODE

        # Handle WinGet Result States
        if ($exitCode -eq 0 -or $exitCode -eq -1978335178-or $exitCode -eq -1978335189) {
            Write-Host "[SUCCESS] Git is up to date at $gitInstallDir\" -ForegroundColor Green
            
            # Use the variable to check if a reboot/restart is suggested in the text
            if ($installOutput -match "restart") {
                Write-Host "[NOTE] A system restart is recommended to finalize the update." -ForegroundColor Yellow
            }
        }else {
            Write-Host "[ERROR] WinGet operation failed. Exit Code: $exitCode" -ForegroundColor Red
            Write-Host "Details: $installOutput" -ForegroundColor Gray
        }
    } else {
        # Fallback for older systems without WinGet
        Write-Host "WinGet not found. Fetching latest release from GitHub API..." -ForegroundColor Yellow
        
        try {
            # Dynamically find the x64 EXE URL for the latest stable release
            $urlasset = ($latestRelease.assets | Where-Object { $_.name -match '64-bit\.exe$' }).browser_download_url

            if (-not $urlasset) { throw "Could not find a valid x64 EXE in the latest GitHub Git release." }

            $installerPath = Join-Path $env:TEMP "git_install.exe"
            Write-Host "Downloading: $($urlasset.Split('/')[-1])..." -ForegroundColor Gray
            Invoke-WebRequest -Uri $urlasset -OutFile $installerPath

            Write-Host "Installing EXE with Navegos parameters..." -ForegroundColor Gray
            # Use REINSTALLMODE=ams to force overwrite if already present, ensuring context menus are set
            $process = Start-Process -FilePath $installerPath -ArgumentList "$installArgs" -Wait -PassThru

            # Exit code 0 is success, 1638 is "already installed"
            if ($process.ExitCode -eq 0 -or $process.ExitCode -eq 1638) {
                Write-Host "[SUCCESS] Git provisioned via EXE at $gitInstallDir\" -ForegroundColor Green
            } else {
                Write-Host "[ERROR] EXE failed with exit code: $($process.ExitCode)" -ForegroundColor Red
            }
        } catch {
            Write-Error "Fallback installation failed: $($_.Exception.Message)"
        } finally {
            if (Test-Path $installerPath) { Remove-Item $installerPath -Force -ErrorAction SilentlyContinue }
        }
    }
    # --- Path Management: Add to END of Path if not present ---
    $pathCmd = Join-Path $gitInstallDir "cmd"
    $pathUsr = Join-Path $gitInstallDir "usr\bin"
    
    # Open the registry key once
    $RegKey = [Microsoft.Win32.Registry]::$RegRoot.OpenSubKey($RegPath, $true)

    # Open the registry key directly to read the RAW (unexpanded) string
    $CurrentRawToolsPath = $RegKey.GetValue("TOOLS_PATH", "", [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
    $CurrentRawExtCompPath = $RegKey.GetValue("EXTCOMP_PATH", "", [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
    
    # Check for both critical folders
    if ($CurrentRawToolsPath -notlike "*$pathCmd*" -or $CurrentRawToolsPath -notlike "*$gitInstallDir*") {
        Write-Host "[PATH] Appending Git cmd root paths to $TargetScope Environment Registry..." -ForegroundColor Cyan
        # Build clean addition
        $CleanPath = $CurrentRawToolsPath.TrimEnd(';')
        if ($CurrentRawToolsPath -notlike "*$pathCmd*") { $CleanPath += ";$pathCmd" }
        if ($CurrentRawToolsPath -notlike "*$gitInstallDir*") { $CleanPath += ";$gitInstallDir" }
        
        # Ensure windows path end dont's wrap
        $CleanPath = ($CleanPath + ";").Replace(";;", ";")

        $RegKey.SetValue("TOOLS_PATH", $CleanPath, [Microsoft.Win32.RegistryValueKind]::ExpandString)
    }
    if ($CurrentRawExtCompPath -notlike "*$pathUsr*") {
        Write-Host "[PATH] Appending Git usr paths to $TargetScope Environment Registry..." -ForegroundColor Cyan
        # Build clean addition
        $CleanPath = $CurrentRawExtCompPath.TrimEnd(';')
        if ($CurrentRawExtCompPath -notlike "*$pathUsr*") { $CleanPath += ";$pathUsr" }
        
        # Ensure windows path end dont's wrap
        $CleanPath = ($CleanPath + ";").Replace(";;", ";")
        
        $RegKey.SetValue("EXTCOMP_PATH", $CleanPath, [Microsoft.Win32.RegistryValueKind]::ExpandString)
    }
    Write-Host "Scrubbing default Git entries from standard Windows Path..." -ForegroundColor Cyan

    # Define the targets to remove
    $targetsToRemove = @("$gitInstallDir\cmd", "$gitInstallDir\bin", "$gitInstallDir\usr\bin")

    # 1. Clean Machine Path
    $RegPath = "System\CurrentControlSet\Control\Session Manager\Environment"
    $RegistryKey = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey($RegPath, $true)
    $CurrentRawPath = $RegistryKey.GetValue("Path", "", [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
    
    # Filter out any segments containing our target strings
    $NewRawPath = ($CurrentRawPath -split ';' | Where-Object { 
        $item = $_; 
        $keep = $true
        foreach ($target in $targetsToRemove) {
            if ($item -like "*$target*") { $keep = $false; break }
        }
        $keep -and ![string]::IsNullOrWhiteSpace($item)
    }) -join ';'
    
    # Ensure we don't start with a semicolon if the path was somehow empty
    $NewRawPath = ($NewRawPath + ";$TargetTag").Replace(";;;", ";;").Replace(";;", ";")

    $RegistryKey.SetValue("Path", $NewRawPath, [Microsoft.Win32.RegistryValueKind]::ExpandString)
    $RegKey.Close()

    Write-Host "[CLEANED] Standard Path variables purged of default Git entries." -ForegroundColor Gray
}

if ($vLocal -ge $vRemote -and $localVersion -ne "0.0.0") {
    Write-Host "[SKIP] Git $localVersion is already installed and up to date at: $gitExePath" -ForegroundColor Green
    Write-Host "Git Version: $(& $gitExePath --version)" -ForegroundColor Gray

    # 1. Locate the bin folder and the root folder
    $gitVersion = $localVersion
    $gitBinPath = Split-Path -Path $gitExePath -Parent
    $gitInstallDir = Split-Path -Path $gitBinPath -Parent

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

    Install-Or-Update-Git

    # --- 3. Save Version Metadata with Safety Check ---
    if (-not (Test-Path $gitInstallDir)) { New-Item -Path $gitInstallDir -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null }

    $gitVersion = $remoteVersion
    if (Test-Path $gitExePath) {
        $rawVersion = (& $gitExePath --version).Trim()
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
    try {
        $versionInfo | ConvertTo-Json | Out-File -FilePath $versionFile -Encoding utf8 -Force
    }
    catch {
        Write-Warning "Metadata save failed. Check folder permissions for $gitInstallDir"
    }
}

# --- 3. Environment Setup ---
# The installer typically puts git.exe in \cmd
if (Test-Path $gitExePath) {
    # Create Environment Helper
    Write-Host "Generating environment helper script..." -ForegroundColor Cyan
    
    # Generate Environment Helper with Clean Paths
    $gitBinPath = $gitBinPath.TrimEnd('\')
    $gitInstallDir = $gitInstallDir.TrimEnd('\')
    $gitExePath = Join-Path $gitBinPath "git.exe"

    # Using a literal here-string with -replace to avoid accidental expansion of $env:PATH during creation
    $EnvContent = @'
# GIT Environment Setup
$gitroot = "VALUE_ROOT_PATH"
$gitbin = "VALUE_BIN_PATH"
$gitexe = "VALUE_EXE_PATH"
$gitversion = "VALUE_VERSION"
$gitunixTools = Join-Path $gitroot "usr\bin"
$env:GIT_PATH = $gitroot
$env:GIT_ROOT = $gitroot
$env:GIT_BIN = $gitbin
$env:BINARY_GIT = $gitexe
"$gitunixTools", "$gitroot", "$gitbin" | ForEach-Object { if ($env:PATH -notlike "*$_*") { $env:PATH = $_ + ";" + $env:PATH; $env:PATH = ($env:PATH).Replace(";;", ";") } }
Write-Host "Git Environment Loaded (Version: $gitversion) (Bin: $gitbin)" -ForegroundColor Green
Write-Host "GIT_ROOT: $env:GIT_ROOT" -ForegroundColor Gray
'@  -replace "VALUE_BIN_PATH", $gitBinPath `
    -replace "VALUE_EXE_PATH", $gitExePath `
    -replace "VALUE_ROOT_PATH", $gitInstallDir `
    -replace "VALUE_VERSION", $gitVersion

    $EnvContent | Out-File -FilePath $gitEnvScript -Encoding utf8
    Write-Host "Created: $gitEnvScript" -ForegroundColor Gray
    
    # Update Current Session
    if (Test-Path $gitEnvScript) { . $gitEnvScript } else {
        Write-Error "git dep install finished but $gitEnvScript was not created."
        return
    }

    # --- 10. Symlink to Global Binaries ---
    Write-Host "Creating global symlink to: $GlobalBinDir..." -ForegroundColor Cyan

    # Create Symlink
    foreach ($gittool in $gittools) {
        if ($gittool -eq "git-bash.exe" -or $gittool -eq "git-cmd.exe") {
            $source = Join-Path $gitInstallDir $gittool
        } else {
            $source = Join-Path $gitBinPath $gittool
        }
        $target = Join-Path $GlobalBinDir $gittool

        if (Test-Path $source) {
            if (Test-Path $target) { Remove-Item $target -Force -ErrorAction SilentlyContinue }
            try {
                New-Item -Path $target -ItemType SymbolicLink -Value $source -ErrorAction Stop | Out-Null
                Write-Host "[LINKED] $gittool" -ForegroundColor Gray
            }
            catch {
                # Fallback to hardlink if developer mode is off/insufficient permissions
                New-Item -Path $target -ItemType HardLink -Value $source | Out-Null
            }
        }
        else {
            Write-Warning "Optional tool $gittool not found in $gitBinPath distribution; skipping symlink."
        }
    }
    
    Write-Host "[LINKED] Git is now globally available via %BINARIES_PATH%" -ForegroundColor Green

    Write-Host "Git Version: $(& $gitExePath --version)" -ForegroundColor Gray

    # --- Post-Install Configuration ---
    # 1. Check for User Name
    $gitName = git config --global user.name
    if ([string]::IsNullOrWhitespace($gitName)) {
        $newName = Read-Host "Git user.name not set. Please enter your name (e.g., VitorF)"
        if (-not [string]::IsNullOrWhitespace($newName)) {
            git config --global user.name "$newName"
            Write-Host "  -> user.name set to: $newName" -ForegroundColor Gray
        }
    }
    else {
        Write-Host "  -> user.name: $gitName" -ForegroundColor DarkGray
    }

    # 2. Check for User Email
    $gitEmail = git config --global user.email
    if ([string]::IsNullOrWhitespace($gitEmail)) {
        $newEmail = Read-Host "Git user.email not set. Please enter your email"
        if (-not [string]::IsNullOrWhitespace($newEmail)) {
            git config --global user.email "$newEmail"
            Write-Host "  -> user.email set to: $newEmail" -ForegroundColor Gray
        }
    }
    else {
        Write-Host "  -> user.email: $gitEmail" -ForegroundColor DarkGray
    }
    
    # 3. Optimization: Performance and Compatibility
    Write-Host "Applying Windows-specific Git optimizations..." -ForegroundColor Gray
    
    # Ignore file permission changes (Windows doesn't use standard POSIX bits)
    git config --global core.filemode false
    
    # Convert LF to CRLF on checkout, CRLF to LF on commit (Standard Windows/Unix compatibility)
    git config --global core.autocrlf true
    
    # Enable the file system cache to speed up status checks on large repos
    git config --global core.fscache true
    
    # Allow Git to handle symbolic links (Requires Admin or Developer Mode enabled in Windows)
    git config --global core.symlinks true
    
    # Bypass the 260 character limit for file paths (Essential for deep C++ build trees)
    git config --global core.longpaths true
    
    # Disable built-in file system monitor (Usually safer to leave off unless repo is massive)
    git config --global core.fsmonitor false
    
    # Use standard merge behavior for 'git pull' (instead of automatic rebase)
    git config --global pull.rebase false
    
    # Don't remove remote-tracking branches that no longer exist on remote during every fetch
    git config --global fetch.prune false
    
    # Disable automatic stashing of local changes before a rebase starts
    git config --global rebase.autoStash false

    # Set Default branch to 'main'
    git config set --global init.defaultBranch main

    # 4. Verification of Unix Tools
    $shCheck = Get-Command sh -ErrorAction SilentlyContinue
    if ($shCheck) {
        Write-Host "[OK] Unix shell tools detected at: $($shCheck.Source)" -ForegroundColor Green
    }
}
else {
    Write-Error "git.exe was not found in the $gitBinPath folder."
    return
}
