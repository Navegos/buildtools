# Copyright 2026 (C) Navegos. DevelVitorF. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
# file:x64-windows/build-cmake.ps1

param (
    [Parameter(HelpMessage = "Base workspace path", Mandatory = $false)]
    [string]$WorkspacePath = "",

    [Parameter(HelpMessage = "cmake git repo url", Mandatory = $false)]
    [string]$GitUrl = "https://github.com/Navegos/CMake.git",
    
    [Parameter(HelpMessage = "cmake git branch to sync from", Mandatory = $false)]
    [string]$GitBranch = "master",

    [Parameter(HelpMessage = "Path for cmake storage", Mandatory = $false)]
    [string]$cmakeInstallDir = "$env:LIBRARIES_PATH\cmake"
)

if ([string]::IsNullOrWhitespace($env:ENVIRONMENT_PATH) -or -not (Test-Path $env:ENVIRONMENT_PATH) -or [string]::IsNullOrWhitespace($env:BINARIES_PATH) -or -not (Test-Path $env:BINARIES_PATH) -or [string]::IsNullOrWhitespace($env:LIBRARIES_PATH) -or -not (Test-Path $env:LIBRARIES_PATH)) {
    Write-Error "User Environment variables missing. With administrator privileges run adduserpaths.ps1 -LibrariesDir 'Path\for\Libraries' -BinariesDir 'Path\for\Binaries' -EnvironmentDir 'Path\for\Environment'"
    return
}

# we need this set(UTILITIES BZIP2 CPPDAP CURL EXPAT FORM JSONCPP LIBARCHIVE LIBLZMA LIBRHASH LIBUV NGHTTP2 ZLIB ZSTD)

$EnvironmentDir = "$env:ENVIRONMENT_PATH"

# --- 1. Initialize Visual Studio 2026 Dev Environment ---
$DevShellBootstrapScript = Join-Path $PSScriptRoot "dev-shell.ps1"
if (Test-Path $DevShellBootstrapScript) { . $DevShellBootstrapScript } else {
    Write-Error "Required dependency '$DevShellBootstrapScript' not found!"
    return
}

$RootPath = if ([string]::IsNullOrWhitespace($WorkspacePath)) { Get-Location } else { $WorkspacePath }

# --- 2. Initialize git environment if missing ---
if (!(Get-Command git -ErrorAction SilentlyContinue)) {
    $gitEnvScript = Join-Path $EnvironmentDir "env-git.ps1"
    if (Test-Path $gitEnvScript) { . $gitEnvScript } 
    if (!(Get-Command git -ErrorAction SilentlyContinue)) {
        $depgitEnvScript = Join-Path $PSScriptRoot "dep-git.ps1"
        if (Test-Path $depgitEnvScript) {
            . $depgitEnvScript
        }
        else {
            Write-Error "CRITICAL: Cannot load Git environment. git is missing and $depgitEnvScript was not found."
            return
        }
    }
}

# --- 3. Initialize cmake environment if missing ---
if (!(Get-Command cmake -ErrorAction SilentlyContinue)) {
    $cmakeEnvScript = Join-Path $EnvironmentDir "env-cmake.ps1"
    if (Test-Path $cmakeEnvScript) { . $cmakeEnvScript } 
    if (!(Get-Command cmake -ErrorAction SilentlyContinue)) {
        $depcmakeEnvScript = Join-Path $PSScriptRoot "dep-cmake.ps1"
        if (Test-Path $depcmakeEnvScript) {
            . $depcmakeEnvScript
        }
        else {
            Write-Error "CRITICAL: Cannot load CMake environment. cmake is missing and $depcmakeEnvScript was not found."
            return
        }
    }
}

# --- 4. Initialize ninja environment if missing ---
if (!(Get-Command ninja -ErrorAction SilentlyContinue)) {
    $ninjaEnvScript = Join-Path $EnvironmentDir "env-ninja.ps1"
    if (Test-Path $ninjaEnvScript) { . $ninjaEnvScript }
    if (!(Get-Command ninja -ErrorAction SilentlyContinue)) {
        $depninjaEnvScript = Join-Path $PSScriptRoot "dep-ninja.ps1"
        if (Test-Path $depninjaEnvScript) {
            . $depninjaEnvScript
        }
        else {
            Write-Error "CRITICAL: Cannot load ninja environment. ninja is missing and $depninjaEnvScript was not found."
            return
        }
    }
}

# --- 5. Initialize clang environment if missing ---
if (!(Get-Command clang -ErrorAction SilentlyContinue)) {
    $llvmEnvScript = Join-Path $EnvironmentDir "env-llvm.ps1"
    if (Test-Path $llvmEnvScript) { . $llvmEnvScript }
    if (!(Get-Command clang -ErrorAction SilentlyContinue)) {
        $depllvmEnvScript = Join-Path $PSScriptRoot "dep-llvm.ps1"
        if (Test-Path $depllvmEnvScript) {
            . $depllvmEnvScript
        }
        else {
            Write-Error "CRITICAL: Cannot load clang environment. clang is missing and $depllvmEnvScript was not found."
            return
        }
    }
}

# --- 6. Path Resolution ---
Push-Location $RootPath

$Source         = Join-Path $RootPath "cmake"
$BuildDir       = Join-Path $Source "build_dir"
$RepoUrl        = $GitUrl
$Branch         = $GitBranch
$CMakeSource    = $Source
$tag_name       = $Branch
$url            = $RepoUrl

# --- 7. Source Management ---
if (Test-Path $Source) {
    Write-Host "Syncing CMake ($Branch) at $Source..." -ForegroundColor Cyan
    Set-Location $Source
    git fetch --all
    git reset --hard "origin/$Branch"
    git pull --recurse-submodules --force
    $tagCommit = (& git rev-parse --verify HEAD).Trim()
}
else {
    Write-Host "Cloning CMake ($Branch) into $Source..." -ForegroundColor Cyan
    git clone --recurse-submodules $RepoUrl $Source -b $Branch
    Set-Location $Source
    $tagCommit = (& git rev-parse --verify HEAD).Trim()
}

# --- 8. Clean & Build (Shadow Swap Logic) ---
# We use .exe extension so it remains 'executable' and detectable
$GlobalBinDir = "$env:BINARIES_PATH"
$cmakeBinPath = Join-Path $cmakeInstallDir "bin"

# 2. Check for existing installation
$cmakeExePath = Join-Path $cmakeBinPath "cmake.exe"
$versionFile = Join-Path $cmakeInstallDir "version.json"

$cmaketools = @("cmake.exe", "cmake-gui.exe", "cmcldeps.exe", "cpack.exe", "ctest.exe")
$cmaketools_old = @("cmake_old.exe", "cmake-gui_old.exe", "cmcldeps_old.exe", "cpack_old.exe", "ctest_old.exe")

if (!(Test-Path $cmakeInstallDir)) {
    New-Item -ItemType Directory -Path $cmakeInstallDir -Force -ErrorAction SilentlyContinue | Out-Null
    New-Item -ItemType Directory -Path $cmakeBinPath -Force -ErrorAction SilentlyContinue | Out-Null
}

# Loop through each tool for the Shadow Swap
for ($i = 0; $i -lt $cmaketools.Count; $i++) {
    $toolName = $cmaketools[$i]
    $oldToolName = $cmaketools_old[$i]
    
    $currentExePath = Join-Path $cmakeBinPath $toolName
    $tempExePath = Join-Path $cmakeBinPath $oldToolName
    $globalLinkPath = Join-Path $GlobalBinDir $toolName

    if (Test-Path $currentExePath) {
        # 1. Remove previous backup if it exists
        if (Test-Path $tempExePath) { Remove-Item $tempExePath -Force -ErrorAction SilentlyContinue }
        
        # 2. Rename existing binary (The "Shadow Swap")
        Move-Item -Path $currentExePath -Destination $tempExePath -Force -ErrorAction SilentlyContinue
        Write-Host "[SWAP] Active $toolName -> $oldToolName" -ForegroundColor Yellow

        if (Test-Path $tempExePath) {
            # 3. Clean up existing global symlink
            if (Test-Path $globalLinkPath) { Remove-Item $globalLinkPath -Force -ErrorAction SilentlyContinue }
            
            # 4. Create new global symlink/hardlink to the OLD/TEMP file
            # This keeps the environment functional DURING the build process
            try {
                New-Item -ItemType SymbolicLink -Path $globalLinkPath -Value $tempExePath -ErrorAction Stop | Out-Null
                Write-Host "[LINKED] $toolName (Global) -> $oldToolName" -ForegroundColor Green
            }
            catch {
                New-Item -ItemType HardLink -Path $globalLinkPath -Value $tempExePath | Out-Null
            }
        }
        else {
            Write-Error "CRITICAL: Could not find $toolName to swap at $tempExePath"
            # Cleanup dead global link if move failed
            if (Test-Path $globalLinkPath) { Remove-Item $globalLinkPath -Force -ErrorAction SilentlyContinue }
            Pop-Location
            return
        }
    }
}

# Ensure fresh build directory
if (Test-Path $BuildDir) { Remove-Item $BuildDir -Recurse -Force -ErrorAction SilentlyContinue }
New-Item -ItemType Directory -Path $BuildDir -Force -ErrorAction SilentlyContinue | Out-Null

Write-Host "Configuring with Clang/Ninja..." -ForegroundColor Cyan
cmake -G "Ninja" `
    -S "$CMakeSource" `
    -B "$BuildDir" `
    -DCMAKE_POLICY_DEFAULT_CMP0109=NEW `
    -DCMAKE_C_COMPILER="clang" `
    -DCMAKE_CXX_COMPILER="clang++" `
    -DCMAKE_INSTALL_PREFIX="$cmakeInstallDir" `
    -DCMAKE_BUILD_TYPE=Release `
    -DBUILD_TESTING=OFF `
    -DCMAKE_C_FLAGS="-Wno-deprecated-declarations -D_CRT_SECURE_NO_WARNINGS=1" `
    -DCMAKE_CXX_FLAGS="-Wno-deprecated-declarations -D_CRT_SECURE_NO_WARNINGS=1"

if ($LASTEXITCODE -ne 0) { Write-Error "CMake configuration failed."; Pop-Location; return }

Write-Host "Building and Installing to $cmakeInstallDir..." -ForegroundColor Green
cmake --build "$BuildDir" --target INSTALL --config Release --parallel

if ($LASTEXITCODE -ne 0) { Write-Error "CMake Build failed with exit code $LASTEXITCODE"; Pop-Location; return }

Write-Host "Successfully built and installed CMake to $cmakeInstallDir!" -ForegroundColor Green

# Cleanup temporary build debris
Remove-Item $BuildDir -Recurse -Force -ErrorAction SilentlyContinue

# Generate Environment Helper with Clean Paths
$cmakeBinPath = $cmakeBinPath.TrimEnd('\')
$cmakeInstallDir = $cmakeInstallDir.TrimEnd('\')

# --- 9. Create Environment Helper ---
Write-Host "Generating environment helper script..." -ForegroundColor Cyan
$cmakeEnvScript = Join-Path $EnvironmentDir "env-cmake.ps1"
$EnvContent = @'
# CMAKE Environment Setup
$cmakebin = "VALUE_BIN_PATH"
$cmakeroot = "VALUE_ROOT_PATH"
$env:CMAKE_PATH = $cmakeroot
$env:CMAKE_ROOT = $cmakeroot
$env:CMAKE_BIN = $cmakebin
if ($env:PATH -notlike "*$cmakebin*") { $env:PATH = $cmakebin + ";" + $env:PATH }
Write-Host "CMAKE Environment Loaded." -ForegroundColor Green
Write-Host "CMAKE_ROOT: $env:CMAKE_ROOT" -ForegroundColor Gray
'@ -replace "VALUE_BIN_PATH", $cmakeBinPath -replace "VALUE_ROOT_PATH", $cmakeInstallDir

$EnvContent | Out-File -FilePath $cmakeEnvScript -Encoding utf8
Write-Host "Created: $cmakeEnvScript" -ForegroundColor Gray

# Update Current Session
if (Test-Path $cmakeEnvScript) { . $cmakeEnvScript } else {
    Write-Error "cmake build install finished but $cmakeEnvScript was not created."
    return
}

# --- 10. Symlink to Global Binaries ---
if (Test-Path $cmakeExePath) {
    $rawVersion = (& $cmakeExePath --version | Select-Object -First 1).Trim()
    # We extract only the numeric part (e.g., 1.12.1) so [version] can handle it
    if ($rawVersion -match 'version\s+(\d+\.\d+\.\d+)') { $localVersion = $Matches[1] } else { $localVersion = "0.0.0" }
    
    # Save new version state
    $versionInfo = @{
        url        = $url;
        tag_name   = $tag_name;
        commit     = $tagCommit;
        version    = $localVersion;
        rawversion = $rawVersion;
        date       = (Get-Date).ToString("yyyy-MM-dd");
        updated_at = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssZ");
        type       = "source_build";
    }
    $versionInfo | ConvertTo-Json | Out-File -FilePath $versionFile -Encoding utf8 -Force
    
    # Create the Symbolic Link
    foreach ($toolName in $cmaketools) {
        $newExePath    = Join-Path $cmakeBinPath $toolName
        $globalLinkPath = Join-Path $GlobalBinDir $toolName
        
        if (Test-Path $newExePath) {
            if (Test-Path $globalLinkPath) { Remove-Item $globalLinkPath -Force -ErrorAction SilentlyContinue }
            try {
                New-Item -ItemType SymbolicLink -Path $globalLinkPath -Value $newExePath -ErrorAction Stop | Out-Null
                Write-Host "[LINKED] CMake (Global) -> $newExePath" -ForegroundColor Green
            }
            catch {
                New-Item -ItemType HardLink -Path $globalLinkPath -Value $newExePath | Out-Null
            }
        }
    }

    Write-Host "[LINKED] CMake is now globally available via %BINARIES_PATH%" -ForegroundColor Green
}
else {
    Write-Error "CRITICAL: Could not find cmake.exe to symlink at $cmakeExePath"

    $cmaketools | ForEach-Object { 
        $globalLinkPath = Join-Path $GlobalBinDir $_
        if (Test-Path $globalLinkPath) {
            Write-Host "Cleaning up dead symlink at $globalLinkPath..." -ForegroundColor Yellow
            Remove-Item $globalLinkPath -Force -ErrorAction SilentlyContinue
        } 
    }
    Pop-Location
    return
}

# --- 11. Post-Build Cleanup ---
$cmaketools_old | ForEach-Object { 
    $oldFile = Join-Path $cmakeBinPath $_
    if (Test-Path $oldFile) { Remove-Item $oldFile -Force -ErrorAction SilentlyContinue } 
}

Write-Host "CMake Version: $(& $cmakeExePath --version | Select-Object -First 1)" -ForegroundColor Gray

# --- Return to Start ---
Pop-Location
Write-Host "Done! and returned to: $(Get-Location)" -ForegroundColor Gray
