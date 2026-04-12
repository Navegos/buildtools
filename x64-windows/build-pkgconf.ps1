# Copyright 2026 (C) Navegos. DevelVitorF. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
# file:x64-windows/build-pkgconf.ps1

param (
    [Parameter(HelpMessage = "Base workspace path", Mandatory = $false)]
    [string]$workspacePath = $null,

    [Parameter(HelpMessage = "pkgconf git repo url", Mandatory = $false)]
    [string]$gitUrl = "https://github.com/pkgconf/pkgconf.git",
    
    [Parameter(HelpMessage = "pkgconf git branch to sync from", Mandatory = $false)]
    [string]$gitBranch = "master",

    [Parameter(HelpMessage = "Path for pkgconf storage", Mandatory = $false)]
    [string]$pkgconfInstallDir = "$env:LIBRARIES_PATH\pkgconf",
    
    [Parameter(HelpMessage = "Force a full purge of the local pkgconf version before continuing", Mandatory = $false)]
    [switch]$forceCleanup,
    
    [Parameter(HelpMessage = "Add's pkgconf Machine Environment Variables. Requires Machine Administrator Rights.", Mandatory = $false)]
    [switch]$withMachineEnvironment
)

# Capture parameters
$pkgconfWorkspacePath = $workspacePath
$pkgconfGitUrl = $gitUrl
$pkgconfGitBranch = $gitBranch
$pkgconfForceCleanup = $forceCleanup
$pkgconfWithMachineEnvironment = $withMachineEnvironment

if ([string]::IsNullOrWhitespace($env:ENVIRONMENT_PATH) -or -not (Test-Path $env:ENVIRONMENT_PATH) -or [string]::IsNullOrWhitespace($env:BINARIES_PATH) -or -not (Test-Path $env:BINARIES_PATH) -or [string]::IsNullOrWhitespace($env:LIBRARIES_PATH) -or -not (Test-Path $env:LIBRARIES_PATH)) {
    Write-Error "User Environment variables missing. With administrator privileges run adduserpaths.ps1 -LibrariesDir 'Path\for\Libraries' -BinariesDir 'Path\for\Binaries' -EnvironmentDir 'Path\for\Environment'"
    return
}

$EnvironmentDir = "$env:ENVIRONMENT_PATH"

$pkgconfEnvScript = Join-Path $EnvironmentDir "env-pkgconf.ps1"
$pkgconfMachineEnvScript = Join-Path $EnvironmentDir "machine-env-pkgconf.ps1"
$RootpkgconfWorkspacePath = if ([string]::IsNullOrWhitespace($pkgconfWorkspacePath)) { Get-Location } else { $pkgconfWorkspacePath }

# --- 1. Cleanup Mechanism ---
function Invoke-pkgconfVersionPurge {
    param ([string]$InstallPath)
    Write-Host "--- Initiating pkgconf Purge ---" -ForegroundColor Cyan

    if ($pkgconfWithMachineEnvironment) {
        $pkgconfCleanMachineEnvScript = Join-Path $env:TEMP "clean-machine-env-pkgconf.ps1"

        # Generating Clean Machine Environment wich removes the persist registry machine Environment
        $CleanMachineEnvContent = @'
# pkgconf Clean Machine Environment Setup

# --- 0. Self-Elevation Logic ---
$IsAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$ScopeColor = "Cyan"

if (-not $IsAdmin) {
    Write-Host "Elevation required to clean pkgconf system variables. Relaunching as Administrator..." -ForegroundColor Yellow
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

$pkgconfroot = "VALUE_ROOT_PATH"

$TargetScope = if ($IsAdmin) { "Machine" } else { "User" }
$RegPath = if ($IsAdmin) { "System\CurrentControlSet\Control\Session Manager\Environment" } else { "Environment" }
$RegRoot = if ($IsAdmin) { "LocalMachine" } else { "CurrentUser" }

# 1. Registry Cleanup (TOOLS_PATH)
$RegKey = [Microsoft.Win32.Registry]::$RegRoot.OpenSubKey($RegPath, $true)

# Open the registry key directly to read the RAW (unexpanded) string
$RawPath = $RegKey.GetValue("TOOLS_PATH", "", [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)

# Cleanup: Remove empty strings, any path containing $pkgconfroot,
$CleanPath = ($RawPath -split ';' | Where-Object { $_ -notlike "*$pkgconfroot*" }) -join ";"

# Save as ExpandString
$RegKey.SetValue("TOOLS_PATH", $CleanPath, [Microsoft.Win32.RegistryValueKind]::ExpandString)
$env:TOOLS_PATH = $CleanPath

$RegKey.Close()

Write-Host "[REMOVED] ($TargetScope) all '*$pkgconfroot*' removed from TOOLS_PATH" -ForegroundColor $ScopeColor
'@  -replace "VALUE_ROOT_PATH", $InstallPath

        $CleanMachineEnvContent | Out-File -FilePath $pkgconfCleanMachineEnvScript -Encoding utf8
        Write-Host "Created: $pkgconfCleanMachineEnvScript" -ForegroundColor Gray
        
        # --- Interaction: Prompt to remove persistent changes ---
        Write-Host ""
        $choice = Read-Host "Administrator rights required to Clean Machine Environment pkgconf changes? (y/n)"
        if ($choice -eq 'y' -or $choice -eq 'Y') {
            Write-Host "Executing $pkgconfCleanMachineEnvScript..." -ForegroundColor Yellow
            try {
                # Start the generated script. It handles its own elevation logic.
                & $pkgconfCleanMachineEnvScript
            }
            catch {
                Write-Error "Failed to execute the Clean Machine Environment script: $($_.Exception.Message)"
                return
            }
        }
        else {
            Write-Error "Skipped Clean Machine Environment pkgconf changes."
            return
        }

        # Cleanup
        Remove-Item $pkgconfCleanMachineEnvScript -Recurse -Force -ErrorAction SilentlyContinue
    }
    
    $Source = Join-Path $RootpkgconfWorkspacePath "pkgconf"
    
    # 2. Filesystem Clean (Requires checking for locked files)
    # delete everithing we create don't fail later
    if (Test-Path $pkgconfEnvScript) {
        Write-Host "  [DELETING] $pkgconfEnvScript" -ForegroundColor Yellow
        Remove-Item $pkgconfEnvScript -Recurse -Force -ErrorAction SilentlyContinue
    }
    if (Test-Path $pkgconfMachineEnvScript) {
        Write-Host "  [DELETING] $pkgconfMachineEnvScript" -ForegroundColor Yellow
        Remove-Item $pkgconfMachineEnvScript -Recurse -Force -ErrorAction SilentlyContinue
    }
    if (Test-Path $InstallPath) {
        Write-Host "  [DELETING] $InstallPath" -ForegroundColor Yellow
        Remove-Item $InstallPath -Recurse -Force -ErrorAction SilentlyContinue
    }
    if (Test-Path $Source) {
        Write-Host "  [DELETING] $Source" -ForegroundColor Yellow
        Remove-Item $Source -Recurse -Force -ErrorAction SilentlyContinue
    }
    
    # remove local Env variables for current session
    Get-ChildItem Env:\PKGCONF_PATH* | Remove-Item -ErrorAction SilentlyContinue
    Get-ChildItem Env:\PKGCONF_ROOT* | Remove-Item -ErrorAction SilentlyContinue
    Get-ChildItem Env:\PKGCONF_BIN* | Remove-Item -ErrorAction SilentlyContinue

    Write-Host "--- pkgconf Purge Complete ---" -ForegroundColor Green
}

# We need to call Purge before dep-pkgconf or dependencie builds fails
if ($pkgconfForceCleanup) {
    Invoke-pkgconfVersionPurge -InstallPath $pkgconfInstallDir
}

# --- 1. Initialize Visual Studio 2026 Dev Environment ---
$DevShellBootstrapScript = Join-Path $PSScriptRoot "dev-shell.ps1"
if (Test-Path $DevShellBootstrapScript) { . $DevShellBootstrapScript } else {
    Write-Error "Required dependency '$DevShellBootstrapScript' not found!"
    return
}

# --- 2. Initialize git environment if missing ---
if (-not $env:GIT_PATH) {
    $gitEnvScript = Join-Path $EnvironmentDir "env-git.ps1"
    if (Test-Path $gitEnvScript) { . $gitEnvScript } 
    if (-not $env:GIT_PATH) {
        $depgitEnvScript = Join-Path $PSScriptRoot "dep-git.ps1"
        if (Test-Path $depgitEnvScript) { . $depgitEnvScript }
        else {
            Write-Error "CRITICAL: Cannot load Git environment. git is missing and $depgitEnvScript was not found."
            return
        }
    }
}

# --- 3. Initialize cmake environment if missing ---
if (-not $env:CMAKE_PATH) {
    $cmakeEnvScript = Join-Path $EnvironmentDir "env-cmake.ps1"
    if (Test-Path $cmakeEnvScript) { . $cmakeEnvScript } 
    if (-not $env:CMAKE_PATH) {
        $depcmakeEnvScript = Join-Path $PSScriptRoot "dep-cmake.ps1"
        if (Test-Path $depcmakeEnvScript) { . $depcmakeEnvScript }
        else {
            Write-Error "CRITICAL: Cannot load CMake environment. cmake is missing and $depcmakeEnvScript was not found."
            return
        }
    }
}

# --- 4. Initialize ninja environment if missing ---
if (-not $env:NINJA_PATH) {
    $ninjaEnvScript = Join-Path $EnvironmentDir "env-ninja.ps1"
    if (Test-Path $ninjaEnvScript) { . $ninjaEnvScript }
    if (-not $env:NINJA_PATH) {
        $depninjaEnvScript = Join-Path $PSScriptRoot "dep-ninja.ps1"
        if (Test-Path $depninjaEnvScript) { . $depninjaEnvScript }
        else {
            Write-Error "CRITICAL: Cannot load ninja environment. ninja is missing and $depninjaEnvScript was not found."
            return
        }
    }
}

# --- 5. Initialize clang environment if missing ---
if (-not $env:LLVM_PATH) {
    $llvmEnvScript = Join-Path $EnvironmentDir "env-llvm.ps1"
    if (Test-Path $llvmEnvScript) { . $llvmEnvScript }
    if (-not $env:LLVM_PATH) {
        $depllvmEnvScript = Join-Path $PSScriptRoot "dep-llvm.ps1"
        if (Test-Path $depllvmEnvScript) { . $depllvmEnvScript }
        else {
            Write-Error "CRITICAL: Cannot load clang environment. clang is missing and $depllvmEnvScript was not found."
            return
        }
    }
}

# Load python requirement
if (-not $env:PYTHON_PATH) {
    $pythonEnvScript = Join-Path $EnvironmentDir "env-python.ps1"
    if (Test-Path $pythonEnvScript) { . $pythonEnvScript }
    if (-not $env:PYTHON_PATH) {
        $deppythonEnvScript = Join-Path $PSScriptRoot "dep-python.ps1"
        if (Test-Path $deppythonEnvScript) { . $deppythonEnvScript }
        else {
            Write-Error "CRITICAL: Cannot load python environment. python is missing and $deppythonEnvScript was not found."
            return
        }
    }
}

$RootPath = $RootpkgconfWorkspacePath

# --- 6. Path Resolution ---
Push-Location $RootPath

$Source = Join-Path $RootPath "pkgconf"
$BuildDirShared = Join-Path $Source "build_shared"
#$BuildDirStatic = Join-Path $Source "build_static" # static build broken
$RepoUrl = $pkgconfGitUrl
$Branch = $pkgconfGitBranch
#$CMakeSource = $Source
$tag_name = $Branch
$url = $RepoUrl

# --- 7. Source Management ---
if (Test-Path $Source) {
    Write-Host "Syncing pkgconf ($Branch) at $Source..." -ForegroundColor Cyan
    Set-Location $Source
    git fetch --all
    git reset --hard "origin/$Branch"
    git pull --recurse-submodules --force
    $tagCommit = (& git rev-parse --verify HEAD).Trim()
}
else {
    Write-Host "Cloning pkgconf ($Branch) into $Source..." -ForegroundColor Cyan
    git clone --recurse-submodules $RepoUrl $Source -b $Branch
    Set-Location $Source
    $tagCommit = (& git rev-parse --verify HEAD).Trim()
}

# --- 8. Clean & Build (Shadow Swap Logic) ---
# We use .exe extension so it remains 'executable' and detectable
$GlobalBinDir = "$env:BINARIES_PATH"
$TargetLink = Join-Path $GlobalBinDir "pkgconf.exe"
$TargetPConfLink = Join-Path $GlobalBinDir "pkg-config.exe"
# Remove existing symlink we are creating a new one
if (Test-Path $TargetLink) { Remove-Item $TargetLink -Force -ErrorAction SilentlyContinue }
if (Test-Path $TargetPConfLink) { Remove-Item $TargetPConfLink -Force -ErrorAction SilentlyContinue }
$pkgconfBinPath = Join-Path $pkgconfInstallDir "bin"

# 2. Check for existing installation
$pkgconfExePath = Join-Path $pkgconfInstallDir "pkgconf.exe"
if (-not (Test-Path $pkgconfExePath)) { $pkgconfExePath = Join-Path $pkgconfBinPath "pkgconf.exe" }

# Ensure fresh Install directory
if (Test-Path $pkgconfInstallDir) {
    Write-Host "Wiping existing installation at $pkgconfInstallDir..." -ForegroundColor Yellow
    Remove-Item $pkgconfInstallDir -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "[INSTALL] Creating fresh directory: $pkgconfBinPath" -ForegroundColor Cyan
New-Item -Path $pkgconfBinPath -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null

# Ensure fresh build directory
if (Test-Path $BuildDirShared) { Remove-Item $BuildDirShared -Recurse -Force -ErrorAction SilentlyContinue }
#if (Test-Path $BuildDirStatic) { Remove-Item $BuildDirStatic -Recurse -Force -ErrorAction SilentlyContinue }
New-Item -Path $BuildDirShared -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null
#New-Item -Path $BuildDirStatic -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null

# 1. Set the environment to use Clang-cl
# save the compiler env if we are calling betwen scripts
<# $envCC = $env:CC
$envCXX = $env:CXX
$envAR = $env:AR
$envLINK = $env:LINK
$env:CC = "cl"
$env:CXX = "cl"
$env:AR = "lib"
$env:LINK = "link" #>

# 2. Setup (Disabling tests and docs for a faster bootstrap)
<# Write-Host "Configuring, Building and Installing static pkgconf to $pkgconfInstallDir..." -ForegroundColor Green
meson setup $BuildDirStatic `
    --buildtype=release `
    --default-library=static `
    -Dfuzzing=false `
    --prefix="$pkgconfInstallDir"`
    -Db_vscrt=md #>
    
#if ($LASTEXITCODE -ne 0) { Write-Error "pkgconf meson static configuration failed.";
    <# $env:CC = $envCC; $env:CXX = $envCXX; $env:AR = $envAR; $env:LINK = $envLINK; #>
#    Pop-Location; return }

# 3. Build
#meson compile -C $BuildDirStatic

#if ($LASTEXITCODE -ne 0) { Write-Error "pkgconf meson static compile failed.";
<# $env:CC = $envCC; $env:CXX = $envCXX; $env:AR = $envAR; $env:LINK = $envLINK; #>
#Pop-Location; return }

# 4. Install
#meson install -C $BuildDirStatic --tags devel,runtime

#if ($LASTEXITCODE -ne 0) { Write-Error "pkgconf meson static install failed.";
<# $env:CC = $envCC; $env:CXX = $envCXX; $env:AR = $envAR; $env:LINK = $envLINK; #>
#Pop-Location; return }

# Rename static lib to pkgconfs.lib to avoid collision
$StaticLibPath = Join-Path $pkgconfInstallDir "lib/pkgconf.lib"
$NewStaticName = Join-Path $pkgconfInstallDir "lib/pkgconfs.lib"
if (Test-Path $StaticLibPath) {
    Move-Item -Path $StaticLibPath -Destination $NewStaticName -Force -ErrorAction SilentlyContinue
    Write-Host "Static library renamed to pkgconfs.lib" -ForegroundColor Gray
}

# 2. Setup (Disabling tests and docs for a faster bootstrap)
Write-Host "Configuring, Building and Installing shared pkgconf to $pkgconfInstallDir..." -ForegroundColor Green
meson setup $BuildDirShared `
    --buildtype=release `
    --default-library=shared `
    -Dfuzzing=false `
    --prefix="$pkgconfInstallDir" <# `
    -Db_vscrt=md #>
    
if ($LASTEXITCODE -ne 0) { Write-Error "pkgconf meson shared configuration failed."; <# $env:CC = $envCC; $env:CXX = $envCXX; #> Pop-Location; return }

# 3. Build
meson compile -C $BuildDirShared

if ($LASTEXITCODE -ne 0) { Write-Error "pkgconf meson shared compile failed."; <# $env:CC = $envCC; $env:CXX = $envCXX; #> Pop-Location; return }

# 4. Install
meson install -C $BuildDirShared

if ($LASTEXITCODE -ne 0) { Write-Error "pkgconf meson shared install failed."; <# $env:CC = $envCC; $env:CXX = $envCXX; #> Pop-Location; return }

Write-Host "Successfully built and installed pkgconf to $pkgconfInstallDir!" -ForegroundColor Green

# restore compiler env
<# $env:CC = $envCC; $env:CXX = $envCXX; $env:AR = $envAR; $env:LINK = $envLINK; #>

# Cleanup temporary build debris
Remove-Item $BuildDirShared -Recurse -Force -ErrorAction SilentlyContinue
#Remove-Item $BuildDirStatic -Recurse -Force -ErrorAction SilentlyContinue

# Generate Environment Helper with Clean Paths
$pkgconfInstallDir = $pkgconfInstallDir.TrimEnd('\')
$pkgconfIncludeDir = Join-Path $pkgconfInstallDir "include\pkgconf"
$pkgconfLibDir = Join-Path $pkgconfInstallDir "lib"
$pkgconfBinPath = Join-Path $pkgconfInstallDir "bin"
$pkgconfCMakePath = $pkgconfInstallDir.Replace('\', '/')

#$StaticLib = Join-Path $pkgconfLibDir "pkgconfstatic.lib"
$SharedLib = Join-Path $pkgconfLibDir "pkgconf.lib"
$BinaryLib = Join-Path $pkgconfBinPath "pkgconf.dll"
$versionFile = Join-Path $pkgconfInstallDir "version.json"

# Fallback check for "pkgconf.lib" / "pkgconfs.lib" naming convention
#if (-not (Test-Path $StaticLib)) { $StaticLib = Join-Path $pkgconfLibDir "pkgconfs.lib" }
#if (-not (Test-Path $SharedLib)) { $SharedLib = Join-Path $pkgconfLibDir "pkgconf.lib" }
#if (-not (Test-Path $BinaryLib)) { $BinaryLib = Join-Path $pkgconfBinPath "pkgconf.dll" }

# --- 9. Symlink to Global Binaries ---
$pkgconfExePath = Join-Path $pkgconfInstallDir "pkgconf.exe"
if (-not (Test-Path $pkgconfExePath)) { $pkgconfExePath = Join-Path $pkgconfBinPath "pkgconf.exe" }

if ((Test-Path $pkgconfExePath) <# -or (Test-Path $StaticLib) #> -or (Test-Path $SharedLib)) {
    # pkgconf --version usually returns a single string like "1.12.1" or "1.12.1.git"
    $rawVersion = (& $pkgconfExePath --version).Trim()
    # We extract only the numeric part (e.g., 1.12.1) so [version] can handle it
    if ($rawVersion -match '^(\d+\.\d+\.\d+)') { $localVersion = $Matches[1] } else { $localVersion = "0.0.0" }

    # 2. Extract SOVERSION and LIBVERSION from meson.build
    $mesonPath = Join-Path $Source "meson.build"
    $soversion = "0"
    $libVersion = "0.0.0"

    if (Test-Path $mesonPath) {
        $mesonContent = Get-Content $mesonPath -Raw
        
        # This pattern starts at 'library', skips all the source files (.*?s),
        # and then captures the version and soversion only from that block.
        $pattern = "(?s)library\s*\(.*?version\s*:\s*'([^']+)'.*?soversion\s*:\s*'([^']+)'"
    
        if ($mesonContent -match $pattern) {
            $libVersion = $Matches[1] # This will be '7.0.0'
            $soversion = $Matches[2] # This will be '7'
        }
    }
    
    if (-not (Test-Path $BinaryLib)) { $BinaryLib = Join-Path $pkgconfBinPath "pkgconf-$soversion.dll" }

    # Save new version state
    $pkgconfVersion = $localVersion
    $versionInfo = @{
        url        = $url;
        tag_name   = $tag_name;
        commit     = $tagCommit;
        version    = $localVersion;    # Project Version (2.5.1)
        rawversion = $rawVersion;
        soversion  = $soversion;       # ABI Version (7)
        libversion = $libVersion;      # Library Version (7.0.0)
        date       = (Get-Date).ToString("yyyy-MM-dd");
        updated_at = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssZ");
        type       = "source_build";
    }
    $versionInfo | ConvertTo-Json | Out-File -FilePath $versionFile -Encoding utf8 -Force

    Write-Host "Creating global symlink: $TargetLink" -ForegroundColor Cyan

    # Remove existing symlink we are creating a new one
    if (Test-Path $TargetLink) { Remove-Item $TargetLink -Force -ErrorAction SilentlyContinue }
    if (Test-Path $TargetPConfLink) { Remove-Item $TargetPConfLink -Force -ErrorAction SilentlyContinue }
    
    # Create the Symbolic Link
    try {
        New-Item -Path $TargetLink -ItemType SymbolicLink -Value $pkgconfExePath -ErrorAction Stop | Out-Null
        New-Item -Path $TargetPConfLink -ItemType SymbolicLink -Value $pkgconfExePath -ErrorAction Stop | Out-Null
        Write-Host "[LINKED] pkgconf (Global) -> $pkgconfExePath" -ForegroundColor Green
    }
    catch {
        New-Item -Path $TargetLink -ItemType HardLink -Value $pkgconfExePath | Out-Null
        New-Item -Path $TargetPConfLink -ItemType HardLink -Value $pkgconfExePath | Out-Null
        Write-Host "[HARDLINKED] pkgconf (Global) -> $pkgconfExePath" -ForegroundColor Green
    }
    
    Write-Host "[LINKED] pkgconf is now globally available via %BINARIES_PATH%" -ForegroundColor Green

    # --- 10. Create Environment Helper ---
    Write-Host "Generating environment helper script..." -ForegroundColor Cyan
    $EnvContent = @'
# PKGCONF Environment Setup
$pkgconfroot = "VALUE_ROOT_PATH"
$pkgconfinclude = "VALUE_INCLUDE_PATH"
$pkgconflibrary = "VALUE_LIB_PATH"
$pkgconfbin = "VALUE_BIN_PATH"
$pkgconfversion = "VALUE_VERSION"
$pkgconfbinary = "VALUE_BINARY"
$pkgconfshared = "VALUE_SHARED"
#$pkgconfstatic = "VALUE_STATIC"
$pkgconfcmakepath = "VALUE_CMAKE_PATH"
$env:PKGCONF_PATH = $pkgconfroot
$env:PKGCONF_ROOT = $pkgconfroot
$env:PKGCONF_BIN = $pkgconfbin
$env:PKGCONF_INCLUDE_DIR = $pkgconfinclude
$env:PKGCONF_LIBRARY_DIR = $pkgconflibrary
$env:BINARY_LIB_PKGCONF = $pkgconfbinary
$env:SHARED_LIB_PKGCONF = $pkgconfshared
#$env:STATIC_LIB_PKGCONF = $pkgconfstatic
if ($env:CMAKE_PREFIX_PATH -notlike "*$pkgconfcmakepath*") { $env:CMAKE_PREFIX_PATH = $pkgconfcmakepath + ";" + $env:CMAKE_PREFIX_PATH; $env:CMAKE_PREFIX_PATH = ($env:CMAKE_PREFIX_PATH).Replace(";;", ";") }
if ($env:INCLUDE -notlike "*$pkgconfinclude*") { $env:INCLUDE = $pkgconfinclude + ";" + $env:INCLUDE; $env:INCLUDE = ($env:INCLUDE).Replace(";;", ";") }
if ($env:LIB -notlike "*$pkgconflibrary*") { $env:LIB = $pkgconflibrary + ";" + $env:LIB; $env:LIB = ($env:LIB).Replace(";;", ";") }
if ($env:PATH -notlike "*$pkgconfbin*") { $env:PATH = $pkgconfbin + ";" + $env:PATH; $env:PATH = ($env:PATH).Replace(";;", ";") }
Write-Host "pkgconf Environment Loaded (Version: $pkgconfversion) (Bin: $pkgconfbin)" -ForegroundColor Green
Write-Host "PKGCONF_ROOT: $env:PKGCONF_ROOT" -ForegroundColor Gray
'@  -replace "VALUE_ROOT_PATH", $pkgconfInstallDir `
    -replace "VALUE_INCLUDE_PATH", $pkgconfIncludeDir `
    -replace "VALUE_LIB_PATH", $pkgconfLibDir `
    -replace "VALUE_BIN_PATH", $pkgconfBinPath `
    -replace "VALUE_VERSION", $pkgconfVersion `
    -replace "VALUE_SHARED", $SharedLib `
    -replace "VALUE_BINARY", $BinaryLib `
    -replace "VALUE_CMAKE_PATH", $pkgconfCMakePath

    <# -replace "VALUE_STATIC", $StaticLib ` #>

    $EnvContent | Out-File -FilePath $pkgconfEnvScript -Encoding utf8 -force
    Write-Host "Created: $pkgconfEnvScript" -ForegroundColor Gray

    # Update Current Session
    if (Test-Path $pkgconfEnvScript) { . $pkgconfEnvScript } else {
        Write-Error "pkgconf build install finished but $pkgconfEnvScript was not created."
        Pop-Location; return
    }

    Write-Host "pkgconf Version: $(& $pkgconfExePath --version)" -ForegroundColor Gray

    if ($pkgconfWithMachineEnvironment) {
        # Generating Machine Environment wich add to the persist registry machine Environment
        $MachineEnvContent = @'
# pkgconf Machine Environment Setup

# --- 0. Self-Elevation Logic ---
$IsAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$ScopeColor = "Cyan"

if (-not $IsAdmin) {
    Write-Host "Elevation required to set pkgconf system variables. Relaunching as Administrator..." -ForegroundColor Yellow
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

$pkgconfroot = "VALUE_ROOT_PATH"
$pkgconfbin = "VALUE_BIN_PATH"
$pkgconfversion = "VALUE_VERSION"

$TargetScope = if ($IsAdmin) { "Machine" } else { "User" }
$RegPath = if ($IsAdmin) { "System\CurrentControlSet\Control\Session Manager\Environment" } else { "Environment" }
$RegRoot = if ($IsAdmin) { "LocalMachine" } else { "CurrentUser" }

# Open the registry key once
$RegKey = [Microsoft.Win32.Registry]::$RegRoot.OpenSubKey($RegPath, $true)

# Open the registry key directly to read the RAW (unexpanded) string
$CurrentRawPath = $RegKey.GetValue("TOOLS_PATH", "", [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)

# Cleanup: Remove empty strings, any path containing $pkgconfroot, and the current target (to avoid dups)
$CleanedPathList = $CurrentRawPath -split ';' | Where-Object { 
    -not [string]::IsNullOrWhitespace($_) -and 
    $_ -notlike "*$pkgconfroot*"
}

$NewRawPath = ($CleanedPathList -join ";").Replace(";;", ";")

$TargetPath = $pkgconfbin

# Rebuild
$NewRawPath = ($NewRawPath + ";" + $TargetPath + ";").Replace(";;", ";")
Write-Host "[UPDATED] ($TargetScope) '$pkgconfbin' synced in TOOLS_PATH" -ForegroundColor $ScopeColor

# Save as ExpandString
$RegKey.SetValue("TOOLS_PATH", $NewRawPath, [Microsoft.Win32.RegistryValueKind]::ExpandString)
$env:TOOLS_PATH = $NewRawPath

$RegKey.Close()

$env:PKGCONF_ROOT = $pkgconfroot
Write-Host "pkgconf Environment Loaded (Version: $pkgconfversion) (Bin: $pkgconfbin)" -ForegroundColor Green
Write-Host "PKGCONF_ROOT: $env:PKGCONF_ROOT" -ForegroundColor Gray
'@  -replace "VALUE_ROOT_PATH", $pkgconfInstallDir `
    -replace "VALUE_BIN_PATH", $pkgconfBinPath `
    -replace "VALUE_VERSION", $pkgconfVersion

        $MachineEnvContent | Out-File -FilePath $pkgconfMachineEnvScript -Encoding utf8 -force
        Write-Host "Created: $pkgconfMachineEnvScript" -ForegroundColor Gray
        
        # --- Interaction: Prompt to apply persistent changes ---
        Write-Host ""
        $choice = Read-Host "Do you want to run the Machine Environment script now to persist pkgconf changes to the Registry? (y/n)"
        if ($choice -eq 'y' -or $choice -eq 'Y') {
            Write-Host "Executing $pkgconfMachineEnvScript..." -ForegroundColor Yellow
            try {
                # Start the generated script. It handles its own elevation logic.
                & $pkgconfMachineEnvScript
            }
            catch {
                Write-Error "Failed to execute the Machine Environment script: $($_.Exception.Message)"
            }
        }
        else {
            Write-Host "Skipped persistent registry update. You can run it later at: $pkgconfMachineEnvScript" -ForegroundColor Gray
        }
    }

    # --- Return to Start ---
    Pop-Location
    Write-Host "Successfully Done! and returned to: $(Get-Location)" -ForegroundColor DarkGreen
}
else {
    Write-Error "pkgconf.exe was not found in the $pkgconfBinPath folder."
    if (Test-Path $TargetLink) { 
        Write-Host "Cleaning up dead symlink at $TargetLink..." -ForegroundColor Yellow
        Remove-Item $TargetLink -Force -ErrorAction SilentlyContinue 
    }if (Test-Path $TargetPConfLink) { 
        Write-Host "Cleaning up dead symlink at $TargetPConfLink..." -ForegroundColor Yellow
        Remove-Item $TargetPConfLink -Force -ErrorAction SilentlyContinue 
    }
    Pop-Location; return
}
