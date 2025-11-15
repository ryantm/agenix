use anyhow::{anyhow, Context, Result};
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
    if !stdin_isatty() {
        "cp -- /dev/stdin".to_string()
    } else {
        env::var("EDITOR").unwrap_or_else(|_| "vi".to_string())
    }
}

/// Edit a file with encryption/decryption
pub fn edit_file(config: &Config, file: &str) -> Result<()> {
    let public_keys = get_public_keys(config, file)?;
    let armor = should_armor(config, file)?;

    if public_keys.is_empty() {
        return Err(anyhow!("No public keys found for file: {}", file));
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
        eprintln!("Warning: {} wasn't created", file);
        return Ok(());
    }

    // Check if file changed
    if Path::new(&backup_file).exists()
        && editor != ":"
        && files_equal(&backup_file, &cleartext_file.to_string_lossy())?
    {
        eprintln!("Warning: {} wasn't changed, skipping re-encryption", file);
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
        return Err(anyhow!("No public keys found for file: {}", file));
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
        eprintln!("Rekeying {}...", file);

        // Set EDITOR to : (no-op) for rekeying
        let old_editor = env::var("EDITOR").ok();
        env::set_var("EDITOR", ":");

        let result = edit_file(config, &file);

        // Restore original EDITOR
        match old_editor {
            Some(editor) => env::set_var("EDITOR", editor),
            None => env::remove_var("EDITOR"),
        }

        result?;
    }

    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_get_editor_command_with_env() {
        let original = env::var("EDITOR").ok();
        env::set_var("EDITOR", "nano");

        if stdin_isatty() {
            let editor = get_editor_command();
            assert_eq!(editor, "nano");
        }

        // Restore original value
        match original {
            Some(val) => env::set_var("EDITOR", val),
            None => env::remove_var("EDITOR"),
        }
    }

    #[test]
    fn test_get_editor_command_default() {
        env::remove_var("EDITOR");

        if stdin_isatty() {
            let editor = get_editor_command();
            assert_eq!(editor, "vi");
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
}
