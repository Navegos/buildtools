# Copyright 2026 (C) Navegos. DevelVitorF. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
# file:x64-windows/dep-cuda.ps1

param (
    [Parameter(HelpMessage = "Base path for cuda storage like path\cuda", Mandatory = $false)]
    [string]$cudaInstallDir = "$env:LIBRARIES_PATH\cuda",

    [Parameter(HelpMessage = "Minimum Fallback CUDA Version", Mandatory = $false)]
    [string]$cudaVersion = "13.2.0",
    
    [Parameter(HelpMessage = "Minimum Fallback CUDSS Version", Mandatory = $false)]
    [string]$cudssVersion = "0.7.1",
    
    [Parameter(HelpMessage = "Minimum Fallback CUTENSOR Version", Mandatory = $false)]
    [string]$cutensorVersion = "2.6.0",
    
    [Parameter(HelpMessage = "Minimum Fallback CUSPARSE_LT Version", Mandatory = $false)]
    [string]$cusparseltVersion = "0.8.1",
    
    [Parameter(HelpMessage = "Minimum Fallback CUDNN Version", Mandatory = $false)]
    [string]$cudnnVersion = "9.20.0",
    
    [Parameter(HelpMessage = "Full link for TensorRT package", Mandatory = $false)]
    [string]$tensorrtLink = "https://developer.nvidia.com/downloads/compute/machine-learning/tensorrt/10.16.0/zip/TensorRT-10.16.0.72.Windows.amd64.cuda-13.2.zip",
    
    [Parameter(HelpMessage = "Force a full uninstallation of the local CUDA version before continuing", Mandatory = $false)]
    [switch]$forceCleanup,

    [Parameter(HelpMessage = "Don't Update CUDA Toolkit and libs if update has found", Mandatory = $false)]
    [switch]$dontUpdate,
    
    [Parameter(HelpMessage = "Add's CUDA Machine Environment Variables. Requires Machine Administrator Rights.", Mandatory = $false)]
    [switch]$withMachineEnvironment
)

# 1. Bootstrap Environment if variables are missing
if ([string]::IsNullOrWhitespace($env:ENVIRONMENT_PATH) -or -not (Test-Path $env:ENVIRONMENT_PATH) -or [string]::IsNullOrWhitespace($env:BINARIES_PATH) -or -not (Test-Path $env:BINARIES_PATH) -or [string]::IsNullOrWhitespace($env:LIBRARIES_PATH) -or -not (Test-Path $env:LIBRARIES_PATH)) {
    Write-Error "User Environment variables missing. Please run adduserpaths.ps1 -LibrariesDir 'Path\for\Libraries' BinariesDir 'Path\for\Binaries' -EnvironmentDir 'Path\for\Environment'"
    return
}

Write-Host "--- Navegos CUDA Auto-Discovery Management ---" -ForegroundColor Cyan

$EnvironmentDir = "$env:ENVIRONMENT_PATH"

# --- 1. Initialize Visual Studio 2026 Dev Environment dependencie requirement for Cuda Toolkit ---
$DevShellBootstrapScript = Join-Path $PSScriptRoot "dev-shell.ps1"
if (Test-Path $DevShellBootstrapScript) { . $DevShellBootstrapScript } else {
    Write-Error "Required dependency '$DevShellBootstrapScript' not found!"
    return
}

# --- 2. Version Detection (Remote) ---
$baseRedistUrl = "https://developer.download.nvidia.com/compute/cuda/redist"
$basecudssRedistUrl = "https://developer.download.nvidia.com/compute/cudss/redist"
$basecutensorRedistUrl = "https://developer.download.nvidia.com/compute/cutensor/redist"
$basecusparseltRedistUrl = "https://developer.download.nvidia.com/compute/cusparselt/redist"
$basecudnnRedistUrl = "https://developer.download.nvidia.com/compute/cudnn/redist"
$remoteVersion = $cudaVersion
$remotecudssVersion = $cudssVersion
$remotecutensorVersion = $cutensorVersion
$remotecusparseltVersion = $cusparseltVersion
$remotecudnnVersion = $cudnnVersion

$regex = 'redistrib_(\d+\.\d+\.\d+)\.json'
try {
    Write-Host "Scanning NVIDIA CUDA Redist repository for latest manifest..." -ForegroundColor Gray
    $webIndex = Invoke-WebRequest -Uri $baseRedistUrl -UseBasicParsing
    $availableVersions = [regex]::Matches($webIndex.Content, $regex) | ForEach-Object { $_.Groups[1].Value } | Sort-Object { [version]$_ } -Descending
    
    if ($availableVersions.Count -gt 0) {
        $remoteVersion = $availableVersions[0]
    }
}
catch {
    Write-Warning "NVIDIA CUDA Redist Discovery failed. Falling back to $cudaVersion"
}

try {
    Write-Host "Scanning NVIDIA CUDSS Redist repository for latest manifest..." -ForegroundColor Gray
    $webIndex = Invoke-WebRequest -Uri $basecudssRedistUrl -UseBasicParsing
    $availableVersions = [regex]::Matches($webIndex.Content, $regex) | ForEach-Object { $_.Groups[1].Value } | Sort-Object { [version]$_ } -Descending
    
    if ($availableVersions.Count -gt 0) {
        $remotecudssVersion = $availableVersions[0]
    }
}
catch {
    Write-Warning "NVIDIA CUDSS Redist Discovery failed. Falling back to $cudssVersion"
}

try {
    Write-Host "Scanning NVIDIA CUTENSOR Redist repository for latest manifest..." -ForegroundColor Gray
    $webIndex = Invoke-WebRequest -Uri $basecutensorRedistUrl -UseBasicParsing
    $availableVersions = [regex]::Matches($webIndex.Content, $regex) | ForEach-Object { $_.Groups[1].Value } | Sort-Object { [version]$_ } -Descending
    
    if ($availableVersions.Count -gt 0) {
        $remotecutensorVersion = $availableVersions[0]
    }
}
catch {
    Write-Warning "NVIDIA CUTENSOR Redist Discovery failed. Falling back to $cutensorVersion"
}

try {
    Write-Host "Scanning NVIDIA CUSPARSE_LT Redist repository for latest manifest..." -ForegroundColor Gray
    $webIndex = Invoke-WebRequest -Uri $basecusparseltRedistUrl -UseBasicParsing
    $availableVersions = [regex]::Matches($webIndex.Content, $regex) | ForEach-Object { $_.Groups[1].Value } | Sort-Object { [version]$_ } -Descending
    
    if ($availableVersions.Count -gt 0) {
        $remotecusparseltVersion = $availableVersions[0]
    }
}
catch {
    Write-Warning "NVIDIA CUSPARSE_LT Redist Discovery failed. Falling back to $cusparseltVersion"
}

try {
    Write-Host "Scanning NVIDIA CUDNN Redist repository for latest manifest..." -ForegroundColor Gray
    $webIndex = Invoke-WebRequest -Uri $basecudnnRedistUrl -UseBasicParsing
    $availableVersions = [regex]::Matches($webIndex.Content, $regex) | ForEach-Object { $_.Groups[1].Value } | Sort-Object { [version]$_ } -Descending
    
    if ($availableVersions.Count -gt 0) {
        $remotecudnnVersion = $availableVersions[0]
    }
}
catch {
    Write-Warning "NVIDIA CUDNN Redist Discovery failed. Falling back to $cudnnVersion"
}

# --- 3. Local Version Detection ---
$baseRoot = $cudaInstallDir # Store the base anchor
$localVersion = "0.0.0"
$localcudssVersion = "0.0.0"
$localcutensorVersion = "0.0.0"
$localcusparseltVersion = "0.0.0"
$localcudnnVersion = "0.0.0"

# Initial pathing based on input param
$cudaSplit = $cudaVersion.Split('.')
$cudamajor = $cudaSplit[0]                              # e.g., "13"
$cudamajorMinor = $cudaSplit[0..1] -join "."            # e.g., "13.2"
$cudapathmajorMinor = "v" + $cudamajorMinor             # e.g., "v13.2"
$cudaenvmajorMinor = $cudaSplit[0..1] -join "_"         # e.g., "13_2"
$activeInstallDir = Join-Path $baseRoot $cudapathmajorMinor
$versionFile = Join-Path $activeInstallDir "version.json"

if (Test-Path $versionFile) {
    $localVersion = (Get-Content $versionFile | ConvertFrom-Json).cuda.version
    $localcudssVersion = (Get-Content $versionFile | ConvertFrom-Json).libcudss.version
    $localcutensorVersion = (Get-Content $versionFile | ConvertFrom-Json).libcutensor.version
    $localcusparseltVersion = (Get-Content $versionFile | ConvertFrom-Json).libcusparse_lt.version
    $localcudnnVersion = (Get-Content $versionFile | ConvertFrom-Json).cudnn.version
}

# Comparison
$vLocal = [version]$localVersion
$vLocalcudss = [version]$localcudssVersion
$vLocalcutensor = [version]$localcutensorVersion
$vLocalcusparselt = [version]$localcusparseltVersion
$vLocalcudnn = [version]$localcudnnVersion
$vRemote = [version]$remoteVersion
$vRemotecudss = [version]$remotecudssVersion
$vRemotecutensor = [version]$remotecutensorVersion
$vRemotecusparselt = [version]$remotecusparseltVersion
$vRemotecudnn = [version]$remotecudnnVersion

function Invoke-CudaVersionPurge {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Version,       # e.g., "13.2"
        [string]$InstallBase = "$env:LIBRARIES_PATH\cuda"
    )

    $verPath = "v$Version"
    $verEnv = $Version.Replace(".", "_")
    $versionVarName = "CUDA_PATH_V$verEnv"
    $fullInstallDir = Join-Path $InstallBase $verPath

    Write-Host "--- Initiating Purge for CUDA $verPath ---" -ForegroundColor Cyan

    if ($withMachineEnvironment)
    {
        $cudaCleanMachineEnvScript = Join-Path $env:TEMP "clean-machine-env-cuda.ps1"

        # Generating Clean Machine Environment wich removes the persist registry machine Environment
        $CleanMachineEnvContent = @'
# CUDA Clean Machine Environment Setup

# --- 0. Self-Elevation Logic ---
$IsAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$ScopeColor = "Cyan"

if (-not $IsAdmin) {
    Write-Host "Elevation required to clean cuda system variables and VS BuildCustomizations. Relaunching as Administrator..." -ForegroundColor Yellow
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

$cudaroot = "VALUE_ROOT_PATH"
$verPath = "VERSION_PATH"
$cudaversion = "VALUE_VERSION"

# 1. Surgical MSBuild v180 Cleanup
# Discover VS Install Dir if not in env
$VSinstallPath = $env:VSINSTALLDIR
if ([string]::IsNullOrWhitespace($VSinstallPath)) {
    # Fallback to standard 2026 path if the dev-shell wasn't inherited
    $vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
    if (Test-Path $vswhere) {
        $VSinstallPath = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
    }
}

$msBuildDest = Join-Path $VSinstallPath "MSBuild\Microsoft\VC\v180\BuildCustomizations"
if (Test-Path $msBuildDest) {
    $targets = @("CUDA $cudaversion.props", "CUDA $cudaversion.targets", "CUDA $cudaversion.Version.props", "CUDA $cudaversion.xml", "Nvda.Build.CudaTasks.v$cudaversion.dll")
    foreach ($f in $targets) {
        $tFile = Join-Path $msBuildDest $f
        if (Test-Path $tFile) { Remove-Item $tFile -Force; Write-Host "  [DELETED] MSBuild: $f" -ForegroundColor Gray }
    }
}

$EnvMapping = [ordered]@{
    "CUDA_HOME"         = $cudaroot
    "CUDA_PATH"         = $cudaroot
    "VERSION_VAR_NAME"   = $cudaroot
}

$TargetScope = if ($IsAdmin) { "Machine" } else { "User" }
$RegPath = if ($IsAdmin) { "System\CurrentControlSet\Control\Session Manager\Environment" } else { "Environment" }
$RegRoot = if ($IsAdmin) { "LocalMachine" } else { "CurrentUser" }

# 1. Get all environment variables from the registry
$RegKey = [Microsoft.Win32.Registry]::$RegRoot.OpenSubKey($RegPath, $true)

# 2. Identify and Remove variables that match the pattern
foreach ($Entry in $EnvMapping.GetEnumerator()) {
    $VarName = $Entry.Key

    # This explicitly passes a null pointer to the Win32 API, 
    # which is the standard trigger for deleting an environment variable.
    [Environment]::SetEnvironmentVariable($VarName, [NullString]::Value, $TargetScope)
    Write-Host "[REMOVED] ($TargetScope) '$VarName' removed from system variables" -ForegroundColor $ScopeColor
        
    # This removes the entry from the HKLM hardware/hive level immediately.
    try {
        if ($RegKey.GetValue($VarName)) {
            $RegKey.DeleteValue($VarName, $false)
        }
    }
    catch {
        Write-Warning "  Direct registry deletion failed for ${VarName}: $($_.Exception.Message)"
    }

    # Remove from current session environment
    if (Test-Path "Env:\$VarName") { Remove-Item "Env:\$VarName" -Force -ErrorAction SilentlyContinue }
}

# Open the registry key directly to read the RAW (unexpanded) string
$RawPath = $RegKey.GetValue("NVIDIA_PATH", "", [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)

# Cleanup: Remove empty strings, any path containing $verPath,
$CleanPath = ($RawPath -split ';' | Where-Object { $_ -notlike "*\cuda\$verPath*" }) -join ";"

# Save as ExpandString
$RegKey.SetValue("NVIDIA_PATH", $CleanPath, [Microsoft.Win32.RegistryValueKind]::ExpandString)
$env:NVIDIA_PATH = $CleanPath

$RegKey.Close()

Write-Host "[REMOVED] ($TargetScope) all '*$verPath*' removed from NVIDIA_PATH" -ForegroundColor $ScopeColor
'@  -replace "VALUE_ROOT_PATH", $fullInstallDir `
    -replace "VERSION_PATH", $verPath `
    -replace "VERSION_VAR_NAME", $versionVarName `
    -replace "VALUE_VERSION", $Version
    
        $CleanMachineEnvContent | Out-File -FilePath $cudaCleanMachineEnvScript -Encoding utf8
        Write-Host "Created: $cudaCleanMachineEnvScript" -ForegroundColor Gray
        
        # --- Interaction: Prompt to remove persistent changes ---
        Write-Host ""
        $choice = Read-Host "Administrator rights required to Clean Visual Studio and Machine Environment cuda changes? (y/n)"
        if ($choice -eq 'y' -or $choice -eq 'Y') {
            Write-Host "Executing $cudaCleanMachineEnvScript..." -ForegroundColor Yellow
            try {
                # Start the generated script. It handles its own elevation logic.
                & $cudaCleanMachineEnvScript
            }
            catch {
                Write-Error "Failed to execute the Clean Machine Environment script: $($_.Exception.Message)"
                return
            }
        }
        else {
            Write-Error "Skipped Clean Visual Studio and Machine Environment cuda changes."
            return
        }
        
        # Cleanup
        Remove-Item $cudaCleanMachineEnvScript -Recurse -Force -ErrorAction SilentlyContinue
    }

    # 4. Filesystem Nuke
    if (Test-Path $fullInstallDir) {
        Write-Host "  [DELETING] $fullInstallDir" -ForegroundColor Yellow
        Remove-Item $fullInstallDir -Recurse -Force -ErrorAction SilentlyContinue
    }
    
    Write-Host "--- Purge Complete for $verPath ---" -ForegroundColor Green
}

# Check if forceCleanup was requested OR if an update is required
if ($forceCleanup -or ($vLocal -lt $vRemote -and -not $dontUpdate)) {
    
    if ($forceCleanup) {
        Write-Host "[FORCE] Manual cleanup requested for version $localVersion..." -ForegroundColor Magenta
    }
    else {
        Write-Host "[UPDATE] Outdated version detected ($localVersion). Preparing system for v$remoteVersion..." -ForegroundColor Yellow
    }

    # Trigger the Purge Function
    # Note: We use $cudamajorMinor from the local detection to ensure we delete the right files
    $purgeVer = $localVersion.Split('.')[0..1] -join "."
    if ($forceCleanup) {
        $cuVer = $cudaversion.Split('.')[0..1] -join "."
        Invoke-CudaVersionPurge -Version $cuVer
    }
    elseif ($purgeVer -ne "0.0") {
        Invoke-CudaVersionPurge -Version $purgeVer
    }

    # Reset local version tracker so the installer knows to proceed with a fresh deployment
    $localVersion = "0.0.0"
    $localcudssVersion = "0.0.0"
    $localcutensorVersion = "0.0.0"
    $localcusparseltVersion = "0.0.0"
    $localcudnnVersion = "0.0.0"
    $vLocal = [version]"0.0.0"
    $vLocalcudss = [version]"0.0.0"
    $vLocalcutensor = [version]"0.0.0"
    $vLocalcusparselt = [version]"0.0.0"
    $vLocalcudnn = [version]"0.0.0"
}

# We are installing new version if forcing cleanup
if ($dontUpdate -and -not $forceCleanup) {
    $cudaVersion = $localVersion
    $cudaSplit = $cudaVersion.Split('.')
    $cudamajor = $cudaSplit[0]                              # e.g., "13"
    $cudamajorMinor = $cudaSplit[0..1] -join "."            # e.g., "13.2"
    $cudapathmajorMinor = "v" + $cudamajorMinor             # e.g., "v13.2"
    $cudaenvmajorMinor = $cudaSplit[0..1] -join "_"         # e.g., "13_2"
    $activeInstallDir = Join-Path $baseRoot $cudapathmajorMinor
    $versionFile = Join-Path $activeInstallDir "version.json"

    $cudssVersion = $localcudssVersion
    $cutensorVersion = $localcutensorVersion
    $cusparseltVersion = $localcusparseltVersion
    $cudnnVersion = $localcudnnVersion
}
elseif ($vLocal -lt $vRemote) {
    $cudaVersion = $remoteVersion
    $cudaSplit = $cudaVersion.Split('.')
    $cudamajor = $cudaSplit[0]                              # e.g., "13"
    $cudamajorMinor = $cudaSplit[0..1] -join "."            # e.g., "13.2"
    $cudapathmajorMinor = "v" + $cudamajorMinor             # e.g., "v13.2"
    $cudaenvmajorMinor = $cudaSplit[0..1] -join "_"         # e.g., "13_2"
    $activeInstallDir = Join-Path $baseRoot $cudapathmajorMinor
    $versionFile = Join-Path $activeInstallDir "version.json"
    
    if ($vLocalcudss -lt $vRemotecudss) { $cudssVersion = $remotecudssVersion }
    if ($vLocalcutensor -lt $vRemotecutensor) { $cutensorVersion = $remotecutensorVersion }
    if ($vLocalcusparselt -lt $vRemotecusparselt) { $cusparseltVersion = $remotecusparseltVersion }
    if ($vLocalcudnn -lt $vRemotecudnn) { $cudnnVersion = $remotecudnnVersion }
}

# Synchronize the main variable for the rest of the script
$cudaInstallDir = $activeInstallDir
$cudaBinPath = Join-Path $cudaInstallDir "bin"
$cudaBinx64Path = Join-Path $cudaBinPath "x64"
$cudaLibDir = Join-Path $cudaInstallDir "lib"
$cudaLibx64Dir = Join-Path $cudaLibDir "x64"
$nvccExePath = Join-Path $cudaBinPath "nvcc.exe"
$cudanvvmPath = Join-Path $cudaInstallDir "nvvm"
$cudanvvmBinPath = Join-Path $cudanvvmPath "bin"
$computesanitizerPath = Join-Path $cudaInstallDir "compute-sanitizer"

# if Symlink present delete
$GlobalBinDir = "$env:BINARIES_PATH"
# Remove existing symlink we are creating a new one
$cudatools = @("__nvcc_device_query.exe", "bin2c.exe", "ctadvisor.exe", "cu++filt.exe", "cudafe++.exe", "cuobjdump.exe",
               "fatbinary.exe", "nvcc.exe", "nvdisasm.exe", "nvlink.exe", "nvprune.exe", "ptxas.exe", "cicc.exe",
               "compute-sanitizer.exe", "tileiras.exe", "trtexec.exe")
$nvvmcicctool = "cicc.exe"
$computesanitizertool = "compute-sanitizer.exe"
foreach ($cudatool in $cudatools) {
    $target = Join-Path $GlobalBinDir $cudatool
    if (Test-Path $target) { Remove-Item $target -Force -ErrorAction SilentlyContinue; Write-Host "  [REMOVED] Link: $cudatool" -ForegroundColor Gray }
}

# --- 4. Install or Skip ---
if (($vLocal -ge $vRemote -and $localVersion -ne "0.0.0") -or ($dontUpdate -and -not $forceCleanup)) {
    Write-Host "[SKIP] CUDA $localVersion is already installed, up to date, or you skipped update at: $cudaInstallDir" -ForegroundColor Green
} else {
    Write-Host "[UPDATE] Local: $localVersion -> Remote: $remoteVersion" -ForegroundColor Yellow

    # Initialize Directory
    if (!(Test-Path $cudaInstallDir)) { New-Item -Path $cudaInstallDir -ItemType Directory -Force | Out-Null }

    $manifestUrl = "$baseRedistUrl/redistrib_$remoteVersion.json"
    $manifest = Invoke-RestMethod -Uri $manifestUrl

    # Key components required for a functional Toolkit
    $components = @("cuda_cccl", "cuda_crt", "cuda_ctadvisor", "cuda_cudart", "cuda_cuobjdump", "cuda_cupti",
                    "cuda_cuxxfilt", "cuda_nvcc", "cuda_nvdisasm", "cuda_nvml_dev", "cuda_nvprune",
                    "cuda_nvrtc", "cuda_nvtx", "cuda_opencl", "cuda_profiler_api", "cuda_sanitizer_api",
                    "cuda_tileiras", "libcublas", "libcufft", "libcurand", "libcusolver", "libcusparse",
                    "libnpp", "libnvfatbin", "libnvjitlink", "libnvjpeg", "libnvptxcompiler", "libnvvm",
                    "nsight_vse", "visual_studio_integration", "libcudss", "libcutensor", "libcusparse_lt", "cudnn")

    $manifestMap = @{
        "libcudss"       = @{ url = $basecudssRedistUrl;        ver = $cudssVersion }
        "libcutensor"    = @{ url = $basecutensorRedistUrl;     ver = $cutensorVersion }
        "libcusparse_lt" = @{ url = $basecusparseltRedistUrl;   ver = $cusparseltVersion }
        "cudnn"          = @{ url = $basecudnnRedistUrl;        ver = $cudnnVersion }
    }

    # --- 5. Download, Extract, and Flatten ---
    # Initialize the structure with the top-level CUDA version
    $versionInfo = [ordered]@{
        "cuda" = @{
            "name"              = "CUDA SDK"
            "version"           = $remoteVersion
            "release_date"      = $manifest.release_date
            "release_label"     = $manifest.release_label
            "release_product"   = $manifest.release_product
            "date"              = (Get-Date).ToString("yyyy-MM-dd")
        }
    }
    foreach ($comp in $components) {
        # Determine which manifest to use
        $currentBaseUrl = $baseRedistUrl
        $currentManifest = $manifest

        if ($manifestMap.ContainsKey($comp)) {
            $libInfo = $manifestMap[$comp]
            $currentBaseUrl = $libInfo.url
            $libVer = $libInfo.ver

            # Construct the specific manifest URL: e.g., .../redistrib_9.2.0.json
            $libManifestUrl = "$currentBaseUrl/redistrib_$libVer.json"

            # Fetch the specific manifest for this extra library
            try {
                Write-Host "Fetching manifest for $comp (v$libVer)..." -ForegroundColor Gray
                $currentManifest = Invoke-RestMethod -Uri $libManifestUrl
            }
            catch {
                Write-Warning "Could not find manifest for $comp version $libVer at $libManifestUrl. Attempting generic redistrib.json..."
                try {
                    $currentManifest = Invoke-RestMethod -Uri "$currentBaseUrl/redistrib.json"
                }
                catch {
                    Write-Error "Failed to locate manifest for $comp. Skipping component."
                    continue
                }
            }
        }

        $compData = $currentManifest."$comp"
        if ($null -eq $compData) { Write-Warning "Component $comp not found in retrieved manifest."; continue }

        $osNode = $compData."windows-x86_64"

        if ($null -eq $osNode) { Write-Warning "Component $comp does not have a 'windows-x86_64' entry. Skipping." continue }

        # We look for a key matching "cuda13", "cuda12", etc.
        $cudaKey = "cuda$cudamajor"
        $asset = if ($osNode.PSObject.Properties.Name -contains $cudaKey) { $osNode.$cudaKey } else { $osNode }
        
        if ($null -eq $asset -or $null -eq $asset.relative_path) { Write-Warning "Could not find a valid Component for $comp at 'windows-x86_64' asset. Skipping."; continue }

        # Add granular metadata to our tracking object
        $versionInfo[$comp] = @{
            "name"              = $compData.name
            "version"           = $compData.version
            "release_date"      = $currentManifest.release_date
            "release_label"     = $currentManifest.release_label
            "release_product"   = $currentManifest.release_product
            "date"              = (Get-Date).ToString("yyyy-MM-dd")
        }

        $downloadUrl = "$currentBaseUrl/$($asset.relative_path)"
        $zipFile = Join-Path $env:TEMP "$comp.zip"
        $tempExtract = Join-Path $env:TEMP "cuda_temp_$(Get-Random)"
        
        Write-Host "Deploying $($compData.name) (v$($compData.version))..." -ForegroundColor Yellow
        
        # Download
        Invoke-WebRequest -Uri $downloadUrl -OutFile $zipFile
        
        # Extract to a unique temporary folder
        Expand-Archive -Path $zipFile -DestinationPath $tempExtract -Force
        
        # Flattening Logic
        # Find the nested folder (e.g., cuda_nvcc-windows-x86_64-13.2.51-archive)
        $internalFolder = Get-ChildItem -Path $tempExtract -Directory | Select-Object -First 1
        
        if ($internalFolder) {
            Get-ChildItem -Path $internalFolder.FullName | ForEach-Object {
                $destPath = Join-Path $cudaInstallDir $_.Name
                if ($_.PSIsContainer -and (Test-Path $destPath)) {
                    Copy-Item -Path "$($_.FullName)\*" -Destination $destPath -Recurse -Force
                } else {
                    Copy-Item -Path $_.FullName -Destination $cudaInstallDir -Recurse -Force
                }
            }
        }
        Remove-Item $zipFile, $tempExtract -Recurse -Force -ErrorAction SilentlyContinue
    }
    
    # --- 6. DLL Relocation (Fixing Redist Structure for Windows) ---
    Write-Host "Relocating DLLs from lib to bin for runtime discovery..." -ForegroundColor Cyan
    if (Test-Path $cudaLibDir) {
        $dlls = Get-ChildItem -Path $cudaLibDir -Filter "*.dll" -Recurse
        foreach ($dll in $dlls) {
            $dest = Join-Path $cudaBinPath $dll.Name
            if (!(Test-Path $dest)) {
                Move-Item -Path $dll.FullName -Destination $cudaBinPath -Force
            }
        }
    }
    
    # create nvvmcicc computesanitizer  symlinks in cuda\bin
    $nvvmcicc_source = Join-Path  $cudanvvmBinPath $nvvmcicctool
    $nvvmcicc_target = Join-Path $cudaBinPath $nvvmcicctool
    
    if (Test-Path $nvvmcicc_source) {
        if (Test-Path $nvvmcicc_target) { Remove-Item $nvvmcicc_target -Force -ErrorAction SilentlyContinue }
        try {
            New-Item -ItemType SymbolicLink -Path $nvvmcicc_target -Value $nvvmcicc_source -ErrorAction Stop | Out-Null
            Write-Host "[LINKED] $nvvmcicctool in $cudaBinPath" -ForegroundColor Gray
        }
        catch {
            # Fallback to hardlink if developer mode is off/insufficient permissions
            New-Item -ItemType HardLink -Path $nvvmcicc_target -Value $nvvmcicc_source | Out-Null
        }
    }
    else {
        Write-Warning "Optional tool $nvvmcicctool not found in $cudaBinPath distribution; skipping symlink."
    }

    $computesanitizer_source = Join-Path  $computesanitizerPath $computesanitizertool
    $computesanitizer_target = Join-Path $cudaBinPath $computesanitizertool
    
    if (Test-Path $computesanitizer_source) {
        if (Test-Path $computesanitizer_target) { Remove-Item $computesanitizer_target -Force -ErrorAction SilentlyContinue }
        try {
            New-Item -ItemType SymbolicLink -Path $computesanitizer_target -Value $computesanitizer_source -ErrorAction Stop | Out-Null
            Write-Host "[LINKED] $computesanitizertool in $cudaBinPath" -ForegroundColor Gray
        }
        catch {
            # Fallback to hardlink if developer mode is off/insufficient permissions
            New-Item -ItemType HardLink -Path $computesanitizer_target -Value $computesanitizer_source | Out-Null
        }
    }
    else {
        Write-Warning "Optional tool $computesanitizertool not found in $cudaBinPath distribution; skipping symlink."
    }

    # --- 5b. Manual TensorRT Installation ---
    if ($tensorrtLink -and $tensorrtLink -like "*.zip") {
        Write-Host "--- Processing TensorRT Package ---" -ForegroundColor Cyan
        
        # Extract version from filename (e.g., TensorRT-10.16.0.72)
        $trtFileName = Split-Path $tensorrtLink -Leaf
        $trtZipFile = Join-Path $env:TEMP $trtFileName
        $trtTempExtract = Join-Path $env:TEMP "trt_temp_$(Get-Random)"
        
        Write-Host "Downloading TensorRT from $tensorrtLink..." -ForegroundColor Yellow
        Invoke-WebRequest -Uri $tensorrtLink -OutFile $trtZipFile -UseBasicParsing
    
        Write-Host "Extracting TensorRT..." -ForegroundColor Gray
        if (!(Test-Path $trtTempExtract)) { New-Item -Path $trtTempExtract -ItemType Directory }
        Expand-Archive -Path $trtZipFile -DestinationPath $trtTempExtract -Force
    
        # Flatten TensorRT structure into the CUDA Install Dir
        # Most TRT zips have a single root folder like TensorRT-10.x.x.x/
        $trtRoot = Get-ChildItem -Path $trtTempExtract -Directory | Select-Object -First 1
        if ($trtRoot) {
            Write-Host "Merging TensorRT files into $cudaInstallDir..." -ForegroundColor Gray
            Get-ChildItem -Path $trtRoot.FullName | ForEach-Object {
                $destPath = Join-Path $cudaInstallDir $_.Name
                if ($_.PSIsContainer -and (Test-Path $destPath)) {
                    # Merge folders (bin, lib, include)
                    Copy-Item -Path "$($_.FullName)\*" -Destination $destPath -Recurse -Force
                }
                else {
                    # Copy files (READMEs, LICENSEs)
                    Copy-Item -Path $_.FullName -Destination $cudaInstallDir -Recurse -Force
                }
            }
            
            # Update Metadata
            $versionInfo["tensorrt"] = @{
                "name"      = "NVIDIA TensorRT"
                "version"   = ($trtRoot.Name -replace "TensorRT-", "")
                "source"    = $tensorrtLink
                "date"      = (Get-Date).ToString("yyyy-MM-dd")
            }
        }
    
        # Cleanup
        Remove-Item $trtZipFile, $trtTempExtract -Recurse -Force -ErrorAction SilentlyContinue
        Write-Host "[SUCCESS] TensorRT integrated." -ForegroundColor Green
    }

    # Finalize Version Metadata File
    $versionInfo | ConvertTo-Json -Depth 5 | Out-File -FilePath $versionFile -Encoding utf8 -Force
    Write-Host "Detailed metadata saved to: $versionFile" -ForegroundColor Gray
}

# Finalize Environment Helper
if (Test-Path $nvccExePath) {
    # Create Environment Helper
    Write-Host "Generating environment helper script..." -ForegroundColor Cyan
    $cudaEnvScript = Join-Path $EnvironmentDir "env-cuda.ps1"

    # Generate Environment Helper with Clean Paths
    $cudaInstallDir = $cudaInstallDir.TrimEnd('\')
    $cudaBinPath = $cudaBinPath.TrimEnd('\')
    $cudaBinx64Path = $cudaBinx64Path.TrimEnd('\')
    $cudaLibDir = $cudaLibDir.TrimEnd('\')
    $cudaLibx64Dir = $cudaLibx64Dir.TrimEnd('\')
    $cudaIncludeDir = Join-Path $cudaInstallDir "include"
    $cudaCMakePath = $cudaInstallDir.Replace('\', '/')
    $cudanvvmPath = $cudanvvmPath.TrimEnd('\')
    $cudanvvmBinPath = $cudanvvmBinPath.TrimEnd('\')
    $cudanvvmBinx64Path = Join-Path $cudanvvmBinPath "x64"
    $cudanvvmLibx64Dir = Join-Path $cudanvvmPath "lib\x64"
    $cudanvvmIncludeDir = Join-Path $cudanvvmPath "include"
    $computesanitizerPath = $computesanitizerPath.TrimEnd('\')
    $computesanitizerIncludeDir = Join-Path $computesanitizerPath "include"

    # Define the version-specific variable name (e.g., CUDA_PATH_V13_2)
    $versionVarName = "CUDA_PATH_V$cudaenvmajorMinor"

    # Using a literal here-string with -replace to avoid accidental expansion of $env:PATH during creation
    $EnvContent = @'
# CUDA Environment Setup
$cudaroot = "VALUE_ROOT_PATH"
$cudabin = "VALUE_BIN_PATH"
$cudabinx64 = "VALUE_BINX64_PATH"
$cudalib = "VALUE_LIB_PATH"
$cudalibx64 = "VALUE_LIBX64_PATH"
$cudainclude = "VALUE_INCLUDE_PATH"
$cudacmakepath = "VALUE_CMAKE_PATH"
$cudaversion = "VALUE_VERSION"
$cudanvvmbin = "VALUE_NVVM_BIN_PATH"
$cudanvvmbinx64 = "VALUE_NVVM_BINX64_PATH"
$cudanvvmlibx64 = "VALUE_NVVM_LIBX64_PATH"
$cudanvvminclude = "VALUE_NVVM_INCLUDE_PATH"
$cudacsatbin = "VALUE_C_SAT_BIN_PATH"
$cudacsatlib = "VALUE_C_SAT_LIB_PATH"
$cudacsatinclude = "VALUE_C_SAT_INCLUDE_PATH"
$env:CUDA_HOME = $cudaroot
$env:CUDA_PATH = $cudaroot
$env:VERSION_VAR_NAME = $cudaroot
$env:CUDA_TOOLKIT_ROOT_DIR = $cudaroot
$env:CUDA_ROOT = $cudaroot
$env:CUDA_BIN = $cudabin + ";" + $cudabinx64 + ";" + $cudanvvmbin + ";" + $cudanvvmbinx64 + ";" + $cudacsatbin
$env:CUDA_INCLUDEDIR = $cudainclude + ";" + $cudanvvminclude + ";" + $cudacsatinclude
$env:CUDA_LIBRARYDIR = $cudalib + ";" + $cudalibx64 + ";" + $cudanvvmlibx64 + ";" + $cudacsatlib
if ($env:CMAKE_PREFIX_PATH -notlike "*$cudacmakepath*") { $env:CMAKE_PREFIX_PATH = $cudacmakepath + ";" + $env:CMAKE_PREFIX_PATH }
"$cudainclude", "$cudanvvminclude", "$cudacsatinclude" | ForEach-Object { if ($env:INCLUDE -notlike "*$_*") { $env:INCLUDE = $_ + ";" + $env:INCLUDE } }
"$cudalib", "$cudalibx64", "$cudanvvmlibx64", "$cudacsatlib" | ForEach-Object { if ($env:LIB -notlike "*$_*") { $env:LIB = $_ + ";" + $env:LIB } }
"$cudabin", "$cudabinx64", "$cudanvvmbin", "$cudanvvmbinx64", "$cudacsatbin" | ForEach-Object { if ($env:PATH -notlike "*$_*") { $env:PATH = $_ + ";" + $env:PATH } }
Write-Host "CUDA Environment Loaded (Version: $cudaversion) (Bin: $cudabin)" -ForegroundColor Green
Write-Host "CUDA_ROOT: $env:CUDA_ROOT" -ForegroundColor Gray
'@  -replace "VALUE_ROOT_PATH", $cudaInstallDir `
    -replace "VALUE_INCLUDE_PATH", $cudaIncludeDir `
    -replace "VALUE_LIB_PATH", $cudaLibDir `
    -replace "VALUE_LIBX64_PATH", $cudaLibx64Dir `
    -replace "VALUE_BIN_PATH", $cudaBinPath `
    -replace "VALUE_BINX64_PATH", $cudaBinx64Path `
    -replace "VALUE_CMAKE_PATH", $cudaCMakePath `
    -replace "VERSION_VAR_NAME", $versionVarName `
    -replace "VALUE_VERSION", $cudaVersion `
    -replace "VALUE_NVVM_BIN_PATH", $cudanvvmBinPath `
    -replace "VALUE_NVVM_BINX64_PATH", $cudanvvmBinx64Path `
    -replace "VALUE_NVVM_LIBX64_PATH", $cudanvvmLibx64Dir `
    -replace "VALUE_NVVM_INCLUDE_PATH", $cudanvvmIncludeDir `
    -replace "VALUE_C_SAT_BIN_PATH", $computesanitizerPath `
    -replace "VALUE_C_SAT_LIB_PATH", $computesanitizerPath `
    -replace "VALUE_C_SAT_INCLUDE_PATH", $computesanitizerIncludeDir

    $EnvContent | Out-File -FilePath $cudaEnvScript -Encoding utf8
    Write-Host "Created: $cudaEnvScript" -ForegroundColor Gray
    
    # Update Current Session
    if (Test-Path $cudaEnvScript) { . $cudaEnvScript } else {
        Write-Error "cuda dep install finished but $cudaEnvScript was not created."
        return
    }
    
    # --- 10. Symlink to Global Binaries ---
    Write-Host "Creating global symlink to: $GlobalBinDir..." -ForegroundColor Cyan

    # Create Symlink
    foreach ($cudatool in $cudatools) {
        if ($cudatool -eq $nvvmcicctool) {
            $source = Join-Path $cudanvvmBinPath $cudatool
            $target = Join-Path $GlobalBinDir $cudatool
        } elseif ($cudatool -eq $computesanitizertool) {
            $source = Join-Path $computesanitizerPath $cudatool
            $target = Join-Path $GlobalBinDir $cudatool
        } else{
            $source = Join-Path $cudaBinPath $cudatool
            $target = Join-Path $GlobalBinDir $cudatool
        }
        
        if (Test-Path $source) {
            if (Test-Path $target) { Remove-Item $target -Force -ErrorAction SilentlyContinue }
            try {
                New-Item -ItemType SymbolicLink -Path $target -Value $source -ErrorAction Stop | Out-Null
                Write-Host "[LINKED] $cudatool in $GlobalBinDir" -ForegroundColor Gray
            }
            catch {
                # Fallback to hardlink if developer mode is off/insufficient permissions
                New-Item -ItemType HardLink -Path $target -Value $source | Out-Null
            }
        }
        else {
            Write-Warning "Optional tool $cudatool not found in $cudaBinPath distribution; skipping symlink."
        }
    }
    
    Write-Host "[LINKED] CUDA is now globally available via %BINARIES_PATH%" -ForegroundColor Green
    
    Write-Host "Cuda Toolkit Version: $cudaVersion" -ForegroundColor Gray

    if ($withMachineEnvironment)
    {
        $cudaMachineEnvScript = Join-Path $EnvironmentDir "machine-env-cuda.ps1"

        # Generating Machine Environment wich add to the persist registry machine Environment
        $MachineEnvContent = @'
# CUDA Machine Environment Setup

# --- 0. Self-Elevation Logic ---
$IsAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$ScopeColor = "Cyan"

if (-not $IsAdmin) {
    Write-Host "Elevation required to set cuda system variables and VS BuildCustomizations. Relaunching as Administrator..." -ForegroundColor Yellow
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

$cudaroot = "VALUE_ROOT_PATH"
$cudabin = "VALUE_BIN_PATH"
$cudabinx64 = "VALUE_BINX64_PATH"
$cudaversion = "VALUE_VERSION"
$cudanvvmbin = "VALUE_NVVM_BIN_PATH"
$cudanvvmbinx64 = "VALUE_NVVM_BINX64_PATH"
$cudacsatbin = "VALUE_C_SAT_BIN_PATH"

$cuVer = $cudaversion.Split('.')[0..1] -join "."
$verPath = "v$cuVer"

$EnvMapping = [ordered]@{
    "CUDA_HOME"         = $cudaroot
    "CUDA_PATH"         = $cudaroot
    "VERSION_VAR_NAME"   = $cudaroot
}

$TargetScope = if ($IsAdmin) { "Machine" } else { "User" }
$RegPath = if ($IsAdmin) { "System\CurrentControlSet\Control\Session Manager\Environment" } else { "Environment" }
$RegRoot = if ($IsAdmin) { "LocalMachine" } else { "CurrentUser" }

Write-Host "Cleaning up legacy CUDA_PATH_V variables..." -ForegroundColor Gray

# 1. Get all environment variables from the registry
$RegKey = [Microsoft.Win32.Registry]::$RegRoot.OpenSubKey($RegPath, $true)
$AllValues = $RegKey.GetValueNames()

# 2. Identify and Remove variables that match the pattern but aren't the current version
foreach ($ValueName in $AllValues) {
    # Check for the pattern (e.g., CUDA_PATH_V12_1) and ensure it's not our current version
    if ($ValueName -like "CUDA_PATH_V*" -and $ValueName -ne "VERSION_VAR_NAME") {
        Write-Host "  Purging: $ValueName" -ForegroundColor Yellow
        
        # This explicitly passes a null pointer to the Win32 API, 
        # which is the standard trigger for deleting an environment variable.
        [Environment]::SetEnvironmentVariable($ValueName, [NullString]::Value, $TargetScope)

        # This removes the entry from the HKLM hardware/hive level immediately.
        try {
            if ($RegKey.GetValue($ValueName)) {
                $RegKey.DeleteValue($ValueName, $false)
            }
        }
        catch {
            Write-Warning "  Direct registry deletion failed for ${ValueName}: $($_.Exception.Message)"
        }
        
        # Remove from current session environment
        if (Test-Path "Env:\$ValueName") { Remove-Item "Env:\$ValueName" -Force -ErrorAction SilentlyContinue }
    }
}
$RegKey.Close()

foreach ($Entry in $EnvMapping.GetEnumerator())
{
    $VarName = $Entry.Key
    $TargetPath = $Entry.Value
    
    # Update Current Process
    Set-Item -Path "Env:\$VarName" -Value $TargetPath
    
    # Persist to Registry (Machine if Admin, else User)
    [Environment]::SetEnvironmentVariable($VarName, $TargetPath, $TargetScope)
}

$RegEnvMapping = [ordered]@{
    "CUDA_PATH"         = $cudaroot
    "CUDA_C_SAN_BIN"    = $cudacsatbin
    "CUDA_NVMM_BINX64"  = $cudanvvmbinx64
    "CUDA_NVMM_BIN"     = $cudanvvmbin
    "CUDA_BINX64"       = $cudabinx64
    "CUDA_BIN"          = $cudabin
}

# Open the registry key once
$RegKey = [Microsoft.Win32.Registry]::$RegRoot.OpenSubKey($RegPath, $true)

# Open the registry key directly to read the RAW (unexpanded) string
$CurrentRawPath = $RegKey.GetValue("NVIDIA_PATH", "", [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)

# Cleanup: Remove empty strings, any path containing \cuda\$verPath, and the current target (to avoid dups)
$CleanedPathList = $CurrentRawPath -split ';' | Where-Object { 
    -not [string]::IsNullOrWhitespace($_) -and 
    $_ -notlike "*\cuda\$verPath*"
}

$NewRawPath = ($CleanedPathList -join ";").Replace(";;", ";")

foreach ($Entry in $RegEnvMapping.GetEnumerator())
{
    $VarName = $Entry.Key
    $TargetPath = $Entry.Value
    
    # Update Current Process
    Set-Item -Path "Env:\$VarName" -Value $TargetPath
    
    # Rebuild
    $NewRawPath = ($TargetPath + ";" + $NewRawPath + ";").Replace(";;", ";")
    
    Write-Host "[UPDATED] ($TargetScope) '$VarName' synced in NVIDIA_PATH" -ForegroundColor $ScopeColor
}

# Save as ExpandString
$RegKey.SetValue("NVIDIA_PATH", $NewRawPath, [Microsoft.Win32.RegistryValueKind]::ExpandString)
$env:NVIDIA_PATH = $NewRawPath

$RegKey.Close()

# --- 1. Visual Studio MSBuild Integration (v180 / VS 2026) ---
$cudaMsBuildSource = Join-Path $cudaroot "visual_studio_integration\MSBuildExtensions"
if (Test-Path $cudaMsBuildSource) {
    # Discover VS Install Dir if not in env
    $VSinstallPath = $env:VSINSTALLDIR
    if ([string]::IsNullOrWhitespace($VSinstallPath)) {
        # Fallback to standard 2026 path if the dev-shell wasn't inherited
        $vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
        if (Test-Path $vswhere) {
            $VSinstallPath = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
        }
    }

    $msBuildDest = Join-Path $VSinstallPath "MSBuild\Microsoft\VC\v180\BuildCustomizations"

    if (Test-Path $VSinstallPath) {
        Write-Host "Integrating CUDA MSBuild Extensions into VS 2026..." -ForegroundColor Cyan
        #if (!(Test-Path $msBuildDest)) { New-Item -Path $msBuildDest -ItemType Directory -Force | Out-Null }
        
        Get-ChildItem -Path $cudaMsBuildSource -File | ForEach-Object {
            $destFile = Join-Path $msBuildDest $_.Name
            Copy-Item -Path $_.FullName -Destination $destFile -Recurse -Force
            Write-Host "  [DEPLOYED] $($_.Name)" -ForegroundColor Gray
        }
    } else {
        Write-Warning "Visual Studio 2026 directory not found. Skipping BuildCustomizations copy."
    }
}

$env:CUDA_ROOT = $cudaroot
Write-Host "CUDA Environment Loaded (Version: $cudaversion) (Bin: $cudabin)" -ForegroundColor Green
Write-Host "CUDA_ROOT: $env:CUDA_ROOT" -ForegroundColor Gray
'@  -replace "VALUE_ROOT_PATH", $cudaInstallDir `
    -replace "VALUE_BIN_PATH", $cudaBinPath `
    -replace "VALUE_BINX64_PATH", $cudaBinx64Path `
    -replace "VERSION_VAR_NAME", $versionVarName `
    -replace "VALUE_VERSION", $cudaVersion `
    -replace "VALUE_NVVM_BIN_PATH", $cudanvvmBinPath `
    -replace "VALUE_NVVM_BINX64_PATH", $cudanvvmBinx64Path `
    -replace "VALUE_C_SAT_BIN_PATH", $computesanitizerPath

        $MachineEnvContent | Out-File -FilePath $cudaMachineEnvScript -Encoding utf8
        Write-Host "Created: $cudaMachineEnvScript" -ForegroundColor Gray
        
        # --- Interaction: Prompt to apply persistent changes ---
        Write-Host ""
        $choice = Read-Host "Do you want to run the Machine Environment script now to persist CUDA changes to the Registry? (y/n)"
        if ($choice -eq 'y' -or $choice -eq 'Y') {
            Write-Host "Executing $cudaMachineEnvScript..." -ForegroundColor Yellow
            try {
                # Start the generated script. It handles its own elevation logic.
                & $cudaMachineEnvScript
            }
            catch {
                Write-Error "Failed to execute the Machine Environment script: $($_.Exception.Message)"
            }
        }
        else {
            Write-Host "Skipped persistent registry update. You can run it later at: $cudaMachineEnvScript" -ForegroundColor Gray
        }
    }
} else {
    Write-Error "nvcc.exe was not found in the $cudaBinPath folder."
    return
}
