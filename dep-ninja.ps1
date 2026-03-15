# Copyright 2026 (C) Navegos. DevelVitorF. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
# file:dep-ninja.ps1

param (
    [Parameter(HelpMessage="Path for ninja storage", Mandatory=$false)]
    [string]$ninjaInstallDir = "$env:LIBRARIES_PATH\ninja"
)

Write-Host "--- Ninja Dependency Resolver ---" -ForegroundColor Cyan

# Determine platform-specific script path
if ($IsWindows) {
    $archScript = Join-Path $PSScriptRoot "x64-windows\dep-ninja.ps1"
    
    if (Test-Path $archScript) {
        Write-Host "[OS] Windows detected. Delegating to x64-windows..." -ForegroundColor Gray
        
        # Splatting parameters to pass them cleanly to the child script
        $params = @{
            ninjaInstallDir = $ninjaInstallDir
        }
        
        & $archScript @params
    } else {
        Write-Error "Platform script not found: $archScript"
    }
}
elseif ($IsLinux) {
    Write-Host "[OS] Linux detected. (Logic for linux-vulkan/dep-ninja.ps1 goes here)" -ForegroundColor Yellow
    # & "$PSScriptRoot/linux-vulkan/dep-ninja.ps1" @params
}
else {
    Write-Error "Unsupported Operating System."
}
