@echo off
rem SPDX-FileCopyrightText: Copyright (c) 2026 Navegos. @DevelVitorF. All Rights Reserved.
rem SPDX-License-Identifier: Apache-2.0
rem project: buildtools
rem file: sync.bat

set "CWD=%~dp0"
set "RUST_BIN=%CWD%target\release\sync.exe"

if not exist "%RUST_BIN%" (
    echo [INFO] Compiling Rust environment sync helper...
    where cargo >nul 2>&1
    if %ERRORLEVEL% EQU 0 (
        pushd "%CWD%"
        cargo build --release --bin sync
        popd
    )
    if not exist "%RUST_BIN%" (
        echo [ERROR] Failed to compile or locate Rust sync helper at %RUST_BIN%.
        pause
        exit /b 1
    )
)

"%RUST_BIN%" %*
exit /b %ERRORLEVEL%
