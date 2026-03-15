# Copyright 2026 (C) Navegos. DevelVitorF. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
# file:x64-windows/dep-llvm.ps1

param (
    [Parameter(HelpMessage="Path for llvm storage", Mandatory=$false)]
    [string]$llvmInstallDir = "$env:LIBRARIES_PATH\llvm"
)

# 1. Bootstrap Environment if variables are missing
if ([string]::IsNullOrWhitespace($env:ENVIRONMENT_PATH) -or -not (Test-Path $env:ENVIRONMENT_PATH) -or [string]::IsNullOrWhitespace($env:BINARIES_PATH) -or -not (Test-Path $env:BINARIES_PATH) -or [string]::IsNullOrWhitespace($env:LIBRARIES_PATH) -or -not (Test-Path $env:LIBRARIES_PATH)) {
    Write-Error "User Environment variables missing. Please run adduserpaths.ps1 -LibrariesDir 'Path\for\Libraries' BinariesDir 'Path\for\Binaries' -EnvironmentDir 'Path\for\Environment'"
    return
}

$EnvironmentDir = "$env:ENVIRONMENT_PATH"

$clangCheck = Get-Command clang -ErrorAction SilentlyContinue
$llvmBinPath = Join-Path $llvmInstallDir "bin"

if ($clangCheck) {
    Write-Host "LLVM/Clang is already installed at: $($clangCheck.Source)" -ForegroundColor Green
    
    # 1. Locate the bin folder and the root folder
    $llvmBinPath = Split-Path -Path $clangCheck.Source -Parent
    $llvmInstallDir = Split-Path -Path $llvmBinPath -Parent
} else {
    Write-Host "LLVM not found. Starting installation from .tar.xz..." -ForegroundColor Yellow

    if (!(Test-Path $llvmInstallDir)) { 
        New-Item -Path $llvmInstallDir -ItemType Directory -Force | Out-Null 
    }

    # 4. Get latest release from GitHub
    $repo = "llvm/llvm-project"
    try {
        $latestRelease = Invoke-RestMethod -Uri "https://api.github.com/repos/$repo/releases/latest"
        # Specifically target the windows-msvc .tar.xz asset
        $asset = $latestRelease.assets | Where-Object { $_.name -match "clang\+llvm-.*-x86_64-pc-windows-msvc\.tar\.xz$" } | Select-Object -First 1
        
        if (!$asset) {
            Write-Error "Could not find a .tar.xz asset for Windows x64. Check GitHub release names."
            return
        }

        $archiveFile = Join-Path $env:TEMP $asset.name

        Write-Host "Downloading $($asset.name)..." -ForegroundColor Cyan
        Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $archiveFile

        # 5. Extract and Flatten
        Write-Host "Extracting to temporary location..." -ForegroundColor Cyan
        $tempExtractPath = Join-Path $env:TEMP "llvm_extract_$(Get-Random)"
        New-Item -ItemType Directory -Path $tempExtractPath -Force | Out-Null

        # Using Windows native tar.exe to handle .tar.xz
        Write-Host "Decompressing LLVM (this may take a minute)..." -ForegroundColor Gray
        tar -xf $archiveFile -C $tempExtractPath

        # Find the root folder inside (usually clang+llvm-version-x86_64-pc-windows-msvc)
        $internalRoot = Get-ChildItem -Path $tempExtractPath -Directory | Select-Object -First 1

        if ($internalRoot) {
            Write-Host "Flattening to $llvmInstallDir..." -ForegroundColor Gray
            Get-ChildItem -Path $internalRoot.FullName | ForEach-Object {
                Move-Item -Path $_.FullName -Destination $llvmInstallDir -Force
            }
        }

        # Cleanup
        Remove-Item $archiveFile -Force
        Remove-Item $tempExtractPath -Recurse -Force
        
        Write-Host "llvm Installation Complete!" -ForegroundColor DarkGreen
    }
    catch {
        Write-Error "Failed to install LLVM: $($_.Exception.Message)"
        return # Stop execution on failure
    }
}

# Finalize Environment Helper
if (Test-Path (Join-Path $llvmBinPath "clang.exe")) {
    #  Create Environment Helper
    Write-Host "Generating environment helper script..." -ForegroundColor Cyan
    
    $llvmEnvScript = Join-Path $EnvironmentDir "env-llvm.ps1"

    # Generate Environment Helper with Clean Paths
    $llvmBinPath = $llvmBinPath.TrimEnd('\')
    $llvmInstallDir = $llvmInstallDir.TrimEnd('\')

    # Using a literal here-string with -replace to avoid accidental expansion of $env:PATH during creation
    $EnvContent = @'
# LLVM Environment Setup
$llvmbin = "VALUE_BIN_PATH"
$llvmroot = "VALUE_ROOT_PATH"
$env:LLVM_PATH = $llvmroot
$env:LLVM_ROOT = $llvmroot
$env:LLVM_BIN = $llvmbin
if ($env:PATH -notlike "*$llvmbin*") { $env:PATH = $llvmbin + ";" + $env:PATH }
Write-Host "LLVM Environment Loaded (Bin: $llvmbin)" -ForegroundColor Green
Write-Host "LLVM_ROOT: $env:LLVM_ROOT" -ForegroundColor Gray
'@ -replace "VALUE_BIN_PATH", $llvmBinPath -replace "VALUE_ROOT_PATH", $llvmInstallDir

    $EnvContent | Out-File -FilePath $llvmEnvScript -Encoding utf8

    # Update Current Session
    if (Test-Path $llvmEnvScript) { . $llvmEnvScript } else {
        Write-Error "llvm dep install finished but $llvmEnvScript was not created."
        return
    }
    Write-Host "Clang Version: $(clang --version | Select-Object -First 1)" -ForegroundColor Gray
} else {
    Write-Error "clang.exe was not found in the $llvmBinPath folder."
    return
}
