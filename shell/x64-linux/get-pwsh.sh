#!/usr/bin/env bash
# SPDX-FileCopyrightText: Copyright (c) 2026 Navegos. @DevelVitorF. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
# project: buildtools
# file: x64-linux/get-pwsh.sh
# created: 2026-05-11
# lastModified: 2026-05-11

# Default installation directory
POWERSHELL_INSTALL_DIR="/opt/microsoft/powershell/7"

# Parse arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        -powershellInstallDir|--powershellInstallDir) POWERSHELL_INSTALL_DIR="$2"; shift ;;
        *) echo "Unknown parameter passed: $1"; exit 1 ;;
    esac
    shift
done

# --- 0. Self-Elevation Logic ---
if [ "$(id -u)" -ne 0 ]; then
    echo -e "\033[33m--- Elevation required. Relaunching with sudo... ---\033[0m"
    exec sudo bash "$0" -powershellInstallDir "$POWERSHELL_INSTALL_DIR"
fi

# --- 1. Helper Function: Error Reporter ---
show_error() {
    local message="$1"
    local exit_code="${2:-1}"
    echo -e "\n\033[31m[FATAL ERROR] $message\033[0m" >&2
    echo -e "\033[90mExit Code: $exit_code\033[0m" >&2
    exit "$exit_code"
}

echo -e "\033[36m--- PowerShell Management ---\033[0m"

# --- 2. Detect and Install/Update ---
install_or_update_pwsh() {
    echo -e "\033[36m--- PowerShell 7 Provisioning ---\033[0m"
    
    echo -e "\033[33mFetching latest release from GitHub API...\033[0m"
    
    # Dynamically find the x64 tar.gz URL for the latest stable release
    DOWNLOAD_URL=$(curl -sL "https://api.github.com/repos/PowerShell/PowerShell/releases/latest" | grep "browser_download_url" | grep "linux-x64.tar.gz" | cut -d '"' -f 4 | head -n 1)
    
    if [ -z "$DOWNLOAD_URL" ]; then
        show_error "Could not find a valid x64 tar.gz in the latest GitHub release."
    fi
    
    TEMP_TAR="/tmp/pwsh_install.tar.gz"
    echo -e "\033[90mDownloading: $(basename "$DOWNLOAD_URL")...\033[0m"
    curl -sL "$DOWNLOAD_URL" -o "$TEMP_TAR" || show_error "Download failed."
    
    echo -e "\033[90mInstalling tar.gz to $POWERSHELL_INSTALL_DIR...\033[0m"
    mkdir -p "$POWERSHELL_INSTALL_DIR" || show_error "Failed to create directory $POWERSHELL_INSTALL_DIR"
    tar -xzf "$TEMP_TAR" -C "$POWERSHELL_INSTALL_DIR" || show_error "Extraction failed."
    
    # Ensure the binary is executable
    chmod +x "$POWERSHELL_INSTALL_DIR/pwsh"
    
    rm -f "$TEMP_TAR"
    
    # Create a symbolic link in /usr/bin to expose pwsh to standard PATH
    echo -e "\033[90mCreating symlink in /usr/bin/pwsh...\033[0m"
    ln -sf "$POWERSHELL_INSTALL_DIR/pwsh" /usr/bin/pwsh
    
    # Add to PATH in .bashrc
    echo -e "\033[90mAdding $POWERSHELL_INSTALL_DIR to PATH in .bashrc...\033[0m"
    local target_bashrc="${HOME}/.bashrc"
    if [ -n "$SUDO_USER" ]; then
        target_bashrc=$(eval echo "~$SUDO_USER/.bashrc")
    fi

    UPDATE_FUNC=$(cat << 'EOF'
update_bashrc_block() {
    local bashrc="$1"
    local new_line="$2"
    local match_string="$3"
    
    if [ ! -f "$bashrc" ]; then
        echo -e "# BUILDTOOLS_BEGIN\n$new_line\n# BUILDTOOLS_END\n" > "$bashrc"
        return
    fi
    
    grep -v "$match_string" "$bashrc" > "${bashrc}.tmp" || true
    if grep -q "# BUILDTOOLS_BEGIN" "${bashrc}.tmp"; then
        awk -v line="$new_line" '
        /# BUILDTOOLS_BEGIN/ { in_block=1; print; next }
        /# BUILDTOOLS_END/ { if(in_block) { print line }; print; in_block=0; next }
        { print }
        ' "${bashrc}.tmp" > "${bashrc}"
    else
        cat "${bashrc}.tmp" > "${bashrc}"
        echo -e "\n# BUILDTOOLS_BEGIN\n$new_line\n# BUILDTOOLS_END\n" >> "${bashrc}"
    fi
    rm -f "${bashrc}.tmp"
}
EOF
)

    if [ -n "$SUDO_USER" ]; then
        sudo -u "$SUDO_USER" bash -c "$UPDATE_FUNC; update_bashrc_block \"$target_bashrc\" 'export PATH=\"\$PATH:$POWERSHELL_INSTALL_DIR\"' \"$POWERSHELL_INSTALL_DIR\""
    else
        eval "$UPDATE_FUNC"
        update_bashrc_block "$target_bashrc" "export PATH=\"\$PATH:$POWERSHELL_INSTALL_DIR\"" "$POWERSHELL_INSTALL_DIR"
    fi

    echo -e "\033[32m[SUCCESS] PowerShell 7 provisioned at $POWERSHELL_INSTALL_DIR\033[0m"
}

# --- 3. Run ---
install_or_update_pwsh

# --- 4. Final Verification ---
CURRENT_VER=$(pwsh -v 2>/dev/null) || CURRENT_VER="Not Found"
echo -e "\033[37mCurrent Session PowerShell Version: $CURRENT_VER\033[0m"

echo -e "\033[32m--- Setup Complete ---\033[0m"
