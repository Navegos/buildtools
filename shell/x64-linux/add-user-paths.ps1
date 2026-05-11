# SPDX-FileCopyrightText: Copyright (c) 2026 Navegos. @DevelVitorF. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
# project: buildtools
# file: x64-linux/add-user-paths.ps1
# created: 2026-05-09
# lastModified: 2026-05-11

param (
    [Parameter(HelpMessage = "Base path for library storage", Mandatory = $false)]
    [string]$LibrariesDir = "/opt/libs",

    [Parameter(HelpMessage = "Base path for environment-specific configs", Mandatory = $false)]
    [string]$EnvironmentDir = "/opt/libs/environment",

    [Parameter(HelpMessage = "Base path for binaries", Mandatory = $false)]
    [string]$BinariesDir = "/opt/libs/binaries",
    
    [Parameter(HelpMessage = "Base path for build tools", Mandatory = $false)]
    [string]$BuildToolsDir = (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) # BuildTools root folder
)

if (-not $IsLinux) {
    Write-Error "This script is intended to run on Linux. Detected OS does not match."
    return
}

# --- 0. Self-Elevation Logic (MUST be after param block) ---
$IsAdmin = (id -u) -eq 0

if (-not $IsAdmin) {
    Write-Host "Elevation required. Relaunching as root (sudo)..." -ForegroundColor Yellow
    # Pass the parameters to the elevated process so they aren't lost
    $ArgList = @("pwsh", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$PSCommandPath`"")
    foreach ($Parameter in $PSBoundParameters.GetEnumerator()) {
        if ($Parameter.Value -is [switch]) {
            if ($Parameter.Value) { $ArgList += "-$($Parameter.Key)" }
        }
        else {
            $ArgList += "-$($Parameter.Key)"
            $ArgList += "`"$($Parameter.Value)`""
        }
    }
    
    try {
        Start-Process sudo -ArgumentList ($ArgList -join ' ') -Wait -ErrorAction Stop
    }
    catch {
        Write-Error "Failed to elevate. Please run this script with sudo pwsh."
    }
    exit
}

# Use an [ordered] hashtable to ensure dependencies are created in the right sequence
$EnvMapping = [ordered]@{
    "LIBRARIES_PATH"    = $LibrariesDir
    "BUILDTOOLS_PATH"   = $BuildToolsDir
    "ENVIRONMENT_PATH"  = $EnvironmentDir
    "BINARIES_PATH"     = $BinariesDir
}

# Empty WhiteSpace
$ToolsDir = " "
$VSToolsDir = " "
$NVIDIAToolsDir = " "
$AMDToolsDir = " "
$LibToolsDir = " "
$PollToolsDir = " "

$VEnvMapping = [ordered]@{
    "TOOLS_PATH"       = $ToolsDir         # Virtual Env path to share all other related (non polluted like llvm/bin git/cmd) external tools to Env PATH
    "VSTOOLS_PATH"     = $VSToolsDir       # Virtual Env path to share Visual Studio and Microsoft tools to Env PATH (Placeholder on Linux)
    "NVIDIA_PATH"      = $NVIDIAToolsDir   # Virtual Env path to share Nvidia Cuda compilers etc... to Env PATH
    "AMD_PATH"         = $AMDToolsDir      # Virtual Env path to share AMD Rocm HIP compilers etc... to Env PATH
    "EXTCOMPLIBS_PATH" = $LibToolsDir      # Virtual Env path to share all other related libraries tools to Env PATH
    "EXTCOMP_PATH"     = $PollToolsDir     # Virtual Env path to share all other related (polluted like python/bin) external tools to Env PATH
}

Write-Host "--- User Environment Sync Start ---" -ForegroundColor White

$TargetScope = "User"
$ScopeColor = "Yellow"

$ProfileVars = [ordered]@{}
$ProfilePaths = @()

foreach ($Entry in $EnvMapping.GetEnumerator())
{
    $VarName = $Entry.Key
    $TargetPath = $Entry.Value

    # 1. Physical Directory Management
    if (-not (Test-Path -Path $TargetPath))
    {
        New-Item -Path $TargetPath -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null
        if (-not [string]::IsNullOrEmpty($env:SUDO_USER)) {
            & chown -R "$($env:SUDO_USER):$($env:SUDO_USER)" $TargetPath
        }
        Write-Host "[NEW] Created directory: $TargetPath" -ForegroundColor Cyan
    } else {
        Write-Host "[OK] Directory exists: $TargetPath" -ForegroundColor DarkGray
    }

    # 2. Environment Variable Management
    $VarNameValue = (Get-Item "Env:\$VarName" -ErrorAction SilentlyContinue).Value

    # Logic: If missing OR pointing to the wrong place, update it.
    if ([string]::IsNullOrWhitespace($VarNameValue) -or -not (Test-Path "Env:\$VarName") -or $VarNameValue -ne $TargetPath)
    {
        # Update Current Process
        Set-Item -Path "Env:\$VarName" -Value $TargetPath
        $ProfileVars[$VarName] = $TargetPath

        # 3. Path Integration for BINARIES_PATH
        if ($VarName -eq "BUILDTOOLS_PATH" -or $VarName -eq "ENVIRONMENT_PATH" -or $VarName -eq "BINARIES_PATH")
        {
            $ProfilePaths += "`$$VarName"
        
            # Update current session only if not already present
            if ($env:PATH -notlike "*$TargetPath*")
            {
                $env:PATH = "$env:PATH:$TargetPath".Replace("::", ":").Trim(':')
            }
        }

        Write-Host "[UPDATED] ($TargetScope Scope) '$VarName' -> $TargetPath" -ForegroundColor $ScopeColor
    } else {
        Write-Host "[OK] Env Var '$VarName' is correctly mapped." -ForegroundColor DarkGray
        $ProfileVars[$VarName] = $TargetPath
        if ($VarName -eq "BUILDTOOLS_PATH" -or $VarName -eq "ENVIRONMENT_PATH" -or $VarName -eq "BINARIES_PATH") {
            $ProfilePaths += "`$$VarName"
        }
    }
}

foreach ($Entry in $VEnvMapping.GetEnumerator())
{
    $VarName = $Entry.Key
    $TargetPath = $Entry.Value

    # Check if already in environment or default Whitespace.
    $VarNameValue = (Get-Item "Env:\$VarName" -ErrorAction SilentlyContinue).Value
    
    # If missing or default Whitespace.
    if ([string]::IsNullOrWhitespace($VarNameValue))
    {
        # Update Current Process
        Set-Item -Path "Env:\$VarName" -Value $TargetPath
        $ProfileVars[$VarName] = $TargetPath

        # 3. Path Integration
        $ProfilePaths += "`$$VarName"

        # Update current session only if not already present
        if ($env:PATH -notlike "*$TargetPath*")
        {
            $env:PATH = "$env:PATH:$TargetPath".Replace("::", ":").Trim(':')
        }

        Write-Host "[UPDATED] ($TargetScope Scope) '$VarName' -> $TargetPath" -ForegroundColor $ScopeColor
    }
    else {
        Write-Host "[OK] Env Var '$VarName' is correctly mapped." -ForegroundColor DarkGray
        $ProfileVars[$VarName] = $TargetPath
        $ProfilePaths += "`$$VarName"
    }
}

# --- 4. Write to Profile ---
$sudoUser = $env:SUDO_USER
if (-not [string]::IsNullOrEmpty($sudoUser)) {
    $passwdEntry = Get-Content '/etc/passwd' -ErrorAction SilentlyContinue | Where-Object { $_ -match "^${sudoUser}:" } | Select-Object -First 1
    if ($passwdEntry) {
        $targetHome = $passwdEntry.Split(':')[5]
    } else {
        $targetHome = "/home/$sudoUser"
    }
} else {
    $targetHome = "$HOME"
}

$bashrc = "$targetHome/.bashrc"

$blockContent = ""
foreach ($key in $ProfileVars.Keys) {
    $blockContent += "export $key=`"$($ProfileVars[$key])`"`n"
}
if ($ProfilePaths.Count -gt 0) {
    $blockContent += "export PATH=`"`$PATH:$($ProfilePaths -join ':')`"`n"
}

if (Test-Path $bashrc) {
    $bashrcContent = Get-Content $bashrc -Raw

    $legacyRegex = "(?s)\r?\n?# Source BuildTools Begin.*?# Source BuildTools End\r?\n?"
    if ($bashrcContent -match $legacyRegex) {
        $bashrcContent = $bashrcContent -replace $legacyRegex, "`n"
    }

    # Remove legacy .buildtools_user_paths.sh script inclusion and the file itself
    $legacyProfile = "$targetHome/.buildtools_user_paths.sh"
    $bashrcContent = ($bashrcContent -split "`r?\n" | Where-Object { $_ -notlike "*$legacyProfile*" }) -join "`n"
    if (Test-Path $legacyProfile) { Remove-Item $legacyProfile -Force -ErrorAction SilentlyContinue }

    if ($bashrcContent -match "(?s)# BUILDTOOLS_BEGIN\r?\n(.*?)# BUILDTOOLS_END") {
        $existingBlockContent = $Matches[1].TrimEnd()
        $existingLines = $existingBlockContent -split "`r?\n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
        $filteredLines = @()
        foreach ($line in $existingLines) {
            $keep = $true
            foreach ($key in $ProfileVars.Keys) { if ($line -match "^export $key=") { $keep = $false; break } }
            if ($line -match "^export PATH=" -and $line -match ':\$BUILDTOOLS_PATH') { $keep = $false }
            if ($keep) { $filteredLines += $line }
        }
        $finalBlockLines = $filteredLines + ($blockContent -split "`n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        $mergedBlockContent = ($finalBlockLines -join "`n") + "`n"
        $bashrcContent = $bashrcContent -replace "(?s)# BUILDTOOLS_BEGIN\r?\n.*?# BUILDTOOLS_END", "# BUILDTOOLS_BEGIN`n$mergedBlockContent# BUILDTOOLS_END"
        Write-Host "[UPDATED] Updated BUILDTOOLS block in $bashrc" -ForegroundColor Green
    } else {
        $bashrcContent = $bashrcContent.TrimEnd() + "`n`n# BUILDTOOLS_BEGIN`n$blockContent# BUILDTOOLS_END`n"
        Write-Host "[UPDATED] Appended BUILDTOOLS block to $bashrc" -ForegroundColor Green
    }
    
    # Direct Out-File natively preserves existing file ownership and permissions on Linux
    $bashrcContent | Out-File -FilePath $bashrc -Encoding utf8 -Force
}

# --- 5. Developer Mode & Sideloading ---
Write-Host "[OK] Developer Mode and Sideloading concepts are Windows-specific. Skipped." -ForegroundColor DarkGray

# --- 6. Enable Long Paths (MAX_PATH removal) ---
Write-Host "[OK] Long Path support is native to Linux. Skipped." -ForegroundColor DarkGray

Write-Host "--- Sync Complete ---" -ForegroundColor Green
