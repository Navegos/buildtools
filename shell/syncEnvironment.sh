#!/usr/bin/env bash
# SPDX-FileCopyrightText: Copyright (c) 2026 Navegos. @DevelVitorF. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
# project: buildtools
# file: syncEnvironment.sh
# created: 2026-05-09
# lastModified: 2026-05-11

# Set Terminal Title
echo -ne "\033]0;Navegos Toolchain Bootstrapper (2026)\007"

echo "============================================"
echo "  Navegos Toolchain: Environment Setup"
echo "============================================"

PROCESSOR_ARCHITECTURE=$(uname -m)
if [ "$PROCESSOR_ARCHITECTURE" = "aarch64" ] || [ "$PROCESSOR_ARCHITECTURE" = "arm64" ]; then
    ARCH="arm64"
elif [ "$PROCESSOR_ARCHITECTURE" = "x86_64" ] || [ "$PROCESSOR_ARCHITECTURE" = "amd64" ]; then
    ARCH="x64"
else
    echo "[ERROR] Unsupported architecture: $PROCESSOR_ARCHITECTURE"
    exit 1
fi

# 1. Setup Paths
CWD="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_ROOT="$CWD/$ARCH-linux"

# In Linux, a shell bootstrapper is preferred since powershell isn't native
GET_PWSH="$SCRIPT_ROOT/get-pwsh.sh"
GET_PWSH_PS1="$SCRIPT_ROOT/get-pwsh.ps1"
ADD_PATHS="$SCRIPT_ROOT/add-user-paths.ps1"

# 2. Always run get-pwsh script
echo "[INFO] Checking for PowerShell 7 updates..."

if [ -f "$GET_PWSH" ]; then
    bash "$GET_PWSH"
elif [ -f "$GET_PWSH_PS1" ]; then
    # Fallback to PowerShell if the .sh bootstrapper is missing but pwsh is available
    if command -v pwsh >/dev/null 2>&1; then
        pwsh -NoProfile -ExecutionPolicy Bypass -File "$GET_PWSH_PS1"
    else
        echo "[ERROR] pwsh is not installed, and $GET_PWSH was not found to bootstrap it."
        exit 1
    fi
else
    echo "[ERROR] Script not found: $GET_PWSH"
    exit 1
fi

# --- REFRESH PATH ---
# Hash refresh to discover newly installed binaries in the current session
hash -r

# 3. Verify pwsh
if ! command -v pwsh >/dev/null 2>&1; then
    # Final fallback: Check common installation directories explicitly
    if [ -x "/opt/microsoft/powershell/7/pwsh" ]; then
        PS_EXE="/opt/microsoft/powershell/7/pwsh"
    elif [ -x "/usr/bin/pwsh" ]; then
        PS_EXE="/usr/bin/pwsh"
    elif [ -x "/usr/local/bin/pwsh" ]; then
        PS_EXE="/usr/local/bin/pwsh"
    else
        echo "[ERROR] pwsh not found in PATH or default directories."
        exit 1
    fi
else
    PS_EXE="$(command -v pwsh)"
fi

# 4. Hand over to modern PowerShell (pwsh)
echo "[OK] Launching Navegos Environment Sync via $PS_EXE..."
"$PS_EXE" -NoProfile -ExecutionPolicy Bypass -File "$ADD_PATHS" "$@"
SYNC_EXIT_CODE=$?

# 5. Finalization
if [ $SYNC_EXIT_CODE -eq 0 ]; then
    echo ""
    echo "[COMPLETE] Navegos environment synchronized successfully."
else
    echo ""
    echo "[FAILED] Environment sync returned error code: $SYNC_EXIT_CODE"
fi
echo "============================================"
