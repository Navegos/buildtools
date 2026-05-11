# SPDX-FileCopyrightText: Copyright (c) 2026 Navegos. @DevelVitorF. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
# project: buildtools
# file: x64-linux/get-pwsh.ps1
# created: 2026-05-12
# lastModified: 2026-05-11

param (
    [Parameter(HelpMessage = "Default installation directory")]
    [string]$powershellInstallDir = "/opt/microsoft/powershell/7"
)

# --- 0. Self-Elevation Logic ---
$IsAdmin = (id -u) -eq 0

if (-not $IsAdmin) {
    Write-Host "--- Elevation required. Relaunching with sudo... ---" -ForegroundColor Yellow
    $ArgList = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $PSCommandPath, "-powershellInstallDir", $powershellInstallDir)
    try {
        Start-Process sudo -ArgumentList (("pwsh") + $ArgList) -Wait -ErrorAction Stop
    }
    catch {
        Write-Error "Failed to elevate. Please run this script with sudo pwsh."
    }
    exit
}

Write-Host "--- PowerShell Management ---" -ForegroundColor Cyan

function Install-OrUpdatePwsh {
    Write-Host "--- PowerShell 7 Provisioning ---" -ForegroundColor Cyan
    
    Write-Host "Fetching latest release from GitHub API..." -ForegroundColor Yellow
    
    # Dynamically find the x64 tar.gz URL for the latest stable release
    $releaseUrl = "https://api.github.com/repos/PowerShell/PowerShell/releases/latest"
    try {
        $release = Invoke-RestMethod -Uri $releaseUrl -ErrorAction Stop
        $asset = $release.assets | Where-Object { $_.name -match "linux-x64\.tar\.gz$" } | Select-Object -First 1
        $downloadUrl = $asset.browser_download_url
    } catch {
        Write-Error "Failed to fetch GitHub release data."
        exit 1
    }
    
    if (-not $downloadUrl) {
        Write-Error "Could not find a valid x64 tar.gz in the latest GitHub release."
        exit 1
    }
    
    $tempTar = "/tmp/pwsh_install.tar.gz"
    Write-Host "Downloading: $($asset.name)..." -ForegroundColor DarkGray
    try {
        Invoke-WebRequest -Uri $downloadUrl -OutFile $tempTar -ErrorAction Stop
    } catch {
        Write-Error "Download failed."
        exit 1
    }
    
    Write-Host "Installing tar.gz to $powershellInstallDir..." -ForegroundColor DarkGray
    if (-not (Test-Path $powershellInstallDir)) {
        New-Item -ItemType Directory -Path $powershellInstallDir -Force | Out-Null
    }
    
    & tar -xzf $tempTar -C $powershellInstallDir
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Extraction failed."
        exit 1
    }
    
    # Ensure the binary is executable
    & chmod +x "$powershellInstallDir/pwsh"
    
    Remove-Item $tempTar -Force -ErrorAction SilentlyContinue
    
    # Create a symbolic link in /usr/bin to expose pwsh to standard PATH
    Write-Host "Creating symlink in /usr/bin/pwsh..." -ForegroundColor DarkGray
    if (Test-Path "/usr/bin/pwsh") {
        Remove-Item "/usr/bin/pwsh" -Force
    }
    New-Item -ItemType SymbolicLink -Path "/usr/bin/pwsh" -Target "$powershellInstallDir/pwsh" | Out-Null
    
    # Add to PATH in .bashrc
    Write-Host "Adding $powershellInstallDir to PATH in .bashrc..." -ForegroundColor DarkGray
    
    $sudoUser = $env:SUDO_USER
    if (-not [string]::IsNullOrEmpty($env:SUDO_USER)) {
        $passwdEntry = Get-Content '/etc/passwd' -ErrorAction SilentlyContinue | Where-Object { $_ -match "^${sudoUser}:" } | Select-Object -First 1
        if ($passwdEntry) {
            $targetBashrc = Join-Path $passwdEntry.Split(':')[5] ".bashrc"
        } else {
            $targetBashrc = "/home/$sudoUser/.bashrc"
        }
    } else {
        $targetBashrc = "$HOME/.bashrc"
    }
    
    $pwshExport = "export PATH=`"`$PATH:$powershellInstallDir`""
    # Cleanup: Remove any line containing $powershellInstallDir, and append the current target (to avoid dups)
    if (Test-Path $targetBashrc) {
        $bashrcContent = Get-Content -Path $targetBashrc -Raw
        $CleanedBashrc = ($bashrcContent -split "`r?\n" | Where-Object { $_ -notlike "*$powershellInstallDir*" }) -join "`n"
        
        if ($CleanedBashrc -match "(?s)# BUILDTOOLS_BEGIN\r?\n(.*?)# BUILDTOOLS_END") {
            $blockContent = $Matches[1].TrimEnd()
            $blockContent = if ([string]::IsNullOrWhiteSpace($blockContent)) { "$pwshExport`n" } else { "$blockContent`n$pwshExport`n" }
            $NewBashrc = $CleanedBashrc -replace "(?s)# BUILDTOOLS_BEGIN\r?\n.*?# BUILDTOOLS_END", "# BUILDTOOLS_BEGIN`n$blockContent# BUILDTOOLS_END"
        } else {
            $NewBashrc = $CleanedBashrc.TrimEnd() + "`n`n# BUILDTOOLS_BEGIN`n$pwshExport`n# BUILDTOOLS_END`n"
        }
    } else {
        $NewBashrc = "# BUILDTOOLS_BEGIN`n$pwshExport`n# BUILDTOOLS_END`n"
    }
    
    # Direct Out-File natively preserves existing file ownership and permissions on Linux
    $NewBashrc | Out-File -FilePath $targetBashrc -Encoding ascii -Force
    
    Write-Host "[SUCCESS] PowerShell 7 provisioned at $powershellInstallDir" -ForegroundColor Green
}

# --- 3. Run ---
Install-OrUpdatePwsh

# --- 4. Final Verification ---
try {
    $currentVer = & pwsh -v 2>$null
    if (-not $currentVer) { $currentVer = "Not Found" }
} catch {
    $currentVer = "Not Found"
}

Write-Host "Current Session PowerShell Version: $currentVer" -ForegroundColor White
Write-Host "--- Setup Complete ---" -ForegroundColor Green
