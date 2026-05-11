rem SPDX-FileCopyrightText: Copyright (c) 2026 Navegos. @DevelVitorF. All Rights Reserved.
rem SPDX-License-Identifier: Apache-2.0
rem project: buildtools
rem file: sync.bat
rem created: 2026-05-12
rem lastModified: 2026-05-11

@echo off
setlocal

set "CWD=%~dp0"
call "%CWD%shell\syncEnvironment.bat" %*

exit /b %ERRORLEVEL%
