use anyhow::{Context, Result, anyhow};
use isatty::stdin_isatty;
use std::env;
use std::fs;
use std::path::Path;
use std::process::Command;
use tempfile::TempDir;

use crate::config::Config;
use crate::crypto::{decrypt_to_file, decrypt_to_stdout, encrypt_from_file, files_equal};
use crate::nix::{get_all_files, get_public_keys, should_armor};

/// Get the editor command to use
pub fn get_editor_command() -> String {
    // If EDITOR is explicitly set, prefer that
    if let Ok(editor) = env::var("EDITOR") {
        return editor;
    }

    if stdin_isatty() {
        // Default editor when attached to a terminal
        "vi".to_string()
    } else {
        // When not attached to a tty, read from stdin
        "cp -- /dev/stdin".to_string()
    }
}

/// Edit a file with encryption/decryption
pub fn edit_file(config: &Config, file: &str) -> Result<()> {
    let public_keys = get_public_keys(config, file)?;
    let armor = should_armor(config, file)?;

    if public_keys.is_empty() {
        return Err(anyhow!("No public keys found for file: {file}"));
    }

    // Create temporary directory for cleartext
    let temp_dir = TempDir::new().context("Failed to create temporary directory")?;
    let cleartext_file = temp_dir.path().join(Path::new(file).file_name().unwrap());

    // Decrypt if file exists
    if Path::new(file).exists() {
        decrypt_to_file(config, file, &cleartext_file)?;
    }

    // Create backup
    let backup_file = format!("{}.backup", cleartext_file.to_string_lossy());
    if cleartext_file.exists() {
        fs::copy(&cleartext_file, &backup_file)?;
    }

    // Edit the file
    let editor = get_editor_command();
    let status = Command::new("sh")
        .args([
            "-c",
            &format!("{} '{}'", editor, cleartext_file.to_string_lossy()),
        ])
        .status()
        .context("Failed to run editor")?;

    if !status.success() {
        return Err(anyhow!("Editor exited with non-zero status"));
    }

    if !cleartext_file.exists() {
        eprintln!("Warning: {file} wasn't created");
        return Ok(());
    }

    // Check if file changed
    if Path::new(&backup_file).exists()
        && editor != ":"
        && files_equal(&backup_file, &cleartext_file.to_string_lossy())?
    {
        eprintln!("Warning: {file} wasn't changed, skipping re-encryption");
        return Ok(());
    }

    // Encrypt the file
    encrypt_from_file(
        &cleartext_file.to_string_lossy(),
        file,
        &public_keys,
        armor,
        config,
    )?;

    Ok(())
}

/// Decrypt a file to stdout or another location
pub fn decrypt_file(config: &Config, file: &str, output: Option<&str>) -> Result<()> {
    let public_keys = get_public_keys(config, file)?;
    if public_keys.is_empty() {
        return Err(anyhow!("No public keys found for file: {file}"));
    }

    match output {
        Some(out_file) => decrypt_to_file(config, file, Path::new(out_file))?,
        None => decrypt_to_stdout(config, file)?,
    }

    Ok(())
}

/// Rekey all files in the rules
pub fn rekey_all_files(config: &Config) -> Result<()> {
    let files = get_all_files(config)?;

    for file in files {
        eprintln!("Rekeying {file}...");

        // Set EDITOR to : (no-op) for rekeying
        let old_editor = env::var("EDITOR").ok();
        unsafe {
            env::set_var("EDITOR", ":");
        }

        let result = edit_file(config, &file);

        // Restore original EDITOR
        match old_editor {
            Some(editor) => unsafe { env::set_var("EDITOR", editor) },
            None => unsafe { env::remove_var("EDITOR") },
        }

        result?;
    }

    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::{Mutex, OnceLock};

    // Global lock to serialize tests that modify environment variables.
    static ENV_LOCK: OnceLock<Mutex<()>> = OnceLock::new();

    #[test]
    fn test_get_editor_command_with_env() {
        // Serialize env changes
        let _guard = ENV_LOCK.get_or_init(|| Mutex::new(())).lock().unwrap();

        let original = env::var("EDITOR").ok();
        unsafe {
            env::set_var("EDITOR", "nano");
        }

        if stdin_isatty() {
            let editor = get_editor_command();
            assert_eq!(editor, "nano");
        }

        // Restore original value
        match original {
            Some(val) => unsafe { env::set_var("EDITOR", val) },
            None => unsafe { env::remove_var("EDITOR") },
        }
    }

    #[test]
    fn test_get_editor_command_default() {
        let _guard = ENV_LOCK.get_or_init(|| Mutex::new(())).lock().unwrap();

        let original = env::var("EDITOR").ok();
        unsafe {
            env::remove_var("EDITOR");
        }

        if stdin_isatty() {
            let editor = get_editor_command();
            assert_eq!(editor, "vi");
        }

        // Restore original value
        match original {
            Some(val) => unsafe { env::set_var("EDITOR", val) },
            None => unsafe { env::remove_var("EDITOR") },
        }
    }

    #[test]
    fn test_edit_file_no_keys() {
        let config = Config::default();
        let result = edit_file(&config, "nonexistent.age");
        assert!(result.is_err());
    }

    #[test]
    fn test_decrypt_file_no_keys() {
        let config = Config::default();
        let result = decrypt_file(&config, "nonexistent.age", None);
        assert!(result.is_err());
    }

    #[test]
    fn test_get_editor_command_prefers_env() {
        let _guard = ENV_LOCK.get_or_init(|| Mutex::new(())).lock().unwrap();

        // Ensure EDITOR is preferred regardless of tty state
        let original = env::var("EDITOR").ok();
        unsafe {
            env::set_var("EDITOR", "emacs");
        }

        let editor = get_editor_command();
        assert_eq!(editor, "emacs");

        // Restore original value
        match original {
            Some(val) => unsafe { env::set_var("EDITOR", val) },
            None => unsafe { env::remove_var("EDITOR") },
        }
    }
}
