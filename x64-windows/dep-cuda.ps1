# Copyright 2026 (C) Navegos. DevelVitorF. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
# file:x64-windows/dep-cuda.ps1

param (
    [Parameter(HelpMessage="Path for cuda storage like path\cuda", Mandatory=$false)]
    [string]$cudaInstallDir = "$env:LIBRARIES_PATH\cuda",

    [Parameter(HelpMessage="CUDA Version", Mandatory=$false)]
    [string]$cudaVersion = "13.2.0"
)

# 1. Bootstrap Environment if variables are missing
if ([string]::IsNullOrWhitespace($env:ENVIRONMENT_PATH) -or -not (Test-Path $env:ENVIRONMENT_PATH) -or [string]::IsNullOrWhitespace($env:BINARIES_PATH) -or -not (Test-Path $env:BINARIES_PATH) -or [string]::IsNullOrWhitespace($env:LIBRARIES_PATH) -or -not (Test-Path $env:LIBRARIES_PATH)) {
    Write-Error "User Environment variables missing. Please run adduserpaths.ps1 -LibrariesDir 'Path\for\Libraries' BinariesDir 'Path\for\Binaries' -EnvironmentDir 'Path\for\Environment'"
    return
}

$EnvironmentDir = "$env:ENVIRONMENT_PATH"

# --- 1. Initialize Visual Studio 2026 Dev Environment dependencie requirement for Cuda Toolkit ---
$DevShellBootstrapScript = Join-Path $PSScriptRoot "devshell.ps1"
if (Test-Path $DevShellBootstrapScript) { . $DevShellBootstrapScript } else {
    Write-Error "Required dependency '$DevShellBootstrapScript' not found!"
    return
}

$nvccCheck = Get-Command nvcc -ErrorAction SilentlyContinue

#$majorMinor = $cudaVersion.Split('.')[0..1] -join "." # e.g., "13.2"
$pathmajorMinor = "v" + ($cudaVersion.Split('.')[0..1] -join ".") # e.g., "v13.2"
$envmajorMinor = $cudaVersion.Split('.')[0..1] -join "_" # e.g., "13_2"
$cudaInstallDir = Join-Path $cudaInstallDir $pathmajorMinor
$cudaBinPath = Join-Path $cudaInstallDir "bin"

function Get-CudaVersionFromJson {
    param([string]$installDir)
    
    $jsonPath = Join-Path $installDir "version.json"
    
    if (Test-Path $jsonPath) {
        try {
            # Load and parse the JSON
            $versionData = Get-Content $jsonPath -Raw | ConvertFrom-Json
            
            # Navigate the NVIDIA structure: usually { "cuda": { "version": "12.4.1" } }
            # Or { "components": { "cudart": { "version": "..." } } }
            if ($versionData.cuda.version) {
                return $versionData.cuda.version
            } 
            elseif ($versionData.components.cudart.version) {
                return $versionData.components.cudart.version
            }
        } catch {
            Write-Warning "Failed to parse version.json: $($_.Exception.Message)"
        }
    }
    return $null
}

if ($nvccCheck) {
    Write-Host "Cuda Toolkit is already installed at: $($nvccCheck.Source)" -ForegroundColor Green

    # 1. Locate the bin folder and the root folder
    $cudaBinPath = Split-Path -Path $nvccCheck.Source -Parent
    $cudaInstallDir = Split-Path -Path $cudaBinPath -Parent

    $cudaVersion = Get-CudaVersionFromJson -installDir $cudaInstallDir

    #$majorMinor = $cudaVersion.Split('.')[0..1] -join "." # e.g., "13.2"
    #$pathmajorMinor = "v" + ($cudaVersion.Split('.')[0..1] -join ".") # e.g., "v13.2"
    $envmajorMinor = $cudaVersion.Split('.')[0..1] -join "_" # e.g., "13_2"

    Write-Host "Cuda Toolkit Version: $cudaVersion" -ForegroundColor Gray
} else {
    # 1. Define the base NVIDIA directory
    $nvidiaRoot = "${env:ProgramFiles}\NVIDIA GPU Computing Toolkit\CUDA"

    # 2. We specifically look for the bin folder to avoid finding nvcc in 'samples' or 'doc'
    $foundNvcc = Get-ChildItem -Path $nvidiaRoot -Filter "nvcc.exe" -Recurse -Depth 3 -ErrorAction SilentlyContinue | 
             Where-Object { $_.DirectoryName -like "*\bin" } | 
             Select-Object -First 1
    
    if ($foundNvcc) {
        Write-Host "Found CUDA at default location. Linking..." -ForegroundColor Yellow
        
        $cudaBinPath = $foundNvcc.DirectoryName
        $cudaInstallDir = Split-Path -Path $cudaBinPath -Parent

        $cudaVersion = Get-CudaVersionFromJson -installDir $cudaInstallDir
         
        $envmajorMinor = $cudaVersion.Split('.')[0..1] -join "_" # e.g., "13_2"

        Write-Host "Cuda Toolkit Version: $cudaVersion" -ForegroundColor Gray
    } else {
        # Im not doing this... Hope some day the Cuda Toolkit Setup for windows gets dynamically smarter. Failing for now.
        Write-Error "Cuda Toolkit not found..."
        Write-Error "Download Nvidia Windows Drivers from:https://www.nvidia.com/en-us/geforce/drivers/"
        Write-Error "Download Cuda Toolkit from:https://developer.nvidia.com/cuda-downloads?target_os=Windows&target_arch=x86_64&target_version=11&target_type=exe_network"
        Write-Error "Install bouth following the instructions..."
        Write-Error "You must re-run this script after Cuda Toolkit installation..."
        return
    }
}

# Finalize Environment Helper
if (Test-Path (Join-Path $cudaBinPath "nvcc.exe")) {
    # Create Environment Helper
    Write-Host "Generating environment helper script..." -ForegroundColor Cyan
    $cudaEnvScript = Join-Path $EnvironmentDir "env-cuda.ps1"

    # Generate Environment Helper with Clean Paths
    #$cudaVersion = Get-CudaVersionFromJson -installDir $cudaInstallDir
    $cudaBinPath = $cudaBinPath.TrimEnd('\')
    $cudaBinx64Path = Join-Path $cudaBinPath "x64"
    $cudaInstallDir = $cudaInstallDir.TrimEnd('\')
    $cudaLibDir = Join-Path $cudaInstallDir "lib"
    $cudaLibx64Dir = Join-Path $cudaLibDir "x64"
    $cudaIncludeDir = Join-Path $cudaInstallDir "include"
    $cudaCMakePath = $cudaInstallDir.Replace('\', '/')

    # Define the version-specific variable name (e.g., CUDA_PATH_V13_2)
    $versionVarName = "CUDA_PATH_V$envmajorMinor"

    # Using a literal here-string with -replace to avoid accidental expansion of $env:PATH during creation
    $EnvContent = @'
# CUDA Environment Setup
$cudabin = "VALUE_BIN_PATH"
$cudabinx64 = "VALUE_BINX64_PATH"
$cudaroot = "VALUE_ROOT_PATH"
$cudalib = "VALUE_LIB_PATH"
$cudalibx64 = "VALUE_LIBX64_PATH"
$cudainclude = "VALUE_INCLUDE_PATH"
$cudacmakepath = "VALUE_CMAKE_PATH"
$cudaversion = "VALUE_VERSION"
$env:CUDA_PATH = $cudaroot
$env:VERSION_VAR_NAME = $cudaroot
$env:CUDA_TOOLKIT_ROOT_DIR = $cudaroot
$env:CUDA_ROOT = $cudaroot
$env:CUDA_BIN = $cudabin + ";" + $cudabinx64
$env:CUDA_INCLUDEDIR = $cudainclude
$env:CUDA_LIBRARYDIR = $cudalib + ";" + $cudalibx64
if ($env:CMAKE_PREFIX_PATH -notlike "*$cudacmakepath*") { $env:CMAKE_PREFIX_PATH = $cudacmakepath + ";" + $env:CMAKE_PREFIX_PATH }
if ($env:INCLUDE -notlike "*$cudainclude*") { $env:INCLUDE = $cudainclude + ";" + $env:INCLUDE }
"$cudalib", "$cudalibx64" | ForEach-Object { if ($env:LIB -notlike "*$_*") { $env:LIB = $_ + ";" + $env:LIB } }
"$cudabin", "$cudabinx64" | ForEach-Object { if ($env:PATH -notlike "*$_*") { $env:PATH = $_ + ";" + $env:PATH } }
if ($env:PATH -notlike "*$cudabin*") { $env:PATH = $cudabin + ";" + $env:PATH }
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
    -replace "VALUE_VERSION", $cudaVersion

    $EnvContent | Out-File -FilePath $cudaEnvScript -Encoding utf8
    Write-Host "Created: $cudaEnvScript" -ForegroundColor Gray
    
    # Update Current Session
    if (Test-Path $cudaEnvScript) { . $cudaEnvScript } else {
        Write-Error "cuda dep install finished but $cudaEnvScript was not created."
        return
    }
    Write-Host "Cuda Toolkit Version: $cudaVersion" -ForegroundColor Gray
} else {
    Write-Error "nvcc.exe was not found in the $cudaBinPath folder."
    return
}
