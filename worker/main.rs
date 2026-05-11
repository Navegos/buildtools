// SPDX-FileCopyrightText: Copyright (c) 2026 Navegos. @DevelVitorF. All Rights Reserved.
// SPDX-License-Identifier: Apache-2.0
// project: buildtools
// file: worker/main.rs
// created: 2026-05-06
// lastModified: 2026-05-06

use std::path::PathBuf;
use std::process::Command;

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    println!("Worker node started.");
    println!("(TODO) Implement Quinn client to connect to Master node...");
    
    // Placeholder to keep the compiler happy until Quinn logic is connected
    // run_script("build-zlib.ps1");

    Ok(())
}

fn run_script(script_name: &str) {
    println!("Executing: {}", script_name);
    let current_dir = std::env::current_dir().unwrap_or_else(|_| PathBuf::from("."));
    let script_path = current_dir.join(script_name);
    
    let output = Command::new("pwsh")
        .args(["-ExecutionPolicy", "Bypass", "-File", &script_path.to_string_lossy()])
        .output();
        
    if let Ok(res) = output {
        println!("Stdout:\n{}", String::from_utf8_lossy(&res.stdout));
        if !res.stderr.is_empty() { eprintln!("Stderr:\n{}", String::from_utf8_lossy(&res.stderr)); }
    } else if let Err(e) = output {
        eprintln!("Failed to execute script: {}", e);
    }
}
