# Copyright 2026 (C) Navegos. DevelVitorF. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
# file:x64-windows/build-libxml2.ps1

param (
    [Parameter(HelpMessage="Base workspace path", Mandatory=$false)]
    [string]$WorkspacePath = "",

    [Parameter(HelpMessage="libxml2 git repo url", Mandatory=$false)]
    [string]$GitUrl = "https://github.com/Navegos/libxml2.git",
    
    [Parameter(HelpMessage="libxml2 git branch to sync from", Mandatory=$false)]
    [string]$GitBranch = "master",

    [Parameter(HelpMessage="Path for libxml2 library storage", Mandatory=$false)]
    [string]$libxml2InstallDir = "$env:LIBRARIES_PATH\libxml2"
)

# 1. Bootstrap Environment if variables are missing
if ([string]::IsNullOrWhitespace($env:ENVIRONMENT_PATH) -or -not (Test-Path $env:ENVIRONMENT_PATH) -or [string]::IsNullOrWhitespace($env:BINARIES_PATH) -or -not (Test-Path $env:BINARIES_PATH) -or [string]::IsNullOrWhitespace($env:LIBRARIES_PATH) -or -not (Test-Path $env:LIBRARIES_PATH)) {
    Write-Error "User Environment variables missing. Please run adduserpaths.ps1 -LibrariesDir 'Path\for\Libraries' BinariesDir 'Path\for\Binaries' -EnvironmentDir 'Path\for\Environment'"
    return
}

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
        if (Test-Path $depgitEnvScript) { . $depgitEnvScript
        } else {
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
        if (Test-Path $depcmakeEnvScript) { . $depcmakeEnvScript
        } else {
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
        if (Test-Path $depninjaEnvScript) { . $depninjaEnvScript
        } else {
            Write-Error "CRITICAL: Cannot load Ninja environment. ninja is missing and $depninjaEnvScript was not found."
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
        if (Test-Path $depllvmEnvScript) { . $depllvmEnvScript
        } else {
            Write-Error "CRITICAL: Cannot load clang environment. clang is missing and $depllvmEnvScript was not found."
            return
        }
    }
}

# --- 6. Path Resolution ---
Push-Location $RootPath

$Source = Join-Path $RootPath "libxml2"
$BuildDirShared = Join-Path $Source "build_shared"
$BuildDirStatic = Join-Path $Source "build_static"
$RepoUrl    = $GitUrl
$Branch     = $GitBranch
$CMakeSource = $Source

# --- 7. Source Management ---
if (Test-Path $Source) {
    Write-Host "Syncing libxml2 ($Branch) at $Source..." -ForegroundColor Cyan
    Set-Location $Source
    
    # We use a try/catch or simple exit code checks for git operations
    git fetch --all
    git reset --hard "origin/$Branch"
    git pull --recurse-submodules --force

    if ($LASTEXITCODE -ne 0) {
        Write-Error "Git sync failed at $Source. Check your network or branch name ($Branch)."
        Pop-Location; return
    }
} else {
    Write-Host "Cloning libxml2 ($Branch) into $Source..." -ForegroundColor Cyan
    git clone --recurse-submodules $RepoUrl $Source -b $Branch
    
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path $Source)) {
        Write-Error "Git clone failed for $RepoUrl. Please verify the URL and your permissions."
        Pop-Location; return
    }
    Set-Location $Source
}

# --- 8. Clean Final Destination ---
if (Test-Path $libxml2InstallDir) {
    Write-Host "Wiping existing installation at $libxml2InstallDir..." -ForegroundColor Yellow
    Remove-Item $libxml2InstallDir -Recurse -Force -ErrorAction SilentlyContinue
}
New-Item -ItemType Directory -Path $libxml2InstallDir -Force -ErrorAction SilentlyContinue | Out-Null

# Ensure fresh build directory
if (Test-Path $BuildDirShared) { Remove-Item $BuildDirShared -Recurse -Force -ErrorAction SilentlyContinue }
if (Test-Path $BuildDirStatic) { Remove-Item $BuildDirStatic -Recurse -Force -ErrorAction SilentlyContinue }
New-Item -ItemType Directory -Path $BuildDirShared -Force -ErrorAction SilentlyContinue | Out-Null
New-Item -ItemType Directory -Path $BuildDirStatic -Force -ErrorAction SilentlyContinue | Out-Null

# --- Dependencies: ---
[string]$Rootlibxml2InstallDir = Split-Path -Path $libxml2InstallDir -Parent

# Load Zlib requirement
if ([string]::IsNullOrWhiteSpace($env:ZLIB_LIBRARYDIR) -or -not (Test-Path (Join-Path $env:ZLIB_LIBRARYDIR "z.lib"))) {
    $zlibEnvScript = Join-Path $EnvironmentDir "env-zlib.ps1"
    if (Test-Path $zlibEnvScript) { . $zlibEnvScript } else {
        $zlibBuildScript = Join-Path $PSScriptRoot "build-zlib.ps1"
        if (Test-Path $zlibBuildScript) {
            [string]$zlibInstallDir = Join-Path $Rootlibxml2InstallDir "zlib"
            & $zlibBuildScript -WorkspacePath $WorkspacePath -zlibInstallDir $zlibInstallDir
            if (Test-Path $zlibEnvScript) { . $zlibEnvScript } else {
                Write-Error "zlib build finished but $zlibEnvScript was not created."
                return
            }
        } else {
            Write-Error "CRITICAL: Cannot build zlib. zlib is missing and $zlibBuildScript was not found."
            return
        }
    }
}

if ([string]::IsNullOrWhiteSpace($env:LZMA_LIBRARYDIR) -or -not (Test-Path (Join-Path $env:LZMA_LIBRARYDIR "lzma.lib"))) {
    $lzmaEnvScript = Join-Path $EnvironmentDir "env-lzma.ps1"
    if (Test-Path $lzmaEnvScript) { . $lzmaEnvScript } else {
        $lzmaBuildScript = Join-Path $PSScriptRoot "build-lzma.ps1"
        if (Test-Path $lzmaBuildScript) {
            [string]$lzmaInstallDir = Join-Path $Rootlibxml2InstallDir "lzma"
            & $lzmaBuildScript -WorkspacePath $WorkspacePath -lzmaInstallDir $lzmaInstallDir
            if (Test-Path $lzmaEnvScript) { . $lzmaEnvScript } else {
                Write-Error "lzma build finished but $lzmaEnvScript was not created."
                return
            }
        } else {
            Write-Error "CRITICAL: Cannot build lzma. lzma is missing and $lzmaBuildScript was not found."
            return
        }
    }
}

# Load libiconv requirement
if ([string]::IsNullOrWhiteSpace($env:LIBICONV_LIBRARYDIR) -or -not (Test-Path (Join-Path $env:LIBICONV_LIBRARYDIR "iconv.lib"))) {
    $libiconvEnvScript = Join-Path $EnvironmentDir "env-libiconv.ps1"
    if (Test-Path $libiconvEnvScript) { . $libiconvEnvScript } else {
        $deplibiconvEnvScript = Join-Path $PSScriptRoot "dep-libiconv.ps1"
        if (Test-Path $deplibiconvEnvScript) { . $deplibiconvEnvScript
        } else {
            # we are not building libiconv we are getting dependencie libiconv from vcpkg and vcpkg auto builds libiconv if it fails retur error
            Write-Error "CRITICAL: Cannot load libiconv environment. iconv is missing and $libiconvEnvScript was not found."
            return
        }
    }
}

# Load icu requirement
if ([string]::IsNullOrWhiteSpace($env:ICU_LIBRARYDIR) -or -not (Test-Path (Join-Path $env:ICU_LIBRARYDIR "icuuc.lib"))) {
    $icuEnvScript = Join-Path $EnvironmentDir "env-icu.ps1"
    if (Test-Path $icuEnvScript) { . $icuEnvScript } else {
        $depicuEnvScript = Join-Path $PSScriptRoot "dep-icu.ps1"
        if (Test-Path $depicuEnvScript) { . $depicuEnvScript
        } else {
            # we are not building icu we are getting dependencie icu from vcpkg and vcpkg auto builds icu if it fails retur error
            Write-Error "CRITICAL: Cannot load icu environment. iconv is missing and $icuEnvScript was not found."
            return
        }
    }
}

# Common CMake Flags 
$CommonCmakeArgs = @(
    "-G", "Ninja",
    "-DCMAKE_C_COMPILER=clang",
    "-DCMAKE_CXX_COMPILER=clang++",
    "-DCMAKE_BUILD_TYPE=Release",
    "-DLIBXML2_WITH_DOCS=OFF",
    "-DLIBXML2_WITH_HTML=ON",
    "-DLIBXML2_WITH_HTTP=OFF",
    "-DLIBXML2_WITH_ICONV=ON",
    "-DLIBXML2_WITH_ICU=ON",
    "-DLIBXML2_WITH_ISO8859X=ON",
    "-DLIBXML2_WITH_LEGACY=OFF",
    "-DLIBXML2_WITH_OUTPUT=ON",
    "-DLIBXML2_WITH_PATTERN=ON",
    "-DLIBXML2_WITH_PUSH=ON",
    "-DLIBXML2_WITH_REGEXPS=ON",
    "-DLIBXML2_WITH_SAX1=ON",
    "-DLIBXML2_WITH_TESTS=OFF",
    "-DLIBXML2_WITH_THREADS=ON",
    "-DLIBXML2_WITH_TLS=OFF",
    "-DLIBXML2_WITH_VALID=ON",
    "-DLIBXML2_WITH_WINPATH=ON",
    "-DLIBXML2_WITH_XINCLUDE=ON",
    "-DLIBXML2_WITH_XPATH=ON",
    "-DLIBXML2_WITH_ZLIB=ON",
    "-DLIBXML2_WITH_LZMA=ON",
    "-DLIBXML2_WITH_C14N=ON",
    "-DLIBXML2_WITH_READER=ON",
    "-DLIBXML2_WITH_SCHEMAS=ON",
    "-DLIBXML2_WITH_SCHEMATRON=OFF",
    "-DLIBXML2_WITH_THREAD_ALLOC=OFF",
    "-DLIBXML2_WITH_WRITER=ON",
    "-DLIBXML2_WITH_XPTR=ON",
    "-DLIBXML2_WITH_RELAXNG=ON"
)

# --- 9. STAGE 1: Build Static Libraries ---
Write-Host "Building Static (libxml2s.lib)..." -ForegroundColor Cyan
cmake $CommonCmakeArgs `
    -S "$CMakeSource" `
    -B "$BuildDirStatic" `
    -DCMAKE_INSTALL_PREFIX="$libxml2InstallDir" `
    -DBUILD_SHARED_LIBS=OFF `
    -DLIBXML2_WITH_CATALOG=OFF `
    -DLIBXML2_WITH_DEBUG=OFF `
    -DLIBXML2_WITH_MODULES=OFF `
    -DLIBXML2_WITH_PROGRAMS=OFF `
    -DLIBXML2_WITH_PYTHON=OFF `
    -DLIBXML2_WITH_READLINE=OFF `
    -DLIBXML2_WITH_HISTORY=OFF `
    -DCMAKE_C_FLAGS="-Wno-deprecated-declarations -D_CRT_SECURE_NO_WARNINGS=1" `
    -DCMAKE_CXX_FLAGS="-Wno-deprecated-declarations -D_CRT_SECURE_NO_WARNINGS=1"

if ($LASTEXITCODE -ne 0) { Write-Error "libxml2 CMake Static (libxml2s.lib) configuration failed."; Pop-Location; return }

cmake --build "$BuildDirStatic" --target install --config Release --parallel

if ($LASTEXITCODE -ne 0) { Write-Error "libxml2 Static Build failed with exit code $LASTEXITCODE"; Pop-Location; return }

# --- 9.5. Rename Static Libraries (Suffix 's' Only) ---
Write-Host "Applying 's' suffix to static libs..." -ForegroundColor Gray
Get-ChildItem -Path "$libxml2InstallDir\lib\*.lib" | ForEach-Object {
    $newName = $_.BaseName + "s" + $_.Extension
    Move-Item -Path $_.FullName -Destination (Join-Path $_.DirectoryName $newName) -Force -ErrorAction SilentlyContinue
    Write-Host "  -> $newName" -ForegroundColor DarkGray
}

# --- 10. STAGE 2: Build Shared Libraries ---
Write-Host "Building Shared (DLL)..." -ForegroundColor Cyan
cmake $CommonCmakeArgs `
    -S "$CMakeSource" `
    -B "$BuildDirShared" `
    -DCMAKE_INSTALL_PREFIX="$libxml2InstallDir" `
    -DBUILD_SHARED_LIBS=ON `
    -DLIBXML2_WITH_CATALOG=ON `
    -DLIBXML2_WITH_DEBUG=ON `
    -DLIBXML2_WITH_MODULES=ON `
    -DLIBXML2_WITH_PROGRAMS=ON `
    -DLIBXML2_WITH_PYTHON=ON `
    -DLIBXML2_WITH_READLINE=OFF `
    -DLIBXML2_WITH_HISTORY=OFF `
    -DCMAKE_C_FLAGS="-Wno-deprecated-declarations -D_CRT_SECURE_NO_WARNINGS=1" `
    -DCMAKE_CXX_FLAGS="-Wno-deprecated-declarations -D_CRT_SECURE_NO_WARNINGS=1"
    
if ($LASTEXITCODE -ne 0) { Write-Error "libxml2 CMake Shared (DLL) configuration failed."; Pop-Location; return }

cmake --build "$BuildDirShared" --target install --config Release --parallel

if ($LASTEXITCODE -ne 0) { Write-Error "libxml2 Shared Build failed with exit code $LASTEXITCODE"; Pop-Location; return }

# --- 10.5. Relocate Dependency DLLs ---
Write-Host "Deploying dependency DLLs to bin folder..." -ForegroundColor Cyan
$DependencyBins = @(
    $env:ZLIB_BIN, 
    $env:LIBICONV_BIN, 
    $env:ICU_BIN, 
    $env:LZMA_BIN
)

$DestBin = Join-Path $libxml2InstallDir "bin"

foreach ($BinPath in $DependencyBins) {
    if (![string]::IsNullOrWhitespace($BinPath) -and (Test-Path $BinPath)) {
        Write-Host "  -> Syncing DLLs from: $BinPath" -ForegroundColor Gray
        Get-ChildItem -Path $BinPath -Filter "*.dll" | Copy-Item -Destination $DestBin -Force -ErrorAction SilentlyContinue
    } else {
        Write-Warning "Dependency bin path missing or invalid: $BinPath"
    }
}

Write-Host "Successfully built and installed libxml2 to $libxml2InstallDir!" -ForegroundColor Green

# Cleanup temporary build debris
Remove-Item $BuildDirShared -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item $BuildDirStatic -Recurse -Force -ErrorAction SilentlyContinue

# Generate Environment Helper with Clean Paths
$libxml2InstallDir = $libxml2InstallDir.TrimEnd('\')
$libxml2IncludeDir = Join-Path $libxml2InstallDir "include\libxml2"
$libxml2LibDir = Join-Path $libxml2InstallDir "lib"
$libxml2BinPath = Join-Path $libxml2InstallDir "bin"
$libxml2CMakePath = $libxml2InstallDir.Replace('\', '/')

# --- 11. Create Environment Helper ---
Write-Host "Generating environment helper script..." -ForegroundColor Cyan
$libxml2EnvScript = Join-Path $EnvironmentDir "env-libxml2.ps1"
$EnvContent = @'
# LIBXML2 Environment Setup
$libxml2root = "VALUE_ROOT_PATH"
$libxml2include = "VALUE_INCLUDE_PATH"
$libxml2library = "VALUE_LIB_PATH"
$libxml2bin = "VALUE_BIN_PATH"
$libxml2cmakepath = "VALUE_CMAKE_PATH"
$env:LIBXML2_PATH = $libxml2root
$env:LIBXML2_ROOT = $libxml2root
$env:LIBXML2_BIN = $libxml2bin
$env:LIBXML2_INCLUDEDIR = $libxml2include
$env:LIBXML2_LIBRARYDIR = $libxml2library
if ($env:CMAKE_PREFIX_PATH -notlike "*$libxml2cmakepath*") { $env:CMAKE_PREFIX_PATH = $libxml2cmakepath + ";" + $env:CMAKE_PREFIX_PATH }
if ($env:INCLUDE -notlike "*$libxml2include*") { $env:INCLUDE = $libxml2include + ";" + $env:INCLUDE }
if ($env:LIB -notlike "*$libxml2library*") { $env:LIB = $libxml2library + ";" + $env:LIB }
if ($env:PATH -notlike "*$libxml2bin*") { $env:PATH = $libxml2bin + ";" + $env:PATH }
Write-Host "LIBXML2 Environment Loaded." -ForegroundColor Green
Write-Host "LIBXML2_ROOT: $env:LIBXML2_ROOT" -ForegroundColor Gray
'@  -replace "VALUE_ROOT_PATH", $libxml2InstallDir `
    -replace "VALUE_INCLUDE_PATH", $libxml2IncludeDir `
    -replace "VALUE_LIB_PATH", $libxml2LibDir `
    -replace "VALUE_BIN_PATH", $libxml2BinPath `
    -replace "VALUE_CMAKE_PATH", $libxml2CMakePath

$EnvContent | Out-File -FilePath $libxml2EnvScript -Encoding utf8
Write-Host "Created: $libxml2EnvScript" -ForegroundColor Gray

# --- Return to Start ---
Pop-Location
Write-Host "Done! and returned to: $(Get-Location)" -ForegroundColor Gray
