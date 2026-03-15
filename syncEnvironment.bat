rem Copyright 2026 (C) Navegos. DevelVitorF. All Rights Reserved.
rem SPDX-License-Identifier: Apache-2.0
rem file:syncEnvironment.bat

@echo off
setlocal enableextensions enabledelayedexpansion

title Navegos Toolchain Bootstrapper (2026)
echo ============================================
echo   Navegos Toolchain: Environment Setup
echo ============================================

:: 1. Setup Paths
:: Keep SCRIPT_ROOT with backslashes for the 'if exist' check, then use for PowerShell
set "CWD=%~dp0"
set "SCRIPT_ROOT=%CWD%x64-windows"
set "GET_PWSH=%SCRIPT_ROOT%\get-pwsh.ps1"
set "ADD_PATHS=%SCRIPT_ROOT%\adduserpaths.ps1"
set "ARGS_LIST=%*"

:: 2. Always run get-pwsh.ps1
echo [INFO] Checking for PowerShell 7 updates...

if not exist "!GET_PWSH!" (
    echo [ERROR] Script not found: !GET_PWSH!
    pause
    exit /b 1
)

:: This command blocks (waits) until get-pwsh.ps1 is finished.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "!GET_PWSH!"

:: --- REFRESH PATH ---
:: If pwsh was just installed, this session's PATH is stale. 
:: We check the registry directly if 'where' fails.
where pwsh >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo [INFO] Refreshing local PATH to detect new installation...
    for /f "tokens=2*" %%A in ('reg query "HKLM\System\CurrentControlSet\Control\Session Manager\Environment" /v Path') do set "NEWPATH=%%B"
    set "PATH=!NEWPATH!"
)

:: 3. Verify pwsh.exe
where pwsh >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    :: Final fallback: Check the Navegos standard install directory explicitly
    if exist "C:\Program Files\PowerShell\7\pwsh.exe" (
        set "PS_EXE=C:\Program Files\PowerShell\7\pwsh.exe"
    ) else (
        echo [ERROR] pwsh.exe not found in PATH or default directory.
        pause
        exit /b 1
    )
) else (
    set "PS_EXE=pwsh.exe"
)

:: 4. Hand over to modern PowerShell (pwsh)
echo [OK] Launching Navegos Environment Sync via !PS_EXE!...
"!PS_EXE!" -NoProfile -ExecutionPolicy Bypass -File "!ADD_PATHS!" %ARGS_LIST%

:: 5. Finalization
if %ERRORLEVEL% EQU 0 (
    echo.
    echo [COMPLETE] Navegos environment synchronized successfully.
) else (
    echo.
    echo [FAILED] Environment sync returned error code: %ERRORLEVEL%
)
echo ============================================
pause
