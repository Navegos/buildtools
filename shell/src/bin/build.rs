// SPDX-FileCopyrightText: Copyright (c) 2026 Navegos. @DevelVitorF. All Rights Reserved.
// SPDX-License-Identifier: Apache-2.0
// project: buildtools
// file: shell/src/bin/build.rs
// created: 2026-06-04
// lastModified: 2026-06-04

use std::fs;
use std::path::{Path, PathBuf};

fn main() {
    let args: Vec<String> = std::env::args().collect();
    
    // Usage check (requires at least 1 actual argument)
    if args.len() < 2 {
        let cmd_name = get_command_name();
        eprintln!("\x1b[31mUsage: {} <action> [target] [arguments...]\x1b[0m", cmd_name);
        println!("\x1b[90mExample: {} get pwsh -powershellInstallDir 'C:\\pwsh'\x1b[0m", cmd_name);
        println!("\x1b[90mExample: {} build zstd -forceCleanup\x1b[0m", cmd_name);
        std::process::exit(1);
    }

    let shell_dir = match find_shell_dir() {
        Some(dir) => dir,
        None => {
            eprintln!("\x1b[31m[ERROR] Could not locate 'shell' directory.\x1b[0m");
            std::process::exit(1);
        }
    };

    let real_args_count = args.len() - 1;
    let mut target_script: Option<PathBuf> = None;
    let mut script_index = 0;

    // Iterate backwards to find the longest matching script name
    for i in (1..=real_args_count).rev() {
        let test_name_base = args[1..=i].join("-");
        let mut test_name = test_name_base.clone();
        if !test_name.to_lowercase().ends_with(".ps1") {
            test_name.push_str(".ps1");
        }

        // 1. Fast check in root shell directory
        let direct_path = shell_dir.join(&test_name);
        if direct_path.exists() && direct_path.is_file() {
            target_script = Some(direct_path);
            script_index = i;
            break;
        }

        // 2. Recursive check if not in root
        if let Some(found) = find_file_recursive(&shell_dir, &test_name) {
            target_script = Some(found);
            script_index = i;
            break;
        }
    }

    if let Some(script_path) = target_script {
        println!("\x1b[36m[BUILD] Delegating to {}...\x1b[0m", script_path.to_string_lossy());
        
        let ps_exe = find_pwsh_path();
        let remaining_args = &args[1 + script_index..];
        
        let mut cmd = std::process::Command::new(&ps_exe);
        cmd.arg("-NoProfile")
           .arg("-ExecutionPolicy")
           .arg("Bypass")
           .arg("-File")
           .arg(&script_path);
           
        for arg in remaining_args {
            cmd.arg(arg);
        }

        let status = cmd.status();
        match status {
            Ok(s) => {
                std::process::exit(s.code().unwrap_or(0));
            }
            Err(e) => {
                eprintln!("\x1b[31m[ERROR] Failed to execute PowerShell ({}): {}\x1b[0m", ps_exe, e);
                std::process::exit(1);
            }
        }
    } else {
        let attempted_name = args[1..].join("-") + ".ps1";
        eprintln!("\x1b[31m[ERROR] Target script not found matching args. Attempted: {}\x1b[0m", attempted_name);
        std::process::exit(1);
    }
}

fn get_command_name() -> String {
    if let Ok(caller) = std::env::var("BUILDTOOLS_CALLER") {
        if caller.to_lowercase().contains("env") {
            return ".\\env.ps1".to_string();
        }
    }
    ".\\build.ps1".to_string()
}

fn find_shell_dir() -> Option<PathBuf> {
    // 1. Check current directory
    if let Ok(cwd) = std::env::current_dir() {
        let path = cwd.join("shell");
        if path.exists() && path.is_dir() {
            return Some(path);
        }
    }
    // 2. Check executable directory and its parents
    if let Ok(exe_path) = std::env::current_exe() {
        if let Some(exe_dir) = exe_path.parent() {
            let path = exe_dir.join("shell");
            if path.exists() && path.is_dir() {
                return Some(path);
            }
            // Check if executable is in target/release or target/debug (2 levels up)
            if let Some(parent) = exe_dir.parent() {
                if let Some(parent2) = parent.parent() {
                    let path = parent2.join("shell");
                    if path.exists() && path.is_dir() {
                        return Some(path);
                    }
                }
            }
        }
    }
    None
}

fn find_file_recursive(dir: &Path, filename: &str) -> Option<PathBuf> {
    if let Ok(entries) = fs::read_dir(dir) {
        let mut subdirs = Vec::new();
        for entry in entries.flatten() {
            let path = entry.path();
            if path.is_file() {
                if let Some(name) = path.file_name().and_then(|n| n.to_str()) {
                    if name.eq_ignore_ascii_case(filename) {
                        return Some(path);
                    }
                }
            } else if path.is_dir() {
                subdirs.push(path);
            }
        }
        for subdir in subdirs {
            if let Some(found) = find_file_recursive(&subdir, filename) {
                return Some(found);
            }
        }
    }
    None
}

fn find_in_path(binary_name: &str) -> Option<PathBuf> {
    if let Ok(path_env) = std::env::var("PATH") {
        for dir in std::env::split_paths(&path_env) {
            let bin_path = dir.join(binary_name);
            if bin_path.exists() && bin_path.is_file() {
                return Some(bin_path);
            }
            #[cfg(target_os = "windows")]
            {
                let bin_path_exe = dir.join(format!("{}.exe", binary_name));
                if bin_path_exe.exists() && bin_path_exe.is_file() {
                    return Some(bin_path_exe);
                }
            }
        }
    }
    None
}

#[cfg(target_os = "windows")]
fn get_registry_path() -> Option<String> {
    let output = std::process::Command::new("reg")
        .args(&[
            "query", 
            "HKLM\\System\\CurrentControlSet\\Control\\Session Manager\\Environment", 
            "/v", 
            "Path"
        ])
        .output()
        .ok()?;
        
    if output.status.success() {
        let stdout = String::from_utf8_lossy(&output.stdout);
        for line in stdout.lines() {
            if line.contains("REG_EXPAND_SZ") {
                if let Some(pos) = line.find("REG_EXPAND_SZ") {
                    return Some(line[pos + "REG_EXPAND_SZ".len()..].trim().to_string());
                }
            } else if line.contains("REG_SZ") {
                if let Some(pos) = line.find("REG_SZ") {
                    return Some(line[pos + "REG_SZ".len()..].trim().to_string());
                }
            }
        }
    }
    None
}

#[cfg(target_os = "windows")]
fn expand_windows_env_vars(s: &str) -> String {
    let mut result = s.to_string();
    let mut start = 0;
    while let Some(pos) = result[start..].find('%') {
        let abs_pos = start + pos;
        if let Some(end_pos) = result[abs_pos + 1..].find('%') {
            let var_name = &result[abs_pos + 1..abs_pos + 1 + end_pos];
            if let Ok(var_val) = std::env::var(var_name) {
                result.replace_range(abs_pos..=abs_pos + 1 + end_pos, &var_val);
                start = abs_pos + var_val.len();
            } else {
                start = abs_pos + 1;
            }
        } else {
            break;
        }
    }
    result
}

fn find_pwsh_path() -> String {
    // 1. Try pwsh in PATH
    if let Some(path) = find_in_path("pwsh") {
        return path.to_string_lossy().to_string();
    }
    
    // 2. Try refreshing path from registry on Windows
    #[cfg(target_os = "windows")]
    {
        if let Some(new_path) = get_registry_path() {
            let expanded = expand_windows_env_vars(&new_path);
            std::env::set_var("PATH", &expanded);
            if let Some(path) = find_in_path("pwsh") {
                return path.to_string_lossy().to_string();
            }
        }
    }
    
    // 3. Try standard installation path
    #[cfg(target_os = "windows")]
    {
        let std_path = PathBuf::from("C:\\Program Files\\PowerShell\\7\\pwsh.exe");
        if std_path.exists() {
            return std_path.to_string_lossy().to_string();
        }
        "powershell.exe".to_string() // Fallback to Windows PowerShell
    }
    
    #[cfg(not(target_os = "windows"))]
    {
        let standard_paths = [
            "/opt/microsoft/powershell/7/pwsh",
            "/usr/bin/pwsh",
            "/usr/local/bin/pwsh",
        ];
        for path_str in &standard_paths {
            let path = PathBuf::from(path_str);
            if path.exists() {
                return path.to_string_lossy().to_string();
            }
        }
        "pwsh".to_string() // Final fallback
    }
}
