# SPDX-FileCopyrightText: Copyright (c) 2026 Navegos. @DevelVitorF. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
# project: buildtools
# file: build.ps1
# created: 2026-05-06
# lastModified: 2026-05-09

if ($args.Count -lt 1) {
    Write-Error "Usage: .\build.ps1 <action> [target] [arguments...]"
    Write-Host "Example: .\build.ps1 get pwsh -powershellInstallDir 'C:\pwsh'" -ForegroundColor Gray
    Write-Host "Example: .\build.ps1 build zstd -forceCleanup" -ForegroundColor Gray
    return
}

$shellDir = Join-Path $PSScriptRoot "shell"
$targetScript = $null
$scriptIndex = -1

# Iterate backwards to find the longest matching script name (e.g., "add user paths" -> add-user-paths.ps1)
for ($i = $args.Count; $i -gt 0; $i--) {
    $testName = ($args[0..($i - 1)] -join "-")
    if (-not $testName.EndsWith(".ps1", [System.StringComparison]::OrdinalIgnoreCase)) {
        $testName += ".ps1"
    }
    
    # 1. Fast check in root shell directory
    $directPath = Join-Path $shellDir $testName
    if (Test-Path $directPath) {
        $targetScript = $directPath
        $scriptIndex = $i
        break
    }
    
    # 2. Recursive check if not in root (e.g., inside x64-windows)
    $found = Get-ChildItem -Path $shellDir -Filter $testName -Recurse -File -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($found) {
        $targetScript = $found.FullName
        $scriptIndex = $i
        break
    }
}

if ($targetScript) {
    Write-Host "[BUILD] Delegating to $targetScript..." -ForegroundColor Cyan
    if ($args.Count -gt $scriptIndex) {
        # Splat the remaining arguments dynamically to the discovered script
        $passArgs = $args[$scriptIndex..($args.Count - 1)]
        & $targetScript @passArgs
    } else {
        & $targetScript
    }
}
else {
    $attemptedName = ($args -join "-") + ".ps1"
    Write-Error "Target script not found matching args. Attempted: $attemptedName"
}
