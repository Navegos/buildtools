#!/usr/bin/env bash
# SPDX-FileCopyrightText: Copyright (c) 2026 Navegos. @DevelVitorF. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
# project: buildtools
# file: sync.sh
# created: 2026-05-12
# lastModified: 2026-05-11

CWD="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

bash "$CWD/shell/syncEnvironment.sh" "$@"
exit $?
