# Copyright 2026 (C) Navegos. DevelVitorF. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
# file:x64-windows/dep-cygwin.ps1

param (
    [Parameter(HelpMessage = "Path for cygwin storage", Mandatory = $false)]
    [string]$cygwinInstallDir = "$env:LIBRARIES_PATH\cygwin",
    
    [Parameter(HelpMessage = "Force a full purge of the local Cygwin version before continuing", Mandatory = $false)]
    [switch]$forceCleanup,
    
    [Parameter(HelpMessage = "Add's Cygwin Machine Environment Variables. Requires Machine Administrator Rights.", Mandatory = $false)]
    [switch]$withMachineEnvironment
)

# Capture parameters
$CygwinWithMachineEnvironment = $withMachineEnvironment
$CygwinForceCleanup = $forceCleanup

# 1. Bootstrap Environment if variables are missing
if ([string]::IsNullOrWhitespace($env:ENVIRONMENT_PATH) -or -not (Test-Path $env:ENVIRONMENT_PATH) -or [string]::IsNullOrWhitespace($env:BINARIES_PATH) -or -not (Test-Path $env:BINARIES_PATH) -or [string]::IsNullOrWhitespace($env:LIBRARIES_PATH) -or -not (Test-Path $env:LIBRARIES_PATH)) {
    Write-Error "User Environment variables missing. Please run adduserpaths.ps1 -LibrariesDir 'Path\for\Libraries' BinariesDir 'Path\for\Binaries' -EnvironmentDir 'Path\for\Environment'"
    return
}

$EnvironmentDir = "$env:ENVIRONMENT_PATH"

$setupExe = Join-Path $env:TEMP "cygwin-setup.exe"
$cygwinBinPath = Join-Path $cygwinInstallDir "bin"
$cygwinEnvScript = Join-Path $EnvironmentDir "env-cygwin.ps1"
$cygwinMachineEnvScript = Join-Path $EnvironmentDir "machine-env-cygwin.ps1"

# --- 1. Cleanup Mechanism ---
function Invoke-cygwinVersionPurge {
    param ([string]$InstallPath)
    Write-Host "--- Initiating cygwin Purge ---" -ForegroundColor Cyan

    if ($CygwinWithMachineEnvironment)
    {
        $cygwinCleanMachineEnvScript = Join-Path $env:TEMP "clean-machine-env-cygwin.ps1"

        # Generating Clean Machine Environment wich removes the persist registry machine Environment
        $CleanMachineEnvContent = @'
# cygwin Clean Machine Environment Setup

# --- 0. Self-Elevation Logic ---
$IsAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$ScopeColor = "Cyan"

if (-not $IsAdmin) {
    Write-Host "Elevation required to clean cygwin system variables. Relaunching as Administrator..." -ForegroundColor Yellow
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

$cygwinroot = "VALUE_ROOT_PATH"

$TargetScope = if ($IsAdmin) { "Machine" } else { "User" }
$RegPath = if ($IsAdmin) { "System\CurrentControlSet\Control\Session Manager\Environment" } else { "Environment" }
$RegRoot = if ($IsAdmin) { "LocalMachine" } else { "CurrentUser" }

# 1. Registry Cleanup (TOOLS_PATH & EXTCOMP_PATH)
$RegKey = [Microsoft.Win32.Registry]::$RegRoot.OpenSubKey($RegPath, $true)

foreach ($VarName in @("TOOLS_PATH", "EXTCOMP_PATH")) {
    # Open the registry key directly to read the RAW (unexpanded) string
    $RawPath = $RegKey.GetValue($VarName, "", [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)

    # Cleanup: Remove empty strings, any path containing $VarName,
    $CleanPath = ($RawPath -split ';' | Where-Object { $_ -notlike "*$cygwinroot*" }) -join ";"

    # Save as ExpandString
    $RegKey.SetValue($VarName, $CleanPath, [Microsoft.Win32.RegistryValueKind]::ExpandString)

    Write-Host "  [CLEANED] $VarName" -ForegroundColor Gray
}
$RegKey.Close()

Write-Host "[REMOVED] ($TargetScope) all '*$cygwinroot*' removed from TOOLS_PATH" -ForegroundColor $ScopeColor
'@  -replace "VALUE_ROOT_PATH", $InstallPath

        $CleanMachineEnvContent | Out-File -FilePath $cygwinCleanMachineEnvScript -Encoding utf8
        Write-Host "Created: $cygwinCleanMachineEnvScript" -ForegroundColor Gray
        
        # --- Interaction: Prompt to remove persistent changes ---
        Write-Host ""
        $choice = Read-Host "Administrator rights required to Clean Machine Environment cygwin changes? (y/n)"
        if ($choice -eq 'y' -or $choice -eq 'Y') {
            Write-Host "Executing $cygwinCleanMachineEnvScript..." -ForegroundColor Yellow
            try {
                # Start the generated script. It handles its own elevation logic.
                & $cygwinCleanMachineEnvScript
            }
            catch {
                Write-Error "Failed to execute the Clean Machine Environment script: $($_.Exception.Message)"
                return
            }
        }
        else {
            Write-Error "Skipped Clean Machine Environment cygwin changes."
            return
        }

        # Cleanup
        Remove-Item $cygwinCleanMachineEnvScript -Recurse -Force -ErrorAction SilentlyContinue
    }

    # 2. Filesystem Clean (Requires checking for locked files)
    # delete everithing we create don't fail later
    if (Test-Path $cygwinEnvScript) {
        Write-Host "  [DELETING] $cygwinEnvScript" -ForegroundColor Yellow
        Remove-Item $cygwinEnvScript -Recurse -Force -ErrorAction SilentlyContinue
    }
    if (Test-Path $cygwinMachineEnvScript) {
        Write-Host "  [DELETING] $cygwinMachineEnvScript" -ForegroundColor Yellow
        Remove-Item $cygwinMachineEnvScript -Recurse -Force -ErrorAction SilentlyContinue
    }
    if (Test-Path $InstallPath) {
        Write-Host "  [DELETING] $InstallPath" -ForegroundColor Yellow
        Remove-Item $InstallPath -Recurse -Force -ErrorAction SilentlyContinue
    }
    
    # remove local Env variables for current session
    Get-ChildItem Env:\CYGWIN_PATH* | Remove-Item -ErrorAction SilentlyContinue
    Get-ChildItem Env:\CYGWIN_ROOT* | Remove-Item -ErrorAction SilentlyContinue
    Get-ChildItem Env:\CYGWIN_BIN* | Remove-Item -ErrorAction SilentlyContinue

    Write-Host "--- cygwin Purge Complete ---" -ForegroundColor Green
}

if ($CygwinForceCleanup) {
    Invoke-cygwinVersionPurge -InstallPath $cygwinInstallDir
}

# We are not adding versioning, so the installer updates the packages itself

# 4. Define Packages (Add or remove as needed for your Clang/ICU/Iconv build)
$packages = @(
    "make", "autoconf", "automake", "libtool", "pkg-config", "m4", "patch", "wget",
    "git", "curl", "gcc-core=16.0.0+20260208-0.1", "gcc-g++=16.0.0+20260208-0.1", "clang=21.1.4-1", "llvm=21.1.4-1", "windres",
    "mingw64-x86_64-gcc-core", "mingw64-x86_64-gcc-g++", "mingw64-x86_64-headers", "mingw64-x86_64-runtime", "mingw64-x86_64-binutils",
    "mingw64-x86_64-clang", "mingw64-x86_64-llvm", "mingw64-x86_64-llvm-static",
    "python39", "python39-clang", "python39-devel", "python39-pip",
    "python312", "python312-clang", "python312-devel", "python312-pip"
) -join ","

# 3. Check Installation State
$isInstalled = Test-Path (Join-Path $cygwinInstallDir "bin\bash.exe")

if ($isInstalled) {
    Write-Host "Cygwin detected. Checking for missing packages and updates..." -ForegroundColor Cyan
} else {
    Write-Host "Cygwin not found. Starting fresh installation..." -ForegroundColor Yellow
    if (-not (Test-Path $cygwinInstallDir)) { New-Item -Path $cygwinInstallDir -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null }
}

# 4. Download/Update Installer
Write-Host "Fetching latest Cygwin installer..." -ForegroundColor Gray
Invoke-WebRequest -Uri "https://www.cygwin.com/setup-x86_64.exe" -OutFile $setupExe

# 5. Run Installation / Upgrade
# Using --upgrade-also to ensure all existing packages stay current
# Using --packages to ensure the specific list is present
Write-Host "Running Cygwin Setup (Unattended)..." -ForegroundColor Cyan
$installArgs = @(
    "--root", $cygwinInstallDir,
    "--local-package-dir", (Join-Path $cygwinInstallDir "mirrors"),
    "--site", "http://mirrors.kernel.org/sourceware/cygwin/",
    "--no-desktop", "--no-shortcuts", "--no-startmenu",
    "--quiet-mode",
    "--upgrade-also",
    "--packages", $packages
)

$process = Start-Process -FilePath $setupExe -ArgumentList $installArgs -Wait -NoNewWindow -PassThru
if ($process.ExitCode -eq 0 -and (Test-Path (Join-Path $cygwinInstallDir "bin\bash.exe"))) {
    Write-Host "Cygwin is up to date with all required packages." -ForegroundColor Green
    
    # Generate Environment Helper with Clean Paths
    $cygwinBinPath = $cygwinBinPath.TrimEnd('\')
    $cygwinInstallDir = $cygwinInstallDir.TrimEnd('\')

    # Using a literal here-string with -replace to avoid accidental expansion of $env:PATH during creation
    $EnvContent = @'
# CYGWIN Environment Setup
$cygwinroot = "VALUE_ROOT_PATH"
$cygwinbin = "VALUE_BIN_PATH"
$env:CYGWIN_PATH = $cygwinroot
$env:CYGWIN_ROOT = $cygwinroot
$env:CYGWIN_BIN = $cygwinbin
"$cygwinroot", "$cygwinbin" | ForEach-Object { if ($env:PATH -notlike "*$_*") { $env:PATH = $_ + ";" + $env:PATH; $env:PATH = ($env:PATH).Replace(";;", ";") } }
Write-Host "CYGWIN Environment Loaded (Bin: $cygwinbin)" -ForegroundColor Green
Write-Host "CYGWIN_ROOT: $env:CYGWIN_ROOT" -ForegroundColor Gray
'@  -replace "VALUE_BIN_PATH", $cygwinBinPath `
    -replace "VALUE_ROOT_PATH", $cygwinInstallDir

    $EnvContent | Out-File -FilePath $cygwinEnvScript -Encoding utf8
    
    # 7. Update Current Session
    if (Test-Path $cygwinEnvScript) { . $cygwinEnvScript } else {
        Write-Error "cygwin dep install finished but $cygwinEnvScript was not created."
        return
    }
    Write-Host "Session updated with Cygwin binaries." -ForegroundColor Gray

    if ($CygwinWithMachineEnvironment)
    {
        # Generating Machine Environment wich add to the persist registry machine Environment
        $MachineEnvContent = @'
# Cygwin Machine Environment Setup

# --- 0. Self-Elevation Logic ---
$IsAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$ScopeColor = "Cyan"

if (-not $IsAdmin) {
    Write-Host "Elevation required to set Cygwin system variables. Relaunching as Administrator..." -ForegroundColor Yellow
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

$cygwinroot = "VALUE_ROOT_PATH"
$cygwinbin = "VALUE_BIN_PATH"

$TargetScope = if ($IsAdmin) { "Machine" } else { "User" }
$RegPath = if ($IsAdmin) { "System\CurrentControlSet\Control\Session Manager\Environment" } else { "Environment" }
$RegRoot = if ($IsAdmin) { "LocalMachine" } else { "CurrentUser" }

# Open the registry key once
$RegKey = [Microsoft.Win32.Registry]::$RegRoot.OpenSubKey($RegPath, $true)

# Open the registry key directly to read the RAW (unexpanded) string
$CurrentRawToolsPath = $RegKey.GetValue("TOOLS_PATH", "", [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
$CurrentRawExtCompPath = $RegKey.GetValue("EXTCOMP_PATH", "", [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)

# Check for both critical folders
if ($CurrentRawToolsPath -notlike "*$cygwinroot*") {
    Write-Host "[PATH] Appending cygwin root path to $TargetScope Environment Registry..." -ForegroundColor Cyan
    # Build clean addition
    $CleanPath = $CurrentRawToolsPath.TrimEnd(';')
    if ($CurrentRawToolsPath -notlike "*$cygwinroot*") { $CleanPath += ";$cygwinroot" }

    # Ensure windows path end dont's wrap
    $CleanPath = ($CleanPath + ";").Replace(";;", ";")

    $RegKey.SetValue("TOOLS_PATH", $CleanPath, [Microsoft.Win32.RegistryValueKind]::ExpandString)
}
if ($CurrentRawExtCompPath -notlike "*$cygwinbin*") {
    Write-Host "[PATH] Appending Cygwin Scripts path to $TargetScope Environment Registry..." -ForegroundColor Cyan
    # Build clean addition
    $CleanPath = $CurrentRawExtCompPath.TrimEnd(';')
    if ($CurrentRawExtCompPath -notlike "*$cygwinbin*") { $CleanPath += ";$cygwinbin" }

    # Ensure windows path end dont's wrap
    $CleanPath = ($CleanPath + ";").Replace(";;", ";")

    $RegKey.SetValue("EXTCOMP_PATH", $CleanPath, [Microsoft.Win32.RegistryValueKind]::ExpandString)
}
$RegKey.Close()

$env:CYGWIN_ROOT = $cygwinroot
Write-Host "cygwin Environment Loaded (Version: $cygwinversion) (Bin: $cygwinbin)" -ForegroundColor Green
Write-Host "CYGWIN_ROOT: $env:CYGWIN_ROOT" -ForegroundColor Gray
'@  -replace "VALUE_ROOT_PATH", $cygwinInstallDir `
    -replace "VALUE_BIN_PATH", $cygwinBinPath

        $MachineEnvContent | Out-File -FilePath $cygwinMachineEnvScript -Encoding utf8
        Write-Host "Created: $cygwinMachineEnvScript" -ForegroundColor Gray
        
        # --- Interaction: Prompt to apply persistent changes ---
        Write-Host ""
        $choice = Read-Host "Do you want to run the Machine Environment script now to persist Cygwin changes to the Registry? (y/n)"
        if ($choice -eq 'y' -or $choice -eq 'Y') {
            Write-Host "Executing $cygwinMachineEnvScript..." -ForegroundColor Yellow
            try {
                # Start the generated script. It handles its own elevation logic.
                & $cygwinMachineEnvScript
            }
            catch {
                Write-Error "Failed to execute the Machine Environment script: $($_.Exception.Message)"
            }
        }
        else {
            Write-Host "Skipped persistent registry update. You can run it later at: $cygwinMachineEnvScript" -ForegroundColor Gray
        }
    }
} else {
    Write-Error "Cygwin setup exited with code $($process.ExitCode)"
    return
}

# Cleanup
if (Test-Path $setupExe) { Remove-Item $setupExe -Force -ErrorAction SilentlyContinue }
