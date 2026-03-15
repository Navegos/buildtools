# Copyright 2026 (C) Navegos. DevelVitorF. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
# file:x64-windows/dep-cygwin.ps1

param (
    [Parameter(HelpMessage="Path for cygwin storage", Mandatory=$false)]
    [string]$cygwinInstallDir = "$env:LIBRARIES_PATH\cygwin"
)

# 1. Bootstrap Environment if variables are missing
if ([string]::IsNullOrWhitespace($env:ENVIRONMENT_PATH) -or -not (Test-Path $env:ENVIRONMENT_PATH) -or [string]::IsNullOrWhitespace($env:BINARIES_PATH) -or -not (Test-Path $env:BINARIES_PATH) -or [string]::IsNullOrWhitespace($env:LIBRARIES_PATH) -or -not (Test-Path $env:LIBRARIES_PATH)) {
    Write-Error "User Environment variables missing. Please run adduserpaths.ps1 -LibrariesDir 'Path\for\Libraries' BinariesDir 'Path\for\Binaries' -EnvironmentDir 'Path\for\Environment'"
    return
}

$EnvironmentDir = "$env:ENVIRONMENT_PATH"

$setupExe = Join-Path $env:TEMP "cygwin-setup.exe"
$cygwinBinPath = Join-Path $cygwinInstallDir "bin"

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
    if (!(Test-Path $cygwinInstallDir)) { New-Item -Path $cygwinInstallDir -ItemType Directory -Force | Out-Null }
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
    "--local-package-dir", (Join-Path $cygwinInstallDir "downloads"),
    "--site", "http://mirrors.kernel.org/sourceware/cygwin/",
    "--no-desktop", "--no-shortcuts", "--no-startmenu",
    "--quiet-mode",
    "--upgrade-also",
    "--packages", $packages
)

$process = Start-Process -FilePath $setupExe -ArgumentList $installArgs -Wait -NoNewWindow -PassThru
if ($process.ExitCode -eq 0 -and (Test-Path (Join-Path $cygwinInstallDir "bin\bash.exe"))) {
    Write-Host "Cygwin is up to date with all required packages." -ForegroundColor Green
    
    # 6. Generate/Update Environment Helper
    
    $cygwinEnvScript = Join-Path $EnvironmentDir "env-cygwin.ps1"
    
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
if ($env:PATH -notlike "*$cygwinbin*") { $env:PATH = $cygwinbin + ";" + $env:PATH }
Write-Host "CYGWIN Environment Loaded (Bin: $cygwinbin)" -ForegroundColor Green
Write-Host "CYGWIN_ROOT: $env:CYGWIN_ROOT" -ForegroundColor Gray
'@ -replace "VALUE_BIN_PATH", $cygwinBinPath -replace "VALUE_ROOT_PATH", $cygwinInstallDir

    $EnvContent | Out-File -FilePath $cygwinEnvScript -Encoding utf8
    
    # 7. Update Current Session
    if (Test-Path $cygwinEnvScript) { . $cygwinEnvScript } else {
        Write-Error "cygwin dep install finished but $cygwinEnvScript was not created."
        return
    }
    Write-Host "Session updated with Cygwin binaries." -ForegroundColor Gray
} else {
    Write-Error "Cygwin setup exited with code $($process.ExitCode)"
    return
}

# Cleanup
if (Test-Path $setupExe) { Remove-Item $setupExe -Force }
