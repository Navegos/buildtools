#!/usr/bin/env bash
# SPDX-FileCopyrightText: Copyright (c) 2026 Navegos. @DevelVitorF. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
# project: buildtools
# file: sync.sh

CWD="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUST_BIN="$CWD/target/release/sync"

if [ ! -f "$RUST_BIN" ]; then
    echo "[INFO] Compiling Rust environment sync helper..."
    if command -v cargo >/dev/null 2>&1; then
        pushd "$CWD" >/dev/null
        cargo build --release --bin sync
        popd >/dev/null
    fi
    if [ ! -f "$RUST_BIN" ]; then
        echo "[ERROR] Failed to compile or locate Rust sync helper at $RUST_BIN."
        exit 1
    fi
fi

"$RUST_BIN" "$@"
exit $?
