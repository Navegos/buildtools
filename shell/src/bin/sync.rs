// SPDX-FileCopyrightText: Copyright (c) 2026 Navegos. @DevelVitorF. All Rights Reserved.
// SPDX-License-Identifier: Apache-2.0
// project: buildtools
// file: shell/src/bin/sync.rs
// created: 2026-06-04
// lastModified: 2026-06-04

use std::io::{Read, Write};
use std::path::PathBuf;

fn main() {
    // Set Terminal Title
    print!("\x1b]0;Navegos Toolchain Bootstrapper (2026)\x07");
    let _ = std::io::stdout().flush();

    println!("============================================");
    println!("  Navegos Toolchain: Environment Setup");
    println!("============================================");

    // Detect Architecture
    let arch = get_architecture();

    let shell_dir = match find_shell_dir() {
        Some(dir) => dir,
        None => {
            eprintln!("\x1b[31m[ERROR] Could not locate 'shell' directory.\x1b[0m");
            finalize(1);
            return;
        }
    };

    // Setup Paths
    #[cfg(target_os = "windows")]
    let script_root = {
        let _ = arch;
        shell_dir.join("x64-windows") // hardcoded to x64-windows for windows
    };
    
    #[cfg(not(target_os = "windows"))]
    let script_root = shell_dir.join(format!("{}-linux", arch));

    let get_pwsh_ps1 = script_root.join("get-pwsh.ps1");
    let add_paths = script_root.join("add-user-paths.ps1");

    #[cfg(target_os = "windows")]
    let get_pwsh = get_pwsh_ps1.clone();
    #[cfg(not(target_os = "windows"))]
    let get_pwsh = script_root.join("get-pwsh.sh");

    // 2. Always run get-pwsh script
    println!("[INFO] Checking for PowerShell 7 updates...");

    if !get_pwsh.exists() && !(cfg!(not(target_os = "windows")) && get_pwsh_ps1.exists()) {
        eprintln!("\x1b[31m[ERROR] Script not found: {}\x1b[0m", get_pwsh.to_string_lossy());
        finalize(1);
        return;
    }

    let mut get_pwsh_success = false;

    #[cfg(target_os = "windows")]
    {
        let status = std::process::Command::new("powershell.exe")
            .arg("-NoProfile")
            .arg("-ExecutionPolicy")
            .arg("Bypass")
            .arg("-File")
            .arg(&get_pwsh)
            .status();
        if let Ok(s) = status {
            get_pwsh_success = s.success();
        }
    }

    #[cfg(not(target_os = "windows"))]
    {
        if get_pwsh.exists() {
            let status = std::process::Command::new("bash")
                .arg(&get_pwsh)
                .status();
            if let Ok(s) = status {
                get_pwsh_success = s.success();
            }
        } else if get_pwsh_ps1.exists() {
            if let Some(pwsh_bin) = find_in_path("pwsh") {
                let status = std::process::Command::new(pwsh_bin)
                    .arg("-NoProfile")
                    .arg("-ExecutionPolicy")
                    .arg("Bypass")
                    .arg("-File")
                    .arg(&get_pwsh_ps1)
                    .status();
                if let Ok(s) = status {
                    get_pwsh_success = s.success();
                }
            } else {
                eprintln!("\x1b[31m[ERROR] pwsh is not installed, and {} was not found to bootstrap it.\x1b[0m", get_pwsh.to_string_lossy());
                finalize(1);
                return;
            }
        }
    }

    if !get_pwsh_success {
        eprintln!("\x1b[31m[ERROR] Checking for PowerShell 7 updates failed.\x1b[0m");
        finalize(1);
        return;
    }

    // Refresh PATH (Windows only)
    #[cfg(target_os = "windows")]
    {
        if find_in_path("pwsh").is_none() {
            println!("[INFO] Refreshing local PATH to detect new installation...");
            if let Some(new_path) = get_registry_path() {
                let expanded = expand_windows_env_vars(&new_path);
                std::env::set_var("PATH", &expanded);
            }
        }
    }

    // Verify pwsh executable
    let mut ps_exe = None;
    if let Some(path) = find_in_path("pwsh") {
        ps_exe = Some(path);
    } else {
        #[cfg(target_os = "windows")]
        {
            let std_path = PathBuf::from("C:\\Program Files\\PowerShell\\7\\pwsh.exe");
            if std_path.exists() {
                ps_exe = Some(std_path);
            }
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
                    ps_exe = Some(path);
                    break;
                }
            }
        }
    }

    let ps_exe_path = match ps_exe {
        Some(p) => p,
        None => {
            eprintln!("\x1b[31m[ERROR] pwsh not found in PATH or default directories.\x1b[0m");
            finalize(1);
            return;
        }
    };

    // Hand over to modern PowerShell (pwsh)
    println!("\x1b[32m[OK] Launching Navegos Environment Sync via {}...\x1b[0m", ps_exe_path.to_string_lossy());

    let args: Vec<String> = std::env::args().skip(1).collect();
    let mut cmd = std::process::Command::new(&ps_exe_path);
    cmd.arg("-NoProfile")
       .arg("-ExecutionPolicy")
       .arg("Bypass")
       .arg("-File")
       .arg(&add_paths);
       
    #[cfg(target_os = "windows")]
    {
        cmd.env("HOST_IS_WINDOWS", "True");
        cmd.env("HOST_ARCH", "x64");
        cmd.env("HOST_PLATFORM", "windows");
        cmd.env("HOST_TRIPLET", "x64-windows");
    }
    #[cfg(not(target_os = "windows"))]
    {
        cmd.env("HOST_IS_LINUX", "True");
        cmd.env("HOST_ARCH", arch);
        cmd.env("HOST_PLATFORM", "linux");
        cmd.env("HOST_TRIPLET", format!("{}-linux", arch));
    }

    for arg in &args {
        cmd.arg(arg);
    }

    let status = cmd.status();
    let mut exit_code = 1;
    match status {
        Ok(s) => {
            if s.success() {
                println!("\n[COMPLETE] Navegos environment synchronized successfully.");
                exit_code = 0;
            } else {
                let code = s.code().unwrap_or(1);
                println!("\n\x1b[31m[FAILED] Environment sync returned error code: {}\x1b[0m", code);
                exit_code = code;
            }
        }
        Err(e) => {
            eprintln!("\n\x1b[31m[ERROR] Failed to run sync script: {}\x1b[0m", e);
        }
    }

    println!("============================================");
    finalize(exit_code);
}

fn get_architecture() -> &'static str {
    #[cfg(target_os = "windows")]
    {
        let val = std::env::var("PROCESSOR_ARCHITECTURE").unwrap_or_default();
        if val.eq_ignore_ascii_case("ARM64") {
            "arm64"
        } else if val.eq_ignore_ascii_case("AMD64") {
            "x64"
        } else {
            eprintln!("\x1b[31m[ERROR] Unsupported architecture: {}\x1b[0m", val);
            finalize(1);
            std::process::exit(1);
        }
    }

    #[cfg(not(target_os = "windows"))]
    {
        match std::env::consts::ARCH {
            "x86_64" => "x64",
            "aarch64" => "arm64",
            other => {
                eprintln!("\x1b[31m[ERROR] Unsupported architecture: {}\x1b[0m", other);
                std::process::exit(1);
            }
        }
    }
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
            // Check 2 levels up
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

fn finalize(exit_code: i32) {
    #[cfg(target_os = "windows")]
    {
        println!("Press any key to continue . . .");
        let mut buffer = [0; 1];
        let _ = std::io::stdin().read(&mut buffer);
    }
    std::process::exit(exit_code);
}
