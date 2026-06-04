# SPDX-FileCopyrightText: Copyright (c) 2026 Navegos. @DevelVitorF. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
# project: buildtools
# file: env.ps1

$binName = if ($IsWindows -or ($env:OS -eq "Windows_NT")) { "build-helper.exe" } else { "build-helper" }
$rustBin = Join-Path $PSScriptRoot "target\release\$binName"

if (-not (Test-Path $rustBin)) {
    Write-Host "[BUILD] Compiling Rust build helper..." -ForegroundColor Gray
    if (Get-Command cargo -ErrorAction SilentlyContinue) {
        $prevCwd = Get-Location
        Set-Location $PSScriptRoot
        cargo build --release --bin build-helper
        Set-Location $prevCwd
    }
    
    if (-not (Test-Path $rustBin)) {
        Write-Error "Failed to locate or compile Rust build helper at $rustBin. Make sure Rust/cargo is installed."
        exit 1
    }
}

$env:BUILDTOOLS_CALLER = "env.ps1"
& $rustBin @args
exit $LASTEXITCODE
