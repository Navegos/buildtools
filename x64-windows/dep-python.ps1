# Copyright 2026 (C) Navegos. DevelVitorF. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
# file:x64-windows/dep-python.ps1

param (
    [Parameter(HelpMessage="Path for python storage", Mandatory=$false)]
    [string]$pythonInstallDir = "$env:LIBRARIES_PATH\python",
    
    [Parameter(HelpMessage="Python Version", Mandatory=$false)]
    [string]$pythonVersion = "3.14.3",
    
    [Parameter(HelpMessage = "Force a full uninstallation of the local Python version before continuing", Mandatory = $false)]
    [switch]$forceCleanup,
    
    [Parameter(HelpMessage = "Add's Python Machine Environment Variables. Requires Machine Administrator Rights.", Mandatory = $false)]
    [switch]$withMachineEnvironment
)

# 1. Bootstrap Environment if variables are missing
if ([string]::IsNullOrWhitespace($env:ENVIRONMENT_PATH) -or -not (Test-Path $env:ENVIRONMENT_PATH) -or [string]::IsNullOrWhitespace($env:BINARIES_PATH) -or -not (Test-Path $env:BINARIES_PATH) -or [string]::IsNullOrWhitespace($env:LIBRARIES_PATH) -or -not (Test-Path $env:LIBRARIES_PATH)) {
    Write-Error "User Environment variables missing. Please run adduserpaths.ps1 -LibrariesDir 'Path\for\Libraries' BinariesDir 'Path\for\Binaries' -EnvironmentDir 'Path\for\Environment'"
    return
}

$EnvironmentDir = "$env:ENVIRONMENT_PATH"

# if Symlink present delete
$GlobalBinDir = "$env:BINARIES_PATH"
# Remove existing symlink we are creating a new one
$pythontools = @("python.exe", "pythonw.exe")
foreach ($pythontool in $pythontools) {
    $target = Join-Path $GlobalBinDir $pythontool
    if (Test-Path $target) { Remove-Item $target -Force -ErrorAction SilentlyContinue }
}
$pythonBinPath = $pythonInstallDir
$pythonExePath = Join-Path $pythonInstallDir "python.exe"
$pythonScriptsPath = Join-Path $pythonInstallDir "Scripts"
$versionFile = Join-Path $pythonInstallDir "version.json"

# Version Detection
$remoteVersion = $pythonVersion # Default to the param version. We don't whant to break user python scripts versions requirements
$tag_name = "v$pythonVersion"
$zipName = "python-$pythonVersion-amd64.zip"
$url = "https://www.python.org/ftp/python/$pythonVersion/$zipName"
$updated_at = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssZ")
$tagCommit = "N/A" # Python FTP doesn't provide easy commit hashes via URL

# Verify if the version exists (Head request)
try {
    # Check if the ZIP exists on the FTP
    $response = Invoke-WebRequest -Uri $url -Method Head -ErrorAction Stop
    Write-Host "[FOUND] $zipName on official FTP (Status: $($response.StatusCode))." -ForegroundColor Green
}
catch {
    Write-Error "Python version $pythonVersion ($zipName) not found at $url."
    Write-Error "Please verify the version at https://www.python.org/ftp/python/"
    return # Terminate early to avoid broken installs
}

# --- 1. Cleanup Mechanism ---
function Invoke-PythonVersionPurge {
    param ([string]$InstallPath)
    Write-Host "--- Initiating Python Purge ---" -ForegroundColor Cyan

    if ($withMachineEnvironment)
    {
        $pythonCleanMachineEnvScript = Join-Path $env:TEMP "clean-machine-env-python.ps1"

        # Generating Clean Machine Environment wich removes the persist registry machine Environment
        $CleanMachineEnvContent = @'
# Python Clean Machine Environment Setup

# --- 0. Self-Elevation Logic ---
$IsAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$ScopeColor = "Cyan"

if (-not $IsAdmin) {
    Write-Host "Elevation required to clean python system variables. Relaunching as Administrator..." -ForegroundColor Yellow
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

$pythonroot = "VALUE_ROOT_PATH"

$TargetScope = if ($IsAdmin) { "Machine" } else { "User" }
$RegPath = if ($IsAdmin) { "System\CurrentControlSet\Control\Session Manager\Environment" } else { "Environment" }
$RegRoot = if ($IsAdmin) { "LocalMachine" } else { "CurrentUser" }

# 1. Registry Cleanup (TOOLS_PATH & EXTCOMP_PATH)
$RegKey = [Microsoft.Win32.Registry]::$RegRoot.OpenSubKey($RegPath, $true)

foreach ($VarName in @("TOOLS_PATH", "EXTCOMP_PATH")) {
    # Open the registry key directly to read the RAW (unexpanded) string
    $RawPath = $RegKey.GetValue($VarName, "", [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)

    # Cleanup: Remove empty strings, any path containing $VarName,
    $CleanPath = ($RawPath -split ';' | Where-Object { $_ -notlike "*$pythonroot*" }) -join ";"

    # Save as ExpandString
    $RegKey.SetValue($VarName, $CleanPath, [Microsoft.Win32.RegistryValueKind]::ExpandString)

    Write-Host "  [CLEANED] $VarName" -ForegroundColor Gray
}
$RegKey.Close()

Write-Host "[REMOVED] ($TargetScope) all '*$pythonroot*' removed from TOOLS_PATH" -ForegroundColor $ScopeColor
'@  -replace "VALUE_ROOT_PATH", $InstallPath

        $CleanMachineEnvContent | Out-File -FilePath $pythonCleanMachineEnvScript -Encoding utf8
        Write-Host "Created: $pythonCleanMachineEnvScript" -ForegroundColor Gray
        
        # --- Interaction: Prompt to remove persistent changes ---
        Write-Host ""
        $choice = Read-Host "Administrator rights required to Clean Machine Environment python changes? (y/n)"
        if ($choice -eq 'y' -or $choice -eq 'Y') {
            Write-Host "Executing $pythonCleanMachineEnvScript..." -ForegroundColor Yellow
            try {
                # Start the generated script. It handles its own elevation logic.
                & $pythonCleanMachineEnvScript
            }
            catch {
                Write-Error "Failed to execute the Clean Machine Environment script: $($_.Exception.Message)"
                return
            }
        }
        else {
            Write-Error "Skipped Clean Machine Environment python changes."
            return
        }

        # Cleanup
        Remove-Item $pythonCleanMachineEnvScript -Recurse -Force -ErrorAction SilentlyContinue
    }

    # 2. Filesystem Nuke (Requires checking for locked files)
    if (Test-Path $InstallPath) {
        Write-Host "  [DELETING] $InstallPath" -ForegroundColor Yellow
        Remove-Item $InstallPath -Recurse -Force -ErrorAction SilentlyContinue
    }

    Write-Host "--- Python Purge Complete ---" -ForegroundColor Green
}

$localVersion = "0.0.0"
$rawVersion = "0.0.0"
if (Test-Path $pythonExePath) {
    $rawVersion = (& $pythonExePath --version | Select-Object -First 1).Trim()
    if ($rawVersion -match 'Python\s+(\d+\.\d+\.\d+)') { $localVersion = $Matches[1] }
}

if (Test-Path $versionFile) {
    $localVersion = (Get-Content $versionFile | ConvertFrom-Json).version
}

if ($forceCleanup) {
    Invoke-PythonVersionPurge -InstallPath $pythonInstallDir
    # Reset trackers to force a fresh install
    $localVersion = "0.0.0"
}

# --- 2. Install or Skip ---
$vLocal = [version]$localVersion
$vRemote = [version]$remoteVersion

if ($vLocal -ge $vRemote -and $localVersion -ne "0.0.0") {
    Write-Host "[SKIP] Python $localVersion is already installed and up to date at: $pythonExePath" -ForegroundColor Green
    Write-Host "Python Version: $(& $pythonExePath --version | Select-Object -First 1)" -ForegroundColor Gray

    # 1. Locate the bin folder and the root folder
    $pythonVersion = $localVersion
    $pythonBinPath = Split-Path -Path $pythonExePath -Parent
    $pythonInstallDir = Split-Path -Path $pythonBinPath -Parent
    
    if (-not (Test-Path $versionFile)) {
        $versionInfo = @{
            url        = $url;
            tag_name   = $tag_name;
            commit     = $tagCommit;
            version    = $localVersion;
            rawversion = $rawVersion;
            date       = (Get-Date).ToString("yyyy-MM-dd");
            updated_at = $updated_at;
            type       = "rel_dist";
        }
        $versionInfo | ConvertTo-Json | Out-File -FilePath $versionFile -Encoding utf8 -Force
    }
} else {
    Write-Host "[UPDATE] Local: $localVersion -> Remote: $remoteVersion" -ForegroundColor Yellow

    # TODO: I we are upgrading existing installation, compare python Major, Minor Version from local and remote.
    # TODO: If Versions missmatch warn user that upgrading renders is scrypt package's incompatible and broken.
    # TODO: If user still whants to upgrade save all scrypt package's to requirements.txt ad requirements.json.
    # TODO: Remove pythonInstallDir and create new one.
    # TODO: Install the new python.
    # TODO: Test requirements are compatible for install and install compatible one's.
    # TODO: Save incompatible one's to incompatibles.txt ad incompatibles.json, and inform the user to see incompatibles if he wants to install manually later on.
    if (!(Test-Path $pythonInstallDir)) { New-Item -Path $pythonInstallDir -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null }

    # 4. Get from the official site
    try {
        $zipPath = Join-Path $env:TEMP $zipName
        
        Write-Host "Downloading $zipName..." -ForegroundColor Cyan
        Invoke-WebRequest -Uri $url -Outfile $zipPath
    
        Write-Host "Extracting to: $pythonInstallDir..." -ForegroundColor Cyan
        Expand-Archive -Path $zipPath -DestinationPath $pythonInstallDir -Force

        # Sometimes the ZIP contains a folder like "python-3.14.3-amd64" inside.
        # We move everything to the root of $pythonInstallDir.
        $extractedItems = Get-ChildItem -Path $pythonInstallDir
        if ($extractedItems.Count -eq 1 -and $extractedItems[0].PSIsContainer) {
            Write-Host "Flattening directory structure..." -ForegroundColor Gray
            $subFolder = $extractedItems[0].FullName
            Get-ChildItem -Path $subFolder | Move-Item -Destination $pythonInstallDir -Recurse -Force -ErrorAction SilentlyContinue
            Remove-Item $subFolder -Recurse -Force -ErrorAction SilentlyContinue
        }

        $pythonVersion = $remoteVersion
        if (Test-Path $pythonExePath) {
            $rawVersion = (& $pythonExePath --version | Select-Object -First 1).Trim()
        }
        $versionInfo = @{
            url        = $url;
            tag_name   = $tag_name;
            commit     = $tagCommit;
            version    = $remoteVersion;
            rawversion = $rawVersion;
            date       = (Get-Date).ToString("yyyy-MM-dd");
            updated_at = $updated_at;
            type       = "rel_dist";
        }
        $versionInfo | ConvertTo-Json | Out-File -FilePath $versionFile -Encoding utf8 -Force
        
        # Cleanup extraction debris
        Remove-Item $zipPath -Force -ErrorAction SilentlyContinue
        
        if (!(Test-Path $pythonScriptsPath)) { New-Item -Path $pythonScriptsPath -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null }

        Write-Host "Python $remoteVersion installed successfully!" -ForegroundColor DarkGreen
    }
    catch {
        Write-Error "Failed to install Python: $($_.Exception.Message)"
        return
    }
    
    # --- 3. Pip Bootstrap ---
    # Standard zips often lack pip. We check the \Scripts folder.
    $pipExe = Join-Path $pythonScriptsPath "pip.exe"
    $uvExe = Join-Path $pythonScriptsPath "uv.exe"
    if (!(Test-Path $pipExe)) {
        $getPipScript = Join-Path $env:TEMP "get-pip.py"
        try {
            Invoke-WebRequest -Uri "https://bootstrap.pypa.io/get-pip.py" -OutFile $getPipScript
            & $pythonExePath $getPipScript --no-warn-script-location
            Write-Host "Pip installed successfully." -ForegroundColor Green
        }
        catch {
            Write-Warning "Failed to bootstrap Pip: $($_.Exception.Message)"
        }
        finally {
            if (Test-Path $getPipScript) { Remove-Item $getPipScript -Force -ErrorAction SilentlyContinue }
        }
    }
    
    # --- Post-Install: Package Management ---
    Write-Host "Python Version: $(& $pythonExePath --version)" -ForegroundColor Gray

    try {
        if (Test-Path $pipExe) {
            & $pipExe --version | Out-Null
            $pipAvailable = $true
        }
        else {
            $pipAvailable = $false
        }
    }
    catch {
        $pipAvailable = $false
    }

    if ($pipAvailable) {
        Write-Host "pip Version: $(& $pythonExePath -m pip --version)" -ForegroundColor Gray
        Write-Host "Upgrading pip and installing uv..." -ForegroundColor Cyan
        
        # Using python -m to ensure we use the local instance we just installed
        & $pythonExePath -m pip install -U pip uv --no-warn-script-location
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host "Successfully installed uv (Fast Python Package Manager)." -ForegroundColor Green
        }
        else {
            Write-Warning "uv installation failed. You may need to install it manually."
        }
    }
    
    try {
        if (Test-Path $uvExe) {
            & $uvExe --version | Out-Null
            $uvAvailable = $true
        }
        else {
            $uvAvailable = $false
        }
    }
    catch {
        $uvAvailable = $false
    }

}

# Finalize Environment Helper
if (Test-Path $pythonExePath) {
    # Create Environment Helper
    Write-Host "Generating environment helper script..." -ForegroundColor Cyan
    $pythonEnvScript = Join-Path $EnvironmentDir "env-python.ps1"

    # Generate Environment Helper with Clean Paths
    $pythonBinPath = $pythonBinPath.TrimEnd('\')
    $pythonInstallDir = $pythonInstallDir.TrimEnd('\')
    $pythonScriptsPath = $pythonScriptsPath.TrimEnd('\')

    # Using a literal here-string with -replace to avoid accidental expansion of $env:PATH during creation
    $EnvContent = @'
# PYTHON Environment Setup
$pythonroot = "VALUE_ROOT_PATH"
$pythonbin = "VALUE_BIN_PATH"
$pythonscripts = "VALUE_SCRIPTS_PATH"
$pythonversion = "VALUE_VERSION"
$env:PYTHON_PATH = $pythonroot
$env:PYTHON_ROOT = $pythonroot
$env:PYTHON_BIN = $pythonbin
$env:PYTHON_SCRIPTS = $pythonscripts
"$pythonscripts", "$pythonbin" | ForEach-Object { if ($env:PATH -notlike "*$_*") { $env:PATH = $_ + ";" + $env:PATH } }
Write-Host "Python Environment Loaded (Version: $pythonversion) (Bin: $pythonbin)" -ForegroundColor Green
Write-Host "PYTHON_ROOT: $env:PYTHON_ROOT" -ForegroundColor Gray
'@  -replace "VALUE_BIN_PATH", $pythonBinPath `
    -replace "VALUE_ROOT_PATH", $pythonInstallDir `
    -replace "VALUE_SCRIPTS_PATH", $pythonScriptsPath `
    -replace "VALUE_VERSION", $pythonVersion

    $EnvContent | Out-File -FilePath $pythonEnvScript -Encoding utf8
    Write-Host "Created: $pythonEnvScript" -ForegroundColor Gray
    
    # Update Current Session
    if (Test-Path $pythonEnvScript) { . $pythonEnvScript } else {
        Write-Error "python dep install finished but $pythonEnvScript was not created."
        return
    }
    
    # --- 10. Symlink to Global Binaries ---
    Write-Host "Creating global symlink to: $GlobalBinDir..." -ForegroundColor Cyan

    # Create Symlink
    foreach ($pythontool in $pythontools) {
        $source = Join-Path $pythonBinPath $pythontool
        $target = Join-Path $GlobalBinDir $pythontool

        if (Test-Path $source) {
            if (Test-Path $target) { Remove-Item $target -Force -ErrorAction SilentlyContinue }
            try {
                New-Item -ItemType SymbolicLink -Path $target -Value $source -ErrorAction Stop | Out-Null
                Write-Host "[LINKED] $pythontool" -ForegroundColor Gray
            }
            catch {
                # Fallback to hardlink if developer mode is off/insufficient permissions
                New-Item -ItemType HardLink -Path $target -Value $source | Out-Null
            }
        }
        else {
            Write-Warning "Optional tool $pythontool not found in $pythonBinPath distribution; skipping symlink."
        }
    }
    
    Write-Host "[LINKED] Python is now globally available via %BINARIES_PATH%" -ForegroundColor Green
    
    if ($withMachineEnvironment)
    {
        $pythonMachineEnvScript = Join-Path $EnvironmentDir "machine-env-python.ps1"

        # Generating Machine Environment wich add to the persist registry machine Environment
        $MachineEnvContent = @'
# Python Machine Environment Setup

# --- 0. Self-Elevation Logic ---
$IsAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$ScopeColor = "Cyan"

if (-not $IsAdmin) {
    Write-Host "Elevation required to set Python system variables. Relaunching as Administrator..." -ForegroundColor Yellow
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

$pythonroot = "VALUE_ROOT_PATH"
$pythonbin = "VALUE_BIN_PATH"
$pythonscripts = "VALUE_SCRIPTS_PATH"
$pythonversion = "VALUE_VERSION"

$TargetScope = if ($IsAdmin) { "Machine" } else { "User" }
$RegPath = if ($IsAdmin) { "System\CurrentControlSet\Control\Session Manager\Environment" } else { "Environment" }
$RegRoot = if ($IsAdmin) { "LocalMachine" } else { "CurrentUser" }

# Open the registry key once
$RegKey = [Microsoft.Win32.Registry]::$RegRoot.OpenSubKey($RegPath, $true)

# Open the registry key directly to read the RAW (unexpanded) string
$CurrentRawToolsPath = $RegKey.GetValue("TOOLS_PATH", "", [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
$CurrentRawExtCompPath = $RegKey.GetValue("EXTCOMP_PATH", "", [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)

# Check for both critical folders
if ($CurrentRawToolsPath -notlike "*$pythonbin*") {
    Write-Host "[PATH] Appending Python root path to $TargetScope Environment Registry..." -ForegroundColor Cyan
    # Build clean addition
    $CleanPath = $CurrentRawToolsPath.TrimEnd(';')
    if ($CurrentRawToolsPath -notlike "*$pythonbin*") { $CleanPath += ";$pythonbin" }

    # Ensure windows path end dont's wrap
    $CleanPath = ($CleanPath + ";").Replace(";;", ";")

    $RegKey.SetValue("TOOLS_PATH", $CleanPath, [Microsoft.Win32.RegistryValueKind]::ExpandString)
}
if ($CurrentRawExtCompPath -notlike "*$pythonscripts*") {
    Write-Host "[PATH] Appending Python Scripts path to $TargetScope Environment Registry..." -ForegroundColor Cyan
    # Build clean addition
    $CleanPath = $CurrentRawExtCompPath.TrimEnd(';')
    if ($CurrentRawExtCompPath -notlike "*$pythonscripts*") { $CleanPath += ";$pythonscripts" }

    # Ensure windows path end dont's wrap
    $CleanPath = ($CleanPath + ";").Replace(";;", ";")

    $RegKey.SetValue("EXTCOMP_PATH", $CleanPath, [Microsoft.Win32.RegistryValueKind]::ExpandString)
}
$RegKey.Close()

$env:PYTHON_ROOT = $pythonroot
Write-Host "python Environment Loaded (Version: $pythonversion) (Bin: $pythonbin)" -ForegroundColor Green
Write-Host "PYTHON_ROOT: $env:PYTHON_ROOT" -ForegroundColor Gray
'@  -replace "VALUE_ROOT_PATH", $pythonInstallDir `
    -replace "VALUE_BIN_PATH", $pythonBinPath `
    -replace "VALUE_SCRIPTS_PATH", $pythonScriptsPath `
    -replace "VALUE_VERSION", $pythonVersion

        $MachineEnvContent | Out-File -FilePath $pythonMachineEnvScript -Encoding utf8
        Write-Host "Created: $pythonMachineEnvScript" -ForegroundColor Gray
        
        # --- Interaction: Prompt to apply persistent changes ---
        Write-Host ""
        $choice = Read-Host "Do you want to run the Machine Environment script now to persist Python changes to the Registry? (y/n)"
        if ($choice -eq 'y' -or $choice -eq 'Y') {
            Write-Host "Executing $pythonMachineEnvScript..." -ForegroundColor Yellow
            try {
                # Start the generated script. It handles its own elevation logic.
                & $pythonMachineEnvScript
            }
            catch {
                Write-Error "Failed to execute the Machine Environment script: $($_.Exception.Message)"
            }
        }
        else {
            Write-Host "Skipped persistent registry update. You can run it later at: $pythonMachineEnvScript" -ForegroundColor Gray
        }
    }
    
    # --- 11. Final Verification ---
    Write-Host "Performing final tool verification..." -ForegroundColor Cyan
    
    $tools = @(
        @{ Name = "python"; Command = "$pythonExePath --version"; Available = $true },
        @{ Name = "pip"; Command = "$pythonExePath -m pip --version"; Available = $pipAvailable },
        @{ Name = "uv"; Command = "$pythonExePath -m uv --version"; Available = $uvAvailable }
    )
    foreach ($tool in $tools) {
        if ($tool.Available) {
            # We use Invoke-Expression or ScriptBlock to handle the string command
            $output = Invoke-Expression $tool.Command
            Write-Host "[OK] $($tool.Name) verified via: $($tool.Command)" -ForegroundColor Green
            Write-Host "$($tool.Name) Version: $output" -ForegroundColor Gray
        }
        else {
            Write-Warning "[FAIL] $($tool.Name) could not be verified using -m syntax."
        }
    }

    Write-Host "--- Python Sync Complete ---" -ForegroundColor Green
} else {
    Write-Error "python.exe was not found in the $pythonBinPath folder."
    return
}
