use anyhow::{Context, Result};
use std::fs;
use std::path::Path;
use std::process::Command;

use crate::config::Config;

/// Decrypt a file to another file
pub fn decrypt_to_file<P: AsRef<Path>>(
    config: &Config,
    input_file: &str,
    output_file: P,
) -> Result<()> {
    let mut args = vec!["--decrypt".to_string()];

    // Add default identities
    let identities = get_default_identities();
    for identity in identities {
        args.extend_from_slice(&["--identity".to_string(), identity]);
    }

    args.extend_from_slice(&[
        "-o".to_string(),
        output_file.as_ref().to_string_lossy().to_string(),
        "--".to_string(),
        input_file.to_string(),
    ]);

    let status = Command::new(&config.age_bin)
        .args(&args)
        .status()
        .context("Failed to run age decrypt")?;

    if !status.success() {
        return Err(anyhow::anyhow!("Failed to decrypt {}", input_file));
    }

    Ok(())
}

/// Decrypt a file to stdout
pub fn decrypt_to_stdout(config: &Config, input_file: &str) -> Result<()> {
    let mut args = vec!["--decrypt".to_string()];

    // Add default identities
    let identities = get_default_identities();
    for identity in identities {
        args.extend_from_slice(&["--identity".to_string(), identity]);
    }

    args.extend_from_slice(&["--".to_string(), input_file.to_string()]);

    let status = Command::new(&config.age_bin)
        .args(&args)
        .status()
        .context("Failed to run age decrypt")?;

    if !status.success() {
        return Err(anyhow::anyhow!("Failed to decrypt {}", input_file));
    }

    Ok(())
}

/// Encrypt from a file to another file
pub fn encrypt_from_file(
    input_file: &str,
    output_file: &str,
    recipients: &[String],
    armor: bool,
    config: &Config,
) -> Result<()> {
    let mut args = Vec::new();

    if armor {
        args.push("--armor".to_string());
    }

    for recipient in recipients {
        args.extend_from_slice(&["--recipient".to_string(), recipient.clone()]);
    }

    args.extend_from_slice(&[
        "-o".to_string(),
        output_file.to_string(),
        "--".to_string(),
        input_file.to_string(),
    ]);

    let status = Command::new(&config.age_bin)
        .args(&args)
        .status()
        .context("Failed to run age encrypt")?;

    if !status.success() {
        return Err(anyhow::anyhow!("Failed to encrypt to {}", output_file));
    }

    Ok(())
}

/// Get default SSH identity files
pub fn get_default_identities() -> Vec<String> {
    let mut identities = Vec::new();

    if let Ok(home) = std::env::var("HOME") {
        let id_rsa = format!("{}/.ssh/id_rsa", home);
        let id_ed25519 = format!("{}/.ssh/id_ed25519", home);

        if Path::new(&id_rsa).exists() {
            identities.push(id_rsa);
        }
        if Path::new(&id_ed25519).exists() {
            identities.push(id_ed25519);
        }
    }

    identities
}

/// Check if two files have the same content
pub fn files_equal(file1: &str, file2: &str) -> Result<bool> {
    if !Path::new(file1).exists() || !Path::new(file2).exists() {
        return Ok(false);
    }

    let content1 = fs::read(file1).context("Failed to read first file")?;
    let content2 = fs::read(file2).context("Failed to read second file")?;
    Ok(content1 == content2)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_get_default_identities() {
        let identities = get_default_identities();
        // Should return 0-2 identities depending on system
        assert!(identities.len() <= 2);
    }

    #[test]
    fn test_files_equal_nonexistent() {
        let result = files_equal("nonexistent1", "nonexistent2");
        assert!(result.is_ok());
        assert!(!result.unwrap());
    }

    #[test]
    fn test_files_equal_same_content() -> Result<()> {
        use std::io::Write;
        use tempfile::NamedTempFile;

        let mut file1 = NamedTempFile::new()?;
        let mut file2 = NamedTempFile::new()?;

        writeln!(file1, "test content")?;
        writeln!(file2, "test content")?;

        let result = files_equal(
            file1.path().to_str().unwrap(),
            file2.path().to_str().unwrap(),
        )?;
        assert!(result);

        Ok(())
    }

    #[test]
    fn test_files_equal_different_content() -> Result<()> {
        use std::io::Write;
        use tempfile::NamedTempFile;

        let mut file1 = NamedTempFile::new()?;
        let mut file2 = NamedTempFile::new()?;

        writeln!(file1, "content 1")?;
        writeln!(file2, "content 2")?;

        let result = files_equal(
            file1.path().to_str().unwrap(),
            file2.path().to_str().unwrap(),
        )?;
        assert!(!result);

        Ok(())
    }
}
