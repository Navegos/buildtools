# SPDX-FileCopyrightText: Copyright (c) 2026 Navegos. @DevelVitorF. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
# project: buildtools
# file: x64-windows/build-jom.ps1
# created: 2026-05-03
# lastModified: 2026-05-11

param (
    [Parameter(HelpMessage = "Base workspace path", Mandatory = $false)]
    [string]$workspacePath = $null,

    [Parameter(HelpMessage = "jom git repo url", Mandatory = $false)]
    [string]$gitUrl = "https://github.com/qt-labs/jom.git",
    
    [Parameter(HelpMessage = "jom git branch to sync from", Mandatory = $false)]
    [string]$gitBranch = "master",

    [Parameter(HelpMessage = "Path for jom storage", Mandatory = $false)]
    [string]$jomInstallDir = "$env:LIBRARIES_PATH\jom",
    
    [Parameter(HelpMessage = "Force a full purge of the local Jom version before continuing", Mandatory = $false)]
    [switch]$forceCleanup,
    
    [Parameter(HelpMessage = "Add's Jom Machine Environment Variables. Requires Machine Administrator Rights.", Mandatory = $false)]
    [switch]$withMachineEnvironment
)

# Capture parameters
$JomWorkspacePath = $workspacePath
$JomGitUrl = $gitUrl
$JomGitBranch = $gitBranch
$JomForceCleanup = $forceCleanup
$JomWithMachineEnvironment = $withMachineEnvironment

if ([string]::IsNullOrWhitespace($env:ENVIRONMENT_PATH) -or -not (Test-Path $env:ENVIRONMENT_PATH) -or [string]::IsNullOrWhitespace($env:BINARIES_PATH) -or -not (Test-Path $env:BINARIES_PATH) -or [string]::IsNullOrWhitespace($env:LIBRARIES_PATH) -or -not (Test-Path $env:LIBRARIES_PATH) -or [string]::IsNullOrWhitespace($env:BUILDTOOLS_PATH) -or -not (Test-Path $env:BUILDTOOLS_PATH)) {
    Write-Error "User Environment variables missing. Please run add-user-paths.ps1 -LibrariesDir 'Path/for/Libraries' -BinariesDir 'Path/for/Binaries' -EnvironmentDir 'Path/for/Environment' -BuildToolsDir 'Path/for/BuildTools'"
    return
}

$EnvironmentDir = "$env:ENVIRONMENT_PATH"

$jomEnvScript = Join-Path $EnvironmentDir "env-jom.ps1"
$jomMachineEnvScript = Join-Path $EnvironmentDir "machine-env-jom.ps1"
$RootJomWorkspacePath = if ([string]::IsNullOrWhitespace($JomWorkspacePath)) { Get-Location } else { $JomWorkspacePath }

$GlobalBinDir = "$env:BINARIES_PATH"
$TargetLink = Join-Path $GlobalBinDir "jom.exe"

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

# Open the registry key directly to read the RAW (unexpanded) string
$RawPath = $RegKey.GetValue("TOOLS_PATH", "", [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)

# Cleanup: Remove empty strings, any path containing $jomroot,
$CleanPath = ($RawPath -split ';' | Where-Object { $_ -notlike "*$jomroot*" }) -join ";"

# Save as ExpandString
$RegKey.SetValue("TOOLS_PATH", $CleanPath, [Microsoft.Win32.RegistryValueKind]::ExpandString)
$env:TOOLS_PATH = $CleanPath

$RegKey.Close()

Write-Host "[REMOVED] ($TargetScope) all '*$jomroot*' removed from TOOLS_PATH" -ForegroundColor $ScopeColor
'@  -replace "VALUE_ROOT_PATH", $InstallPath

        $CleanMachineEnvContent | Out-File -FilePath $jomCleanMachineEnvScript -Encoding utf8
        Write-Host "Created: $jomCleanMachineEnvScript" -ForegroundColor Gray
        
        # --- Interaction: Prompt to remove persistent changes ---
        Write-Host ""
        $choice = Read-Host "Administrator rights required to Clean Machine Environment jom changes? (y/n)"
        if ($choice -eq 'y' -or $choice -eq 'Y') {
            Write-Host "Executing $jomCleanMachineEnvScript..." -ForegroundColor Yellow
            try {
                # Start the generated script. It handles its own elevation logic.
                & $jomCleanMachineEnvScript
            }
            catch {
                Write-Error "Failed to execute the Clean Machine Environment script: $($_.Exception.Message)"
                return
            }
        }
        else {
            Write-Error "Skipped Clean Machine Environment jom changes."
            return
        }
        
        # Cleanup
        Remove-Item $jomCleanMachineEnvScript -Recurse -Force -ErrorAction SilentlyContinue
    }

    $Source = Join-Path $RootJomWorkspacePath "jom"
    
    # 2. Filesystem Clean (Requires checking for locked files)
    # delete everithing we create don't fail later
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
    if (Test-Path $Source) {
        Write-Host "  [DELETING] $Source" -ForegroundColor Yellow
        Remove-Item $Source -Recurse -Force -ErrorAction SilentlyContinue
    }
    
    if (Test-Path $TargetLink) { Remove-Item $TargetLink -Force -ErrorAction SilentlyContinue; Write-Host "  [REMOVED] Link: jom.exe" -ForegroundColor Gray }

    # remove local Env variables for current session
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

if ($JomForceCleanup) {
    Invoke-JomVersionPurge -InstallPath $jomInstallDir
}

# --- 1. Initialize Visual Studio 2026 Dev Environment ---
$DevShellBootstrapScript = Join-Path $PSScriptRoot "dev-shell.ps1"
if (Test-Path $DevShellBootstrapScript) { . $DevShellBootstrapScript } else {
    Write-Error "Required dependency '$DevShellBootstrapScript' not found!"
    return
}

# --- 2. Initialize git environment if missing ---
if ([string]::IsNullOrWhitespace($env:BINARY_GIT) -or -not (Test-Path $env:BINARY_GIT)) {
    $gitEnvScript = Join-Path $EnvironmentDir "env-git.ps1"
    if (Test-Path $gitEnvScript) { . $gitEnvScript } 
    if ([string]::IsNullOrWhitespace($env:BINARY_GIT) -or -not (Test-Path $env:BINARY_GIT)) {
        $depgitEnvScript = Join-Path $PSScriptRoot "dep-git.ps1"
        if (Test-Path $depgitEnvScript) { . $depgitEnvScript }
        else {
            Write-Error "CRITICAL: Cannot load Git environment. git is missing and $depgitEnvScript was not found."
            return
        }
    }
}

# --- 3. Initialize cmake environment if missing ---
if ([string]::IsNullOrWhitespace($env:BINARY_CMAKE) -or -not (Test-Path $env:BINARY_CMAKE)) {
    $cmakeEnvScript = Join-Path $EnvironmentDir "env-cmake.ps1"
    if (Test-Path $cmakeEnvScript) { . $cmakeEnvScript } 
    if ([string]::IsNullOrWhitespace($env:BINARY_CMAKE) -or -not (Test-Path $env:BINARY_CMAKE)) {
        $depcmakeEnvScript = Join-Path $PSScriptRoot "dep-cmake.ps1"
        if (Test-Path $depcmakeEnvScript) { . $depcmakeEnvScript }
        else {
            Write-Error "CRITICAL: Cannot load CMake environment. cmake is missing and $depcmakeEnvScript was not found."
            return
        }
    }
}

# --- 4. Initialize ninja environment if missing ---
if ([string]::IsNullOrWhitespace($env:BINARY_NINJA) -or -not (Test-Path $env:BINARY_NINJA)) {
    $ninjaEnvScript = Join-Path $EnvironmentDir "env-ninja.ps1"
    if (Test-Path $ninjaEnvScript) { . $ninjaEnvScript }
    if ([string]::IsNullOrWhitespace($env:BINARY_NINJA) -or -not (Test-Path $env:BINARY_NINJA)) {
        $depninjaEnvScript = Join-Path $PSScriptRoot "dep-ninja.ps1"
        if (Test-Path $depninjaEnvScript) { . $depninjaEnvScript }
        else {
            Write-Error "CRITICAL: Cannot load ninja environment. ninja is missing and $depninjaEnvScript was not found."
            return
        }
    }
}

# --- 5. Initialize clang environment if missing ---
if ([string]::IsNullOrWhitespace($env:BINARY_CLANG) -or -not (Test-Path $env:BINARY_CLANG)) {
    $llvmEnvScript = Join-Path $EnvironmentDir "env-llvm.ps1"
    if (Test-Path $llvmEnvScript) { . $llvmEnvScript }
    if ([string]::IsNullOrWhitespace($env:BINARY_CLANG) -or -not (Test-Path $env:BINARY_CLANG)) {
        $depllvmEnvScript = Join-Path $PSScriptRoot "dep-llvm.ps1"
        if (Test-Path $depllvmEnvScript) { . $depllvmEnvScript }
        else {
            Write-Error "CRITICAL: Cannot load clang environment. clang is missing and $depllvmEnvScript was not found."
            return
        }
    }
}

# --- 6. Initialize Qt environment if missing ---
if ([string]::IsNullOrWhitespace($env:QT_ROOT) -or -not (Test-Path $env:QT_ROOT)) {
    $qtEnvScript = Join-Path $EnvironmentDir "env-qt.ps1"
    if (Test-Path $qtEnvScript) { . $qtEnvScript }
    if ([string]::IsNullOrWhitespace($env:QT_ROOT) -or -not (Test-Path $env:QT_ROOT)) {
        $depqtEnvScript = Join-Path $PSScriptRoot "dep-qt.ps1"
        if (Test-Path $depqtEnvScript) { . $depqtEnvScript }
        else {
            Write-Error "CRITICAL: Cannot load Qt environment. Qt is missing and $depqtEnvScript was not found."
            return
        }
    }
}

$RootPath = $RootJomWorkspacePath

# --- 6. Path Resolution ---
Push-Location $RootPath

$Source         = Join-Path $RootPath "jom"
$BuildDir       = Join-Path $Source "build_dir"
$RepoUrl        = $JomGitUrl
$Branch         = $JomGitBranch
$CMakeSource    = $Source
$tag_name       = $Branch
$url            = $RepoUrl

# --- 7. Source Management ---
if (Test-Path $Source) {
    Write-Host "Syncing jom ($Branch) at $Source..." -ForegroundColor Cyan
    Set-Location $Source
    git fetch --all
    if ($LASTEXITCODE -ne 0) { Write-Error "Git fetch failed."; Pop-Location; return }
    git reset --hard "origin/$Branch"
    git clean -xdf
    git pull --recurse-submodules --force
    if ($LASTEXITCODE -ne 0) { Write-Error "Git pull failed."; Pop-Location; return }
    $tagCommit = (& git rev-parse --verify HEAD).Trim()
} else {
    Write-Host "Cloning jom ($Branch) into $Source..." -ForegroundColor Cyan
    git clone --recurse-submodules $RepoUrl $Source -b $Branch
    if ($LASTEXITCODE -ne 0) { Write-Error "Git clone failed."; Pop-Location; return }
    Set-Location $Source
    $tagCommit = (& git rev-parse --verify HEAD).Trim()
}

# --- 8. Clean & Build (Shadow Swap Logic) ---
$jomBinPath = Join-Path $jomInstallDir "bin"

$jomExePath = Join-Path $jomInstallDir "jom.exe"
if (-not (Test-Path $jomExePath)) { $jomExePath = Join-Path $jomBinPath "jom.exe" }
$TempJomDir = Join-Path $env:TEMP "jom_old"
$TempJomBinDir = Join-Path $TempJomDir "bin"
$TempJom = Join-Path $TempJomBinDir "jom.exe"
$versionFile = Join-Path $jomInstallDir "version.json"

if (Test-Path $jomExePath) {
    if (Test-Path $TempJom) { Remove-Item $TempJom -Force -ErrorAction SilentlyContinue } else {
        # Create a brand new, temp empty directory
        if (-not (Test-Path $TempJomBinDir))
        {
            Write-Host "[INSTALL] Creating fresh temp directory: $TempJomBinDir" -ForegroundColor Cyan
            New-Item -Path $TempJomBinDir -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null
        }
    }
    
    # 1. Rename the existing binary (Windows allows this while running)
    Move-Item -Path $jomExePath -Destination $TempJom -Force -ErrorAction SilentlyContinue
    Write-Host "[SWAP] Active jom.exe -> $TempJom" -ForegroundColor Yellow

    if (Test-Path $TempJom) {
        Write-Host "Creating global symlink: $TargetLink" -ForegroundColor Cyan
        
        # Remove existing symlink we are creating a new one
        if (Test-Path $TargetLink) { Remove-Item $TargetLink -Force -ErrorAction SilentlyContinue }
        
        # Create the Symbolic Link
        try {
            New-Item -Path $TargetLink -ItemType SymbolicLink -Value $TempJom -ErrorAction Stop | Out-Null
            Write-Host "[LINKED] Jom (Global) -> $TempJom" -ForegroundColor Green
        }
        catch {
            New-Item -Path $TargetLink -ItemType HardLink -Value $TempJom | Out-Null
            Write-Host "[HARDLINKED] Jom (Global) -> $TempJom" -ForegroundColor Green
        }
    }
    else {
        Write-Error "CRITICAL: Could not find jom.exe to symlink at $TempJom"
        if (Test-Path $TargetLink) {
            Write-Host "Cleaning up dead symlink at $TargetLink..." -ForegroundColor Yellow
            Remove-Item $TargetLink -Force -ErrorAction SilentlyContinue
        }
        Pop-Location; return
    }
}

# --- Apply Patch qt version changes ---
$PatchFile = Join-Path $PSScriptRoot "patch\jom_cmake_qt.patch"
if (Test-Path $PatchFile) {
    Write-Host "[PATCH] Verifying custom CMake modifications..." -ForegroundColor Cyan
    
    # 1. Perform a Dry-Run (--check)
    # --ignore-space-change handles the Windows/Linux line-ending (CRLF/LF) headaches
    git apply --check --ignore-space-change "$PatchFile"
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "[PATCH] Verification successful. Applying patch..." -ForegroundColor Green
        
        # 2. Actually apply the patch
        git apply --ignore-space-change --verbose "$PatchFile"
        
        if ($LASTEXITCODE -ne 0) {
            Write-Error "CRITICAL: Patch verification passed but application failed!"
            Pop-Location; return
        }
    }
    else {
        # The check failed, which usually means the repo has changed 
        # or the patch was already partially applied (unlikely after git reset --hard)
        Write-Warning "[PATCH] Patch verification failed. The source may have changed upstream."
        Write-Host "Check the patch file for conflicts or update the patch." -ForegroundColor Yellow
        
        # In a strict build-chain, you might want to stop here:
        Pop-Location; return
    }
}

# Ensure fresh Install directory
if (Test-Path $jomInstallDir) {
    Write-Host "Wiping existing installation at $jomInstallDir..." -ForegroundColor Yellow
    Remove-Item $jomInstallDir -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "[INSTALL] Creating fresh directory: $jomBinPath" -ForegroundColor Cyan
New-Item -Path $jomBinPath -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null

if (Test-Path $BuildDir) { Remove-Item $BuildDir -Recurse -Force -ErrorAction SilentlyContinue }
New-Item -Path $BuildDir -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null

Write-Host "Configuring with Clang/Ninja..." -ForegroundColor Cyan
cmake -G "Ninja" `
    -S "$CMakeSource" `
    -B "$BuildDir" `
    -DCMAKE_POLICY_DEFAULT_CMP0091=NEW `
    -DCMAKE_POLICY_DEFAULT_CMP0109=NEW `
    -DCMAKE_CXX_COMPILER="clang++" `
    -DCMAKE_INSTALL_PREFIX="$jomInstallDir" `
    -DCMAKE_BUILD_TYPE=Release `
    -DBUILD_TESTING=OFF `
    -DCMAKE_CXX_FLAGS="-Wno-deprecated-declarations -D_CRT_SECURE_NO_WARNINGS=1" `
    --no-warn-unused-cli

if ($LASTEXITCODE -ne 0) { Write-Error "jom CMake configuration failed."; Pop-Location; return }

Write-Host "Building and Installing to $jomInstallDir..." -ForegroundColor Green
cmake --build "$BuildDir" --target install --config Release --parallel

if ($LASTEXITCODE -ne 0) { Write-Error "jom Build failed with exit code $LASTEXITCODE"; Pop-Location; return }

Write-Host "Successfully built and installed jom to $jomInstallDir!" -ForegroundColor Green

# Cleanup temporary build debris
Remove-Item $BuildDir -Recurse -Force -ErrorAction SilentlyContinue
if (Test-Path $TempJomDir) {
    Write-Host "Releasing old temp directory..." -ForegroundColor Cyan
    # Give the OS a heartbeat to release file handles
    Start-Sleep -Milliseconds 500
    Remove-Item $TempJomDir -Recurse -Force -ErrorAction SilentlyContinue
}

# Generate Environment Helper with Clean Paths
$jomBinPath = $jomBinPath.TrimEnd('\')
$jomInstallDir = $jomInstallDir.TrimEnd('\')

# --- 9. Symlink to Global Binaries ---
$jomExePath = Join-Path $jomInstallDir "jom.exe"
if (-not (Test-Path $jomExePath)) { $jomExePath = Join-Path $jomBinPath "jom.exe" }

if (Test-Path $jomExePath) {
    $rawVersion = (& $jomExePath /VERSION 2>&1 | Select-Object -First 1).ToString().Trim()
    if ($rawVersion -match 'jom(?:\s+version)?\s+(\d+\.\d+\.\d+)') { $localVersion = $Matches[1] } else { $localVersion = "0.0.0" }
    
    # Save new version state
    $jomVersion = $localVersion
    $versionInfo = @{
        url        = $url;
        tag_name   = $tag_name;
        commit     = $tagCommit;
        version    = $localVersion;
        rawversion = $rawVersion;
        date       = (Get-Date).ToString("yyyy-MM-dd");
        updated_at = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssZ");
        type       = "source_build";
    }
    $versionInfo | ConvertTo-Json | Out-File -FilePath $versionFile -Encoding utf8 -Force

    Write-Host "Creating global symlink: $TargetLink" -ForegroundColor Cyan
    
    # Remove existing symlink we are creating a new one
    if (Test-Path $TargetLink) { Remove-Item $TargetLink -Force -ErrorAction SilentlyContinue }
    
    # Create the Symbolic Link
    try {
        New-Item -Path $TargetLink -ItemType SymbolicLink -Value $jomExePath -ErrorAction Stop | Out-Null
        Write-Host "[LINKED] Jom (Global) -> $jomExePath" -ForegroundColor Green
    } catch {
        New-Item -Path $TargetLink -ItemType HardLink -Value $jomExePath | Out-Null
        Write-Host "[HARDLINKED] Jom (Global) -> $jomExePath" -ForegroundColor Green
    }
    
    Write-Host "[LINKED] Jom is now globally available via %BINARIES_PATH%" -ForegroundColor Green
    
    # --- 10. Create Environment Helper ---
    Write-Host "Generating environment helper script..." -ForegroundColor Cyan
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

    $EnvContent | Out-File -FilePath $jomEnvScript -Encoding utf8 -force
    Write-Host "Created: $jomEnvScript" -ForegroundColor Gray
    
    # Update Current Session
    if (Test-Path $jomEnvScript) { . $jomEnvScript } else {
        Write-Error "jom build install finished but $jomEnvScript was not created.";
        Pop-Location; return
    }

    Write-Host "Jom Version: $(& $jomExePath /VERSION 2>&1 | Select-Object -First 1)" -ForegroundColor Gray
    
    if ($JomWithMachineEnvironment)
    {
        # Generating Machine Environment wich add to the persist registry machine Environment
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

$env:JOM_ROOT = $jomroot
Write-Host "Jom Environment Loaded (Version: $jomversion) (Bin: $jombin)" -ForegroundColor Green
Write-Host "JOM_ROOT: $env:JOM_ROOT" -ForegroundColor Gray
'@  -replace "VALUE_ROOT_PATH", $jomInstallDir `
    -replace "VALUE_BIN_PATH", $jomBinPath `
    -replace "VALUE_VERSION", $jomVersion

        $MachineEnvContent | Out-File -FilePath $jomMachineEnvScript -Encoding utf8 -force
        Write-Host "Created: $jomMachineEnvScript" -ForegroundColor Gray
        
        # --- Interaction: Prompt to apply persistent changes ---
        Write-Host ""
        $choice = Read-Host "Do you want to run the Machine Environment script now to persist jom changes to the Registry? (y/n)"
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
    
    # --- Return to Start ---
    Pop-Location
    Write-Host "Successfully Done! and returned to: $(Get-Location)" -ForegroundColor DarkGreen
} else {
    Write-Error "jom.exe was not found in the $jomBinPath folder."
    if (Test-Path $TargetLink) {
        Write-Host "Cleaning up dead symlink at $TargetLink..." -ForegroundColor Yellow
        Remove-Item $TargetLink -Force -ErrorAction SilentlyContinue
    }
    Pop-Location; return
}
