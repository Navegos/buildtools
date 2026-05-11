// SPDX-FileCopyrightText: Copyright (c) 2026 Navegos. @DevelVitorF. All Rights Reserved.
// SPDX-License-Identifier: Apache-2.0
// project: buildtools
// file: controller/build.rs
// created: 2026-05-06
// lastModified: 2026-05-06

fn main() {
    slint_build::compile("ui/main.slint").unwrap();
}
