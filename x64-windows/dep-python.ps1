# Copyright 2026 (C) Navegos. DevelVitorF. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
# file:x64-windows/dep-python.ps1

param (
    [Parameter(HelpMessage = "Path for python storage", Mandatory = $false)]
    [string]$pythonInstallDir = "$env:LIBRARIES_PATH\python",
    
    [Parameter(HelpMessage = "Python Version", Mandatory = $false)]
    [string]$pythonVersion = "3.14.4",
    
    [Parameter(HelpMessage = "Force a full purge of the local Python version before continuing", Mandatory = $false)]
    [switch]$forceCleanup,

    [Parameter(HelpMessage = "Don't Update Python and scripts packages if update has found", Mandatory = $false)]
    [switch]$dontUpdate,
    
    [Parameter(HelpMessage = "Add's Python Machine Environment Variables. Requires Machine Administrator Rights.", Mandatory = $false)]
    [switch]$withMachineEnvironment
)

# Capture parameters
$PythonWithMachineEnvironment = $withMachineEnvironment
$PythonDontUpdate = $dontUpdate
$PythonForceCleanup = $forceCleanup

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
    if (Test-Path $target) {
        Remove-Item $target -Force -ErrorAction SilentlyContinue;
    }
    if ($pythontool -eq "python.exe") {
        $target = Join-Path $GlobalBinDir "python3.exe"
        if (Test-Path $target) {
            Remove-Item $target -Force -ErrorAction SilentlyContinue;
        }
    }
}
$pythonBinPath = $pythonInstallDir
$pythonExePath = Join-Path $pythonInstallDir "python.exe"
$pythonScriptsPath = Join-Path $pythonInstallDir "Scripts"
$versionFile = Join-Path $pythonInstallDir "version.json"
$pipExe = Join-Path $pythonScriptsPath "pip.exe"
$uvExe = Join-Path $pythonScriptsPath "uv.exe"
$pythonEnvScript = Join-Path $EnvironmentDir "env-python.ps1"
$pythonMachineEnvScript = Join-Path $EnvironmentDir "machine-env-python.ps1"

# Version Detection
$remoteVersion = $pythonVersion # Default to the param version. We don't whant to break user python scripts versions requirements
$tag_name = "v$pythonVersion"
$zipName = "python-$pythonVersion-amd64.zip"
$url = "https://www.python.org/ftp/python/$pythonVersion/$zipName"
$updated_at = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssZ")
$tagCommit = "N/A" # Python FTP doesn't provide easy commit hashes via URL
$localVersion = "0.0.0"
$rawVersion = "0.0.0"
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

    if ($PythonWithMachineEnvironment)
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

    # 2. Filesystem Clean (Requires checking for locked files)
    # delete everithing we create don't fail later
    if (Test-Path $pythonEnvScript) {
        Write-Host "  [DELETING] $pythonEnvScript" -ForegroundColor Yellow
        Remove-Item $pythonEnvScript -Recurse -Force -ErrorAction SilentlyContinue
    }
    if (Test-Path $pythonMachineEnvScript) {
        Write-Host "  [DELETING] $pythonMachineEnvScript" -ForegroundColor Yellow
        Remove-Item $pythonMachineEnvScript -Recurse -Force -ErrorAction SilentlyContinue
    }
    if (Test-Path $InstallPath) {
        Write-Host "  [DELETING] $InstallPath" -ForegroundColor Yellow
        Remove-Item $InstallPath -Recurse -Force -ErrorAction SilentlyContinue
    }
    
    # remove local Env variables for current session
    Get-ChildItem Env:\PYTHON_PATH* | Remove-Item -ErrorAction SilentlyContinue
    Get-ChildItem Env:\PYTHON_ROOT* | Remove-Item -ErrorAction SilentlyContinue
    Get-ChildItem Env:\PYTHON_BIN* | Remove-Item -ErrorAction SilentlyContinue
    Get-ChildItem Env:\PYTHON_SCRIPTS* | Remove-Item -ErrorAction SilentlyContinue

    Write-Host "--- Python Purge Complete ---" -ForegroundColor Green
}

if (Test-Path $pythonExePath) {
    $rawVersion = (& $pythonExePath --version | Select-Object -First 1).Trim()
    if ($rawVersion -match 'Python\s+(\d+\.\d+\.\d+)') { $localVersion = $Matches[1] }
}

if (Test-Path $versionFile) {
    $localVersion = (Get-Content $versionFile | ConvertFrom-Json).version
}

# --- 2. Install or Skip ---
$vLocal = [version]$localVersion
$vRemote = [version]$remoteVersion

$pipAvailable = $false
$uvAvailable = $false    

if ($PythonForceCleanup) {
    Write-Host "[FORCE] Manual cleanup requested for version $localVersion..." -ForegroundColor Magenta

    Invoke-PythonVersionPurge -InstallPath $pythonInstallDir

    # Reset local version tracker so the installer knows to proceed with a fresh deployment
    $localVersion = "0.0.0"
    $vLocal = [version]"0.0.0"
}

if (($vLocal -ge $vRemote -and $localVersion -ne "0.0.0") -or ($PythonDontUpdate -and -not $PythonForceCleanup)) {
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
    
    if (Test-Path $pipExe) {
        $pipAvailable = $true
    }
    if (Test-Path $uvExe) {
        $uvAvailable = $true
    }
} else {
    Write-Host "[UPDATE] Local: $localVersion -> Remote: $remoteVersion" -ForegroundColor Yellow

    # --- 1. Version Comparison & Package Inventory ---
    $requirementsFile = Join-Path $env:TEMP "python-$localVersion-migration-requirements.txt"
    $incompatibleFile = Join-Path $pythonInstallDir "incompatibles.json"
    $versionMissMatchUpgrade = $false
    $proceedWithInstall = $false
    $venvTempBackupDir = Join-Path $env:TEMP "venv-backups"
    $venvpathsLog = Join-Path $venvTempBackupDir "paths.log"

    if ($localVersion -ne "0.0.0" -and ($vLocal.Major -ne $vRemote.Major -or $vLocal.Minor -ne $vRemote.Minor)) {
        Write-Warning "Major/Minor version mismatch detected ($localVersion -> $remoteVersion)."
        Write-Warning "Upgrading will render your current site-packages incompatible and broken."
        
        $choice = Read-Host "Do you want to proceed with a clean upgrade? This will attempt to re-install packages using uv. (y/n)"
        if ($choice -match "^[yY]$") {
            $versionMissMatchUpgrade = $true
            
            # User said YES: Prepare for migration
            if (Test-Path $pythonExePath) {
                try {
                    # Export requirements before we nuke the folder
                    Write-Host "Backing up package list to $requirementsFile..." -ForegroundColor Gray
                    # Use pip freeze to get a clean requirements list
                    if (Test-Path $uvExe) {
                        & $pythonExePath -m uv pip freeze | Out-File -FilePath $requirementsFile -Encoding utf8
                    } else {
                        & $pythonExePath -m pip freeze | Out-File -FilePath $requirementsFile -Encoding utf8
                    }
                    $proceedWithInstall = $true
                }
                catch {
                    Write-Warning "Could not export package list. You may need to reinstall python requirements packages manually."
                }
            }
        }
        
        ## --- Multi-Venv Backup Phase (Smart Version Detection) ---
        Write-Host "[BACKUP] Scanning $pythonInstallDir for virtual environments..." -ForegroundColor Cyan

        # Find all directories containing 'pyvenv.cfg' (the marker of a venv)
        $foundVenvs = Get-ChildItem -Path $pythonInstallDir -Recurse -Filter "pyvenv.cfg" -ErrorAction SilentlyContinue

        if ($null -ne $foundVenvs -and $foundVenvs.Count -gt 0) {
            Write-Host "[FOUND] $($foundVenvs.Count) environments to process." -ForegroundColor Green
            
            if (-not (Test-Path $venvTempBackupDir)) { New-Item -Path $venvTempBackupDir -ItemType Directory -Force -ErrorAction SilentlyContinue }

            foreach ($cfgFile in $foundVenvs) {
                $venvRoot = $cfgFile.DirectoryName

                # 1. Extract the original version from the config file
                $originalVersion = "3.14" # Default fallback
                $cfgContent = Get-Content $cfgFile.FullName
                foreach ($line in $cfgContent) {
                    if ($line -match 'version\s*=\s*(\d+\.\d+)') {
                        $originalVersion = $Matches[1]
                        break
                    }
                }

                # Clean up the path name for a safe filename (remove drive letters and slashes)
                $relativeName = ($venvRoot -split [regex]::Escape($pythonInstallDir))[-1].TrimStart('\').Replace('\', '_')
                if ([string]::IsNullOrWhitespace($relativeName)) { $relativeName = "root_venv" }

                # Save the requirements AND the version info
                $backupFile = Join-Path $venvTempBackupDir "req-$relativeName.txt"
                $versionLog = Join-Path $venvTempBackupDir "ver-$relativeName.txt"
    
                $venvPython = Join-Path $venvRoot "Scripts\python.exe"
                $venvuv = Join-Path $venvRoot "Scripts\uv.exe"

                if (Test-Path $venvPython) {
                    Write-Host "  Freezing: $relativeName" -ForegroundColor Gray

                    try {
                        # Use the internal venv python to ensure we get the correct package list
                        if (Test-Path $venvuv) {
                            & $venvPython -m uv pip freeze | Out-File -FilePath $backupFile -Encoding utf8
                        }
                        else {
                            & $venvPython -m pip freeze | Out-File -FilePath $backupFile -Encoding utf8
                        }    
                    }
                    catch {
                        Write-Warning "Could not export venv package list in $venvRoot. You may need to reinstall venv requirements packages manually."
                    }
                    
                    # Save the path so we know where to recreate it later
                    $originalVersion | Out-File -FilePath $versionLog -Encoding utf8
                    $venvRoot | Out-File -FilePath $venvpathsLog -Append
                }
            }
        } else {
            Write-Host "[SKIP] No virtual environments found in $pythonInstallDir. Nothing to backup." -ForegroundColor Gray
        }
    }

    # Execute Clean Install if mismatch found
    if ($versionMissMatchUpgrade -and $proceedWithInstall) {
        Write-Host "Purging $pythonInstallDir for clean installation..." -ForegroundColor Yellow
        Remove-Item $pythonInstallDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    # Ensure directory exists
    if (-not (Test-Path $pythonInstallDir)) { New-Item -Path $pythonInstallDir -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null }

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

    # Allow overwrite files in same Major.Minor version or a full clean install with packages restoring
    if (($versionMissMatchUpgrade -and $proceedWithInstall) -or ($vLocal.Major -eq $vRemote.Major -or $vLocal.Minor -eq $vRemote.Minor))
    {
        # 4. Get from the official site
        try {
            $zipPath = Join-Path $env:TEMP $zipName
            
            Write-Host "Downloading $zipName..." -ForegroundColor Cyan
            Invoke-WebRequest -Uri $url -Outfile $zipPath -ErrorAction Stop
        
            Write-Host "Extracting Python $remoteVersion..." -ForegroundColor Cyan
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
            
            # Cleanup extraction debris
            Remove-Item $zipPath -Force -ErrorAction SilentlyContinue
            
            if (-not (Test-Path $pythonScriptsPath)) { New-Item -Path $pythonScriptsPath -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null }

            Write-Host "Python $remoteVersion installed successfully!" -ForegroundColor DarkGreen
        }
        catch {
            Write-Error "Critical Failure during installation: $($_.Exception.Message)"
            return # Exit to prevent trying to run pip on a non-existent install
        }
    }
    
    $versionInfo | ConvertTo-Json | Out-File -FilePath $versionFile -Encoding utf8 -Force

    # --- 3. Pip Bootstrap ---
    # Standard zips often lack pip. We check the \Scripts folder.
    if (-not $pipAvailable) {
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

    if (Test-Path $pipExe) {
        $pipAvailable = $true
    }

    if ($pipAvailable) {
        Write-Host "pip Version: $(& $pythonExePath -m pip --version)" -ForegroundColor Gray
        Write-Host "Upgrading pip and installing uv..." -ForegroundColor Cyan
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host "Successfully installed uv (Fast Python Package Manager)." -ForegroundColor Green
        }
        else {
            Write-Warning "uv installation failed. You may need to install it manually."
        }
    }

    if (Test-Path $uvExe) {
        $uvAvailable = $true
    }

    if ($pipAvailable) {
        # 1. Define your dependencies clearly
        $packageList = @'
setuptools
setuptools-rust
wheel
cython
pybind11
"pybind11[global]"
ninja
make
cmake
build
build[uv]
meson
numpy
psutil
tqdm
pydantic
pydantic-core
py-cpuinfo
scipy
rpyc
requests
pylint
pyyaml
packaging
winloop
'@
        # 2. Parse the string into a clean array
        $packages = $packageList -split '\s+' | Where-Object { $_ -match '\S' }

        # Install using the splatted array
        Write-Host "Installing library development essentials..." -ForegroundColor Cyan
        & $pythonExePath -m uv pip install -U $packages --no-warn-script-location | Out-Null
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host "Successfully installed required packages vis uv (Fast Python Package Manager)." -ForegroundColor Green
        }
        else {
            Write-Warning "required packages installation failed. You may need to install it manually."
        }
    }

    # --- 4. Package Migration & Incompatibility Check ---
    if ($versionMissMatchUpgrade -and $proceedWithInstall -and (Test-Path $requirementsFile)) {
        Write-Host "Attempting to restore packages for Python $remoteVersion using uv (high-speed migration)..." -ForegroundColor Cyan

        # 1. Define the persistent backup path
        $persistentRequirements = Join-Path $pythonInstallDir "python-$localVersion-migration-requirements.txt"
    
        # 2. Copy the file to the install dir before we start (Safety first)
        Copy-Item $requirementsFile -Destination $persistentRequirements -Force -ErrorAction SilentlyContinue

        # 3. Bulk install attempt (Fastest)
        & $pythonExePath -m uv pip install -r $requirementsFile --no-warn-script-location | Out-Null

        if ($LASTEXITCODE -ne 0) {
            Write-Warning "Bulk restore failed. Identifying specific incompatible packages..."
            $incompatibles = @()
            $packages = Get-Content $requirementsFile
            foreach ($pkg in $packages) {
                if ([string]::IsNullOrWhiteSpace($pkg)) { continue }
                Write-Host "  Installing: $pkg" -ForegroundColor Gray
                & $pythonExePath -m uv pip install -U $pkg --no-warn-script-location | Out-Null
                
                if ($LASTEXITCODE -ne 0) {
                    Write-Warning "  [FAILED] $pkg is incompatible or failed to build."
                    $incompatibles += $pkg
                }
            }

            if ($incompatibles.Count -gt 0) {
                $incompatibles | ConvertTo-Json | Out-File $incompatibleFile -Force -ErrorAction SilentlyContinue
                Write-Host "!!! Incompatible packages logged to: $incompatibleFile" -ForegroundColor Yellow
            }
        }
        
        # Clean up the TEMP file, but keep the one in $pythonInstallDir as a log
        Remove-Item $requirementsFile -Force -ErrorAction SilentlyContinue
        Write-Host "[ARCHIVED] Previous package list saved to: $persistentRequirements" -ForegroundColor Gray
    }

    # --- Multi-Venv Restore Phase (Dynamic Versioning) ---
    if ($versionMissMatchUpgrade -and $proceedWithInstall -and (Test-Path $venvpathsLog)) {
        Write-Host "Attempting to restore venv packages for Python $remoteVersion using uv (high-speed migration)..." -ForegroundColor Cyan

        # 1. Define the persistent backup path
        $venvBackupDir = Join-Path $pythonInstallDir "venv-backups"
        if (-not (Test-Path $venvBackupDir)) { New-Item -Path $venvBackupDir -ItemType Directory -Force -ErrorAction SilentlyContinue}
    
        # 2. Copy the venv backup folder to the install dir before we start (Safety first)
        Copy-Item -Path "$venvTempBackupDir\*" -Destination $venvBackupDir -Recurse -Force -ErrorAction SilentlyContinue

        $venvPaths = Get-Content $venvpathsLog
        Write-Host "[RESTORE] Rebuilding discovered virtual environments..." -ForegroundColor Cyan

        foreach ($vPath in $venvPaths) {
            if ([string]::IsNullOrWhiteSpace($vPath)) { continue }

            $relativeName = ($vPath -split [regex]::Escape($pythonInstallDir))[-1].TrimStart('\').Replace('\', '_')
            if ([string]::IsNullOrWhitespace($relativeName)) { $relativeName = "root_venv" }

            $backupFile = Join-Path $venvTempBackupDir "req-$relativeName.txt"
            $versionLog = Join-Path $venvTempBackupDir "ver-$relativeName.txt"

            if (Test-Path $backupFile -and Test-Path $versionLog) {
                # Read the specific version intended for THIS venv
                $targetVenvVersion = (Get-Content $versionLog).Trim()

                Write-Host "  Recreating: $vPath (Targeting Python $targetVenvVersion)" -ForegroundColor Gray
            
                # Delete old incompatible folder
                if (Test-Path $vPath) { Remove-Item $vPath -Recurse -Force -ErrorAction SilentlyContinue }
            
                # Create fresh venv using the specific version detected earlier
                # UV will find the correct installed Python (3.14 or 3.15) automatically
                & $pythonExePath -m uv venv $vPath --python $targetVenvVersion --quiet
            
                # Restore packages using the GLOBAL uv targeting the NEW venv python
                $newVenvPython = Join-Path $vPath "Scripts\python.exe"
                & $pythonExePath -m uv pip install -r $backupFile --python $newVenvPython --path $vPath --no-warn-script-location --offline-if-cached
                #& $newVenvPython -m ensurepip
                #& $newVenvPython -m pip install -U pip uv
                #& $newVenvPython -m uv pip install -r $backupFile --no-warn-script-location
                
                if ($LASTEXITCODE -eq 0) {
                    Write-Host "  [SUCCESS] Restored $relativeName as Python $targetVenvVersion" -ForegroundColor Green
                } else {
                    Write-Error "  [FATAL] Package restoration failed for $relativeName as Python $targetVenvVersion"
                }
            }
        }

        # Clean up the TEMP venv backup folder, but keep the one in $pythonInstallDir as a log
        Remove-Item $venvTempBackupDir -Recurse -Force -ErrorAction SilentlyContinue
        Write-Host "[ARCHIVED] Previous venv package list saved to: $venvBackupDir" -ForegroundColor Gray
    }

    Write-Host "Python $remoteVersion upgrade successful!" -ForegroundColor DarkGreen
}

# Finalize Environment Helper
if (Test-Path $pythonExePath) {
    # Create Environment Helper
    Write-Host "Generating environment helper script..." -ForegroundColor Cyan

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
if ($env:PATH -notlike "*$pythonbin*") { $env:PATH = $pythonbin + ";" + $env:PATH; $env:PATH = ($env:PATH).Replace(";;", ";") }
if ($env:PATH -notlike "*$pythonscripts*") { $env:PATH = $env:PATH + ";" + $pythonscripts; $env:PATH = ($env:PATH).Replace(";;", ";") }
#"$pythonscripts", "$pythonbin" | ForEach-Object { if ($env:PATH -notlike "*$_*") { $env:PATH = $_ + ";" + $env:PATH; $env:PATH = ($env:PATH).Replace(";;", ";") } }
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
        $targetp3 = Join-Path $GlobalBinDir "python3.exe"

        if (Test-Path $source) {
            if (Test-Path $target) { Remove-Item $target -Force -ErrorAction SilentlyContinue }

            try {
                New-Item -Path $target -ItemType SymbolicLink -Value $source -ErrorAction Stop | Out-Null
                Write-Host "[LINKED] $pythontool" -ForegroundColor Gray
            }
            catch {
                # Fallback to hardlink if developer mode is off/insufficient permissions
                New-Item -Path $target -ItemType HardLink -Value $source | Out-Null
                Write-Host "[LINKED] $pythontool" -ForegroundColor Gray
            }

            if ($pythontool -eq "python.exe") {
                if (Test-Path $targetp3) { Remove-Item $targetp3 -Force -ErrorAction SilentlyContinue; }
                try {
                    New-Item -Path $targetp3 -ItemType SymbolicLink -Value $source -ErrorAction Stop | Out-Null
                    Write-Host "[LINKED] python3.exe" -ForegroundColor Gray
                }
                catch {
                    # Fallback to hardlink if developer mode is off/insufficient permissions
                    New-Item -Path $targetp3 -ItemType HardLink -Value $source | Out-Null
                    Write-Host "[LINKED] python3.exe" -ForegroundColor Gray
                }
            }
        }
        else {
            Write-Warning "Optional tool $pythontool not found in $pythonBinPath distribution; skipping symlink."
        }
    }
    
    Write-Host "[LINKED] Python is now globally available via %BINARIES_PATH%" -ForegroundColor Green
    
    if ($PythonWithMachineEnvironment)
    {
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
    $pythontools | ForEach-Object { 
        $globalLinkPath = Join-Path $GlobalBinDir $_
        if (Test-Path $globalLinkPath) {
            Write-Host "Cleaning up dead symlink at $globalLinkPath..." -ForegroundColor Yellow
            Remove-Item $globalLinkPath -Force -ErrorAction SilentlyContinue
        }
        if ($_ -eq "python.exe") {
            $target = Join-Path $GlobalBinDir "python3.exe"
            if (Test-Path $target) {
                Remove-Item $target -Force -ErrorAction SilentlyContinue;
            }
        }
    }
    return
}
