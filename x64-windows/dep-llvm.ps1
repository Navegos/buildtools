# SPDX-FileCopyrightText: Copyright (c) 2026 Navegos. @DevelVitorF. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
# project: buildtools
# file: x64-windows/dep-llvm.ps1
# created: 2026-03-02
# lastModified: 2026-04-26

param (
    [Parameter(HelpMessage = "Path for llvm storage", Mandatory = $false)]
    [string]$llvmInstallDir = "$env:LIBRARIES_PATH\llvm",
    
    [Parameter(HelpMessage = "Force a full purge of the local LLVM version before continuing", Mandatory = $false)]
    [switch]$forceCleanup,
    
    [Parameter(HelpMessage = "Add's LLVM Machine Environment Variables. Requires Machine Administrator Rights.", Mandatory = $false)]
    [switch]$withMachineEnvironment
)

# Capture parameters
$LLVMWithMachineEnvironment = $withMachineEnvironment
$LLVMForceCleanup = $forceCleanup

# 1. Bootstrap Environment if variables are missing
if ([string]::IsNullOrWhitespace($env:ENVIRONMENT_PATH) -or -not (Test-Path $env:ENVIRONMENT_PATH) -or [string]::IsNullOrWhitespace($env:BINARIES_PATH) -or -not (Test-Path $env:BINARIES_PATH) -or [string]::IsNullOrWhitespace($env:LIBRARIES_PATH) -or -not (Test-Path $env:LIBRARIES_PATH)) {
    Write-Error "User Environment variables missing. Please run adduserpaths.ps1 -LibrariesDir 'Path\for\Libraries' BinariesDir 'Path\for\Binaries' -EnvironmentDir 'Path\for\Environment'"
    return
}

$EnvironmentDir = "$env:ENVIRONMENT_PATH"

# if Symlink present delete
$GlobalBinDir = "$env:BINARIES_PATH"
# Remove existing symlink we are creating a new one
$llvmtools = @("amdgpu-arch.exe", "bugpoint.exe", "c-index-test.exe", "clang.exe", "clang++.exe", "clang-apply-replacements.exe",
               "clang-change-namespace.exe", "clang-check.exe", "clang-cl.exe", "clang-cpp.exe", "clangd.exe", "clang-doc.exe",
               "clang-extdef-mapping.exe", "clang-format.exe", "clang-include-cleaner.exe", "clang-include-fixer.exe", "clang-installapi.exe",
               "clang-linker-wrapper.exe", "clang-move.exe", "clang-nvlink-wrapper.exe", "clang-offload-bundler.exe", "clang-offload-packager.exe",
               "clang-query.exe", "clang-refactor.exe", "clang-reorder-fields.exe", "clang-repl.exe", "clang-scan-deps.exe", "clang-sycl-linker.exe",
               "clang-tblgen.exe", "clang-tidy.exe", "diagtool.exe", "dsymutil.exe", "find-all-symbols.exe", "ld.lld.exe", "ld64.lld.exe",
               "llc.exe", "lld.exe", "lld-link.exe", "lli.exe", "llvm-addr2line.exe", "llvm-ar.exe", "llvm-as.exe", "llvm-bcanalyzer.exe",
               "llvm-bitcode-strip.exe", "llvm-cas.exe", "llvm-cat.exe", "llvm-cfi-verify.exe", "llvm-cgdata.exe", "llvm-config.exe", "llvm-cov.exe",
               "llvm-c-test.exe", "llvm-ctxprof-util.exe", "llvm-cvtres.exe", "llvm-cxxdump.exe", "llvm-cxxfilt.exe", "llvm-cxxmap.exe",
               "llvm-debuginfo-analyzer.exe", "llvm-debuginfod.exe", "llvm-debuginfod-find.exe", "llvm-diff.exe", "llvm-dis.exe", "llvm-dlltool.exe",
               "llvm-dwarfdump.exe", "llvm-dwarfutil.exe", "llvm-dwp.exe", "llvm-exegesis.exe", "llvm-extract.exe", "llvm-gsymutil.exe", "llvm-ifs.exe",
               "llvm-install-name-tool.exe", "llvm-ir2vec.exe", "llvm-jitlink.exe", "llvm-lib.exe", "llvm-libtool-darwin.exe", "llvm-link.exe",
               "llvm-lipo.exe", "llvm-lto.exe", "llvm-lto2.exe", "llvm-mc.exe", "llvm-mca.exe", "llvm-ml.exe", "llvm-ml64.exe", "llvm-modextract.exe",
               "llvm-mt.exe", "llvm-nm.exe", "llvm-objcopy.exe", "llvm-objdump.exe", "llvm-offload-binary.exe", "llvm-offload-wrapper.exe",
               "llvm-opt-report.exe", "llvm-otool.exe", "llvm-pdbutil.exe", "llvm-profdata.exe", "llvm-profgen.exe", "llvm-ranlib.exe", "llvm-rc.exe",
               "llvm-readelf.exe", "llvm-readobj.exe", "llvm-readtapi.exe", "llvm-reduce.exe", "llvm-remarkutil.exe", "llvm-rtdyld.exe", "llvm-sim.exe",
               "llvm-size.exe", "llvm-split.exe", "llvm-stress.exe", "llvm-strings.exe", "llvm-strip.exe", "llvm-symbolizer.exe", "llvm-tblgen.exe",
               "llvm-tli-checker.exe", "llvm-undname.exe", "llvm-windres.exe", "llvm-xray.exe", "modularize.exe", "nvptx-arch.exe", "offload-arch.exe",
               "opt.exe", "pp-trace.exe", "reduce-chunk-list.exe", "sancov.exe", "sanstats.exe", "verify-uselistorder.exe", "wasm-ld.exe")
foreach ($llvmtool in $llvmtools) {
    $target = Join-Path $GlobalBinDir $llvmtool
    if (Test-Path $target) { Remove-Item $target -Force -ErrorAction SilentlyContinue }
}
$llvmBinPath = Join-Path $llvmInstallDir "bin"
$clangExePath = Join-Path $llvmBinPath "clang.exe"
$versionFile = Join-Path $llvmInstallDir "version.json"
$llvmEnvScript = Join-Path $EnvironmentDir "env-llvm.ps1"
$llvmMachineEnvScript = Join-Path $EnvironmentDir "machine-env-llvm.ps1"

# Version Detection
$repo = "llvm/llvm-project"
try {
    $latestRelease = Invoke-RestMethod -Uri "https://api.github.com/repos/$repo/releases/latest"
    $url = $latestRelease.url
    $tag_name = $latestRelease.tag_name
    $updated_at = $latestRelease.updated_at
    $remoteVersionString = $latestRelease.tag_name.TrimStart('v')
    $refTags = Invoke-RestMethod -Uri "https://api.github.com/repos/$repo/git/ref/tags/$tag_name"
    $tagCommit = $refTags.object.sha
    
    # Clean remote version for comparison (e.g., "1.12.1")
    if ($remoteVersionString -match '(\d+\.\d+\.\d+)') { $remoteVersion = $Matches[1] }
    $remoteVersion = ($remoteVersion -replace '-.*', '')
}
catch {
    Write-Warning "Could not connect to GitHub. Using 0.0.0 for remote."
    $url = "ERR_CONNECTION_TIMED_OUT"
    $tag_name = "0.0.0"
    $updated_at = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssZ")
    $remoteVersion = "0.0.0"
    $tagCommit = "0000000000000000000000000000000000000000"
}

# --- 1. Cleanup Mechanism ---
function Invoke-LlvmVersionPurge {
    param ([string]$InstallPath)
    Write-Host "--- Initiating LLVM Purge ---" -ForegroundColor Cyan

    if ($LLVMWithMachineEnvironment) {
        $llvmCleanMachineEnvScript = Join-Path $env:TEMP "clean-machine-env-llvm.ps1"

        # Generating Clean Machine Environment wich removes the persist registry machine Environment
        $CleanMachineEnvContent = @'
# LLVM Clean Machine Environment Setup

# --- 0. Self-Elevation Logic ---
$IsAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$ScopeColor = "Cyan"

if (-not $IsAdmin) {
    Write-Host "Elevation required to clean llvm system variables. Relaunching as Administrator..." -ForegroundColor Yellow
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

$llvmroot = "VALUE_ROOT_PATH"

$TargetScope = if ($IsAdmin) { "Machine" } else { "User" }
$RegPath = if ($IsAdmin) { "System\CurrentControlSet\Control\Session Manager\Environment" } else { "Environment" }
$RegRoot = if ($IsAdmin) { "LocalMachine" } else { "CurrentUser" }

# 1. Registry Cleanup (TOOLS_PATH)
$RegKey = [Microsoft.Win32.Registry]::$RegRoot.OpenSubKey($RegPath, $true)

# Open the registry key directly to read the RAW (unexpanded) string
$RawPath = $RegKey.GetValue("TOOLS_PATH", "", [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)

# Cleanup: Remove empty strings, any path containing $llvmroot,
$CleanPath = ($RawPath -split ';' | Where-Object { $_ -notlike "*$llvmroot*" }) -join ";"

# Save as ExpandString
$RegKey.SetValue("TOOLS_PATH", $CleanPath, [Microsoft.Win32.RegistryValueKind]::ExpandString)
$env:TOOLS_PATH = $CleanPath

$RegKey.Close()

Write-Host "[REMOVED] ($TargetScope) all '*$llvmroot*' removed from TOOLS_PATH" -ForegroundColor $ScopeColor
'@  -replace "VALUE_ROOT_PATH", $InstallPath

        $CleanMachineEnvContent | Out-File -FilePath $llvmCleanMachineEnvScript -Encoding utf8
        Write-Host "Created: $llvmCleanMachineEnvScript" -ForegroundColor Gray
        
        # --- Interaction: Prompt to remove persistent changes ---
        Write-Host ""
        $choice = Read-Host "Administrator rights required to Clean Machine Environment llvm changes? (y/n)"
        if ($choice -eq 'y' -or $choice -eq 'Y') {
            Write-Host "Executing $llvmCleanMachineEnvScript..." -ForegroundColor Yellow
            try {
                # Start the generated script. It handles its own elevation logic.
                & $llvmCleanMachineEnvScript
            }
            catch {
                Write-Error "Failed to execute the Clean Machine Environment script: $($_.Exception.Message)"
                return
            }
        }
        else {
            Write-Error "Skipped Clean Machine Environment llvm changes."
            return
        }

        # Cleanup
        Remove-Item $llvmCleanMachineEnvScript -Recurse -Force -ErrorAction SilentlyContinue
    }

    # 2. Filesystem Clean (Requires checking for locked files)
    # delete everithing we create don't fail later
    if (Test-Path $llvmEnvScript) {
        Write-Host "  [DELETING] $llvmEnvScript" -ForegroundColor Yellow
        Remove-Item $llvmEnvScript -Recurse -Force -ErrorAction SilentlyContinue
    }
    if (Test-Path $llvmMachineEnvScript) {
        Write-Host "  [DELETING] $llvmMachineEnvScript" -ForegroundColor Yellow
        Remove-Item $llvmMachineEnvScript -Recurse -Force -ErrorAction SilentlyContinue
    }
    if (Test-Path $InstallPath) {
        Write-Host "  [DELETING] $InstallPath" -ForegroundColor Yellow
        Remove-Item $InstallPath -Recurse -Force -ErrorAction SilentlyContinue
    }
    
    # remove local Env variables for current session
    Get-ChildItem Env:\LLVM_PATH* | Remove-Item -ErrorAction SilentlyContinue
    Get-ChildItem Env:\LLVM_ROOT* | Remove-Item -ErrorAction SilentlyContinue
    Get-ChildItem Env:\LLVM_BIN* | Remove-Item -ErrorAction SilentlyContinue

    Write-Host "--- LLVM Purge Complete ---" -ForegroundColor Green
}

$localVersion = "0.0.0"
$rawVersion = "0.0.0"
if (Test-Path $clangExePath) {
    $rawVersion = (& $clangExePath --version | Select-Object -First 1).Trim()
    if ($rawVersion -match 'version\s+(\d+\.\d+\.\d+)') { $localVersion = $Matches[1] }
    $localVersion = ($localVersion -replace '-.*', '')
}

if (Test-Path $versionFile) {
    $localVersion = (Get-Content $versionFile | ConvertFrom-Json).version
}

if ($LLVMForceCleanup) {
    Invoke-LlvmVersionPurge -InstallPath $llvmInstallDir
    # Reset trackers to force a fresh install
    $localVersion = "0.0.0"
}

# --- 2. Install or Skip ---
$vLocal = [version]$localVersion
$vRemote = [version]$remoteVersion

if ($vLocal -ge $vRemote -and $localVersion -ne "0.0.0") {
    Write-Host "[SKIP] Clang $localVersion is already installed and up to date at: $clangExePath" -ForegroundColor Green
    Write-Host "Clang Version: $(& $clangExePath --version | Select-Object -First 1)" -ForegroundColor Gray
    
    # 1. Locate the bin folder and the root folder
    $llvmVersion = $localVersion
    $llvmBinPath = Split-Path -Path $clangExePath -Parent
    $llvmInstallDir = Split-Path -Path $llvmBinPath -Parent
    
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

    # --- 2. Prepare Clean Install Directory ---
    if (Test-Path $llvmInstallDir) {
        Write-Host "[CLEANUP] Removing existing LLVM installation at $llvmInstallDir..." -ForegroundColor Yellow
        # We remove the content and the folder to ensure a completely fresh folder entry
        Remove-Item -Path $llvmInstallDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    # Create a brand new, empty directory
    Write-Host "[INSTALL] Creating fresh directory: $llvmInstallDir" -ForegroundColor Cyan
    New-Item -Path $llvmInstallDir -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null

    try {
        # Specifically target the windows-msvc .tar.xz asset
        $asset = $latestRelease.assets | Where-Object { $_.name -match "clang\+llvm-.*-x86_64-pc-windows-msvc\.tar\.xz$" } | Select-Object -First 1
        
        if (-not $asset) {
            Write-Error "Could not find a .tar.xz asset for Windows x64. Check GitHub release names."
            return
        }

        $archiveFile = Join-Path $env:TEMP $asset.name

        Write-Host "Downloading $($asset.name)..." -ForegroundColor Cyan
        Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $archiveFile

        # 5. Extract and Flatten
        Write-Host "Extracting to temporary location..." -ForegroundColor Cyan
        $tempExtractPath = Join-Path $env:TEMP "llvm_extract_$(Get-Random)"
        New-Item -Path $tempExtractPath -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null

        # Using Windows native tar.exe to handle .tar.xz
        Write-Host "Decompressing LLVM (this may take a minute)..." -ForegroundColor Gray
        tar -xf $archiveFile -C $tempExtractPath

        # Find the root folder inside (usually clang+llvm-version-x86_64-pc-windows-msvc)
        $internalRoot = Get-ChildItem -Path $tempExtractPath -Directory | Select-Object -First 1

        if ($internalRoot) {
            Write-Host "Syncing files to $llvmInstallDir..." -ForegroundColor Gray
    
            # Use Copy-Item with Recurse and Force to ensure all subdirectories (lib, include, share) merge correctly
            Copy-Item -Path "$($internalRoot.FullName)\*" -Destination $llvmInstallDir -Recurse -Force -ErrorAction SilentlyContinue
        }
        
        $llvmVersion = $remoteVersion
        if (Test-Path $clangExePath) {
            $rawVersion = (& $clangExePath --version | Select-Object -First 1).Trim()
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
    
        # Cleanup
        Remove-Item $archiveFile -Force -ErrorAction SilentlyContinue
        Remove-Item $tempExtractPath -Recurse -Force -ErrorAction SilentlyContinue
        
        Write-Host "LLVM Installation Complete!" -ForegroundColor DarkGreen
    }
    catch {
        Write-Error "Failed to install LLVM: $($_.Exception.Message)"
        return # Stop execution on failure
    }
}

# Finalize Environment Helper
if (Test-Path $clangExePath) {
    #  Create Environment Helper
    Write-Host "Generating environment helper script..." -ForegroundColor Cyan

    # Generate Environment Helper with Clean Paths
    $llvmBinPath = $llvmBinPath.TrimEnd('\')
    $llvmInstallDir = $llvmInstallDir.TrimEnd('\')
    $clangExePath = Join-Path $llvmBinPath "clang.exe"

    # Using a literal here-string with -replace to avoid accidental expansion of $env:PATH during creation
    $EnvContent = @'
# LLVM Environment Setup
$llvmroot = "VALUE_ROOT_PATH"
$llvmbin = "VALUE_BIN_PATH"
$clangexe = "VALUE_EXE_PATH"
$llvmversion = "VALUE_VERSION"
$env:LLVM_PATH = $llvmroot
$env:LLVM_ROOT = $llvmroot
$env:LLVM_BIN = $llvmbin
$env:BINARY_CLANG = $clangexe
if ($env:PATH -notlike "*$llvmbin*") { $env:PATH = $llvmbin + ";" + $env:PATH; $env:PATH = ($env:PATH).Replace(";;", ";") }
Write-Host "LLVM Environment Loaded (Version: $llvmversion) (Bin: $llvmbin)" -ForegroundColor Green
Write-Host "LLVM_ROOT: $env:LLVM_ROOT" -ForegroundColor Gray
'@  -replace "VALUE_BIN_PATH", $llvmBinPath `
    -replace "VALUE_EXE_PATH", $clangExePath `
    -replace "VALUE_ROOT_PATH", $llvmInstallDir `
    -replace "VALUE_VERSION", $llvmVersion

    $EnvContent | Out-File -FilePath $llvmEnvScript -Encoding utf8
    Write-Host "Created: $llvmEnvScript" -ForegroundColor Gray

    # Update Current Session
    if (Test-Path $llvmEnvScript) { . $llvmEnvScript } else {
        Write-Error "llvm dep install finished but $llvmEnvScript was not created."
        return
    }
    
    # --- 10. Symlink to Global Binaries ---
    Write-Host "Creating global symlink to: $GlobalBinDir..." -ForegroundColor Cyan

    # Create Symlink
    foreach ($llvmtool in $llvmtools) {
        $source = Join-Path $llvmBinPath $llvmtool
        $target = Join-Path $GlobalBinDir $llvmtool
        
        if (Test-Path $source) {
            if (Test-Path $target) { Remove-Item $target -Force -ErrorAction SilentlyContinue }
            try {
                New-Item -Path $target -ItemType SymbolicLink -Value $source -ErrorAction Stop | Out-Null
                Write-Host "[LINKED] $llvmtool" -ForegroundColor Gray
            }
            catch {
                # Fallback to hardlink if developer mode is off/insufficient permissions
                New-Item -Path $target -ItemType HardLink -Value $source | Out-Null
            }
        }
        else {
            Write-Warning "Optional tool $llvmtool not found in $llvmBinPath distribution; skipping symlink."
        }
    }
    
    Write-Host "[LINKED] LLVM is now globally available via %BINARIES_PATH%" -ForegroundColor Green
    
    Write-Host "Clang Version: $(& $clangExePath --version | Select-Object -First 1)" -ForegroundColor Gray
    
    if ($LLVMWithMachineEnvironment)
    {
        # Generating Machine Environment wich add to the persist registry machine Environment
        $MachineEnvContent = @'
# LLVM Machine Environment Setup

# --- 0. Self-Elevation Logic ---
$IsAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$ScopeColor = "Cyan"

if (-not $IsAdmin) {
    Write-Host "Elevation required to set LLVM system variables. Relaunching as Administrator..." -ForegroundColor Yellow
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

$llvmroot = "VALUE_ROOT_PATH"
$llvmbin = "VALUE_BIN_PATH"
$llvmversion = "VALUE_VERSION"

$TargetScope = if ($IsAdmin) { "Machine" } else { "User" }
$RegPath = if ($IsAdmin) { "System\CurrentControlSet\Control\Session Manager\Environment" } else { "Environment" }
$RegRoot = if ($IsAdmin) { "LocalMachine" } else { "CurrentUser" }

# Open the registry key once
$RegKey = [Microsoft.Win32.Registry]::$RegRoot.OpenSubKey($RegPath, $true)

# Open the registry key directly to read the RAW (unexpanded) string
$CurrentRawPath = $RegKey.GetValue("TOOLS_PATH", "", [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)

# Cleanup: Remove empty strings, any path containing $llvmroot, and the current target (to avoid dups)
$CleanedPathList = $CurrentRawPath -split ';' | Where-Object { 
    -not [string]::IsNullOrWhitespace($_) -and 
    $_ -notlike "*$llvmroot*"
}

$NewRawPath = ($CleanedPathList -join ";").Replace(";;", ";")

$TargetPath = $llvmbin

# Rebuild
$NewRawPath = ($NewRawPath + ";" + $TargetPath + ";").Replace(";;", ";")
Write-Host "[UPDATED] ($TargetScope) '$llvmbin' synced in TOOLS_PATH" -ForegroundColor $ScopeColor

# Save as ExpandString
$RegKey.SetValue("TOOLS_PATH", $NewRawPath, [Microsoft.Win32.RegistryValueKind]::ExpandString)
$env:TOOLS_PATH = $NewRawPath

$RegKey.Close()

$env:LLVM_ROOT = $llvmroot
Write-Host "LLVM Environment Loaded (Version: $llvmversion) (Bin: $llvmbin)" -ForegroundColor Green
Write-Host "LLVM_ROOT: $env:LLVM_ROOT" -ForegroundColor Gray
'@  -replace "VALUE_ROOT_PATH", $llvmInstallDir `
    -replace "VALUE_BIN_PATH", $llvmBinPath `
    -replace "VALUE_VERSION", $llvmVersion

        $MachineEnvContent | Out-File -FilePath $llvmMachineEnvScript -Encoding utf8
        Write-Host "Created: $llvmMachineEnvScript" -ForegroundColor Gray
        
        # --- Interaction: Prompt to apply persistent changes ---
        Write-Host ""
        $choice = Read-Host "Do you want to run the Machine Environment script now to persist LLVM changes to the Registry? (y/n)"
        if ($choice -eq 'y' -or $choice -eq 'Y') {
            Write-Host "Executing $llvmMachineEnvScript..." -ForegroundColor Yellow
            try {
                # Start the generated script. It handles its own elevation logic.
                & $llvmMachineEnvScript
            }
            catch {
                Write-Error "Failed to execute the Machine Environment script: $($_.Exception.Message)"
            }
        }
        else {
            Write-Host "Skipped persistent registry update. You can run it later at: $llvmMachineEnvScript" -ForegroundColor Gray
        }
    }
} else {
    Write-Error "clang.exe was not found in the $llvmBinPath folder."
    return
}
