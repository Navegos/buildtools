# Copyright 2026 (C) Navegos. DevelVitorF. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
# file:x64-windows/adduserpaths.ps1

param (
    [Parameter(HelpMessage="Base path for library storage", Mandatory=$false)]
    [string]$LibrariesDir = "C:\libs",

    [Parameter(HelpMessage="Base path for environment-specific configs", Mandatory=$false)]
    [string]$EnvironmentDir = "C:\libs\environment",

    [Parameter(HelpMessage="Base path for binaries", Mandatory=$false)]
    [string]$BinariesDir = "C:\libs\binaries",
    
    [Parameter(HelpMessage="Base path for build tools", Mandatory=$false)]
    [string]$BuildToolsDir = (Split-Path -Path $PSScriptRoot -Parent) # BuildTools root folder
)

# --- 0. Self-Elevation Logic (MUST be after param block) ---
$IsAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $IsAdmin) {
    Write-Host "Elevation required. Relaunching as Administrator..." -ForegroundColor Yellow
    # Pass the parameters to the elevated process so they aren't lost
    $Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    if ($PSBoundParameters.Count -gt 0) {
        foreach ($Key in $PSBoundParameters.Keys) {
            $Arguments += " -$Key `"$($PSBoundParameters[$Key])`""
        }
    }
    
    try {
        Start-Process pwsh.exe -ArgumentList $Arguments -Verb RunAs -ErrorAction Stop
    } catch {
        Write-Error "Failed to elevate. Please right-click PowerShell and 'Run as Administrator'."
    }
    exit
}

# Use an [ordered] hashtable to ensure dependencies are created in the right sequence
$EnvMapping = [ordered]@{
    "LIBRARIES_PATH"    = $LibrariesDir
    "ENVIRONMENT_PATH"  = $EnvironmentDir
    "BINARIES_PATH"     = $BinariesDir
    "BUILDTOOLS_PATH"   = $BuildToolsDir
}

Write-Host "--- User Environment Sync Start ---" -ForegroundColor White

foreach ($Entry in $EnvMapping.GetEnumerator()) {
    $VarName = $Entry.Key
    $TargetPath = $Entry.Value

    # 1. Physical Directory Management
    if (!(Test-Path -Path $TargetPath)) {
        New-Item -ItemType Directory -Path $TargetPath -Force | Out-Null
        Write-Host "[NEW] Created directory: $TargetPath" -ForegroundColor Cyan
    } else {
        Write-Host "[OK] Directory exists: $TargetPath" -ForegroundColor DarkGray
    }

    # 2. Environment Variable Management
    $TargetScope = if ($IsAdmin) { "Machine" } else { "User" }
    # Logic: If missing OR pointing to the wrong place, update it.
    if (!(Test-Path "Env:\$VarName") -or (Get-Item "Env:\$VarName").Value -ne $TargetPath) {
        
        # Update Current Process
        Set-Item -Path "Env:\$VarName" -Value $TargetPath
        
        # Persist to Registry (Machine if Admin, else User)
        [Environment]::SetEnvironmentVariable($VarName, $TargetPath, $TargetScope)
        
        # 3. Path Integration for BINARIES_PATH
        if ($VarName -eq "ENVIRONMENT_PATH" -or $VarName -eq "BINARIES_PATH" -or $VarName -eq "BUILDTOOLS_PATH") {
            $RegPath = if ($IsAdmin) { "System\CurrentControlSet\Control\Session Manager\Environment" } else { "Environment" }
            $RegRoot = if ($IsAdmin) { "LocalMachine" } else { "CurrentUser" }
            $TargetTag = "%$VarName%"
        
            # Open the registry key directly to read the RAW (unexpanded) string
            $RegistryKey = [Microsoft.Win32.Registry]::$RegRoot.OpenSubKey($RegPath, $true)
            $CurrentRawPath = $RegistryKey.GetValue("Path", "", [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
        
            if ($CurrentRawPath -notlike "*$TargetTag*") {
                Write-Host "[PATH] Prepending $TargetTag to Registry..." -ForegroundColor Cyan

                # Ensure we don't start with a semicolon if the path was somehow empty
                $NewRawPath = ("$TargetTag;" + $CurrentRawPath).Replace(";;", ";").TrimEnd(';')
                
                # Corrected: Use ExpandString to ensure %VAR% tags remain dynamic
                $RegistryKey.SetValue("Path", $NewRawPath, [Microsoft.Win32.RegistryValueKind]::ExpandString)
                
                # Update current session only if not already present
                if ($env:Path -notlike "*$TargetPath*") {
                    $env:Path = "$TargetPath;" + $env:Path
                }
            } else {
                Write-Host "[OK] $TargetTag is already in the Path." -ForegroundColor DarkGray
            }
            $RegistryKey.Close()
        }

        $ScopeColor = if ($IsAdmin) { "Magenta" } else { "Yellow" }
        Write-Host "[UPDATED] ($TargetScope Scope) '$VarName' -> $TargetPath" -ForegroundColor $ScopeColor
    } else {
        Write-Host "[OK] Env Var '$VarName' is correctly mapped." -ForegroundColor DarkGray
    }
}

# --- 4. Developer Mode & Sideloading ---
$DevPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock"
if (-not (Test-Path $DevPath)) { New-Item -Path $DevPath -Force | Out-Null }

$DevVal = Get-ItemProperty -Path $DevPath -Name "AllowDevelopmentWithoutDevLicense" -ErrorAction SilentlyContinue
$TrustVal = Get-ItemProperty -Path $DevPath -Name "AllowAllTrustedApps" -ErrorAction SilentlyContinue

if ($null -eq $DevVal -or $DevVal.AllowDevelopmentWithoutDevLicense -ne 1) {
    Set-ItemProperty -Path $DevPath -Name "AllowDevelopmentWithoutDevLicense" -Value 1
    Write-Host "[UPDATED] Windows Developer Mode enabled." -ForegroundColor Green
} else {
    Write-Host "[OK] Windows Developer Mode is already active." -ForegroundColor DarkGray
}
if ($null -eq $TrustVal -or $TrustVal.AllowAllTrustedApps -ne 1) {
    Set-ItemProperty -Path $DevPath -Name "AllowAllTrustedApps" -Value 1
    Write-Host "[UPDATED] Trusted App Sideloading enabled." -ForegroundColor Green
} else {
    Write-Host "[OK] Trusted App Sideloading is already active." -ForegroundColor DarkGray
}

# --- 5. Enable Long Paths (MAX_PATH removal) ---
$FileSystemPath = "HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem"
$LongPathVal = Get-ItemProperty -Path $FileSystemPath -Name "LongPathsEnabled" -ErrorAction SilentlyContinue

if ($null -eq $LongPathVal -or $LongPathVal.LongPathsEnabled -ne 1) {
    Set-ItemProperty -Path $FileSystemPath -Name "LongPathsEnabled" -Value 1
    Write-Host "[UPDATED] Long Path support enabled (LongPathsEnabled=1)." -ForegroundColor Green
} else {
    Write-Host "[OK] Long Path support is already active." -ForegroundColor DarkGray
}

Write-Host "--- Sync Complete ---" -ForegroundColor Green
