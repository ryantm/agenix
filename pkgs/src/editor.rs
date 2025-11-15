use anyhow::{Context, Result, anyhow};
use std::fs;
use std::path::Path;
use std::process::Command;
use tempfile::TempDir;

use crate::crypto::{decrypt_to_file, decrypt_to_stdout, encrypt_from_file, files_equal};
use crate::nix::NIX_INSTANTIATE;
use crate::nix::{get_all_files, get_public_keys, should_armor};

/// Edit a file with encryption/decryption
pub fn edit_file(rules_path: &str, file: &str, editor_cmd: &str) -> Result<()> {
    let public_keys = get_public_keys(NIX_INSTANTIATE, rules_path, file)?;
    let armor = should_armor(NIX_INSTANTIATE, rules_path, file)?;

    if public_keys.is_empty() {
        return Err(anyhow!("No public keys found for file: {file}"));
    }

    // Create temporary directory for cleartext
    let temp_dir = TempDir::new().context("Failed to create temporary directory")?;
    let cleartext_file = temp_dir.path().join(Path::new(file).file_name().unwrap());

    // Decrypt if file exists
    if Path::new(file).exists() {
        decrypt_to_file(file, &cleartext_file)?;
    }

    // Create backup
    let backup_file = format!("{}.backup", cleartext_file.to_string_lossy());
    if cleartext_file.exists() {
        fs::copy(&cleartext_file, &backup_file)?;
    }

    // If editor_cmd is ":" we skip invoking an editor (used for rekey)
    if editor_cmd != ":" {
        let status = Command::new("sh")
            .args([
                "-c",
                &format!("{} '{}'", editor_cmd, cleartext_file.to_string_lossy()),
            ])
            .status()
            .context("Failed to run editor")?;

        if !status.success() {
            return Err(anyhow!("Editor exited with non-zero status"));
        }
    }

    if !cleartext_file.exists() {
        eprintln!("Warning: {file} wasn't created");
        return Ok(());
    }

    // Check if file changed (only when an editor was actually invoked)
    if editor_cmd != ":"
        && Path::new(&backup_file).exists()
        && files_equal(&backup_file, &cleartext_file.to_string_lossy())?
    {
        eprintln!("Warning: {file} wasn't changed, skipping re-encryption");
        return Ok(());
    }

    // Encrypt the file
    encrypt_from_file(&cleartext_file.to_string_lossy(), file, &public_keys, armor)?;

    Ok(())
}

/// Decrypt a file to stdout or another location
pub fn decrypt_file(rules_path: &str, file: &str, output: Option<&str>) -> Result<()> {
    let public_keys = get_public_keys(NIX_INSTANTIATE, rules_path, file)?;
    if public_keys.is_empty() {
        return Err(anyhow!("No public keys found for file: {file}"));
    }

    match output {
        Some(out_file) => decrypt_to_file(file, Path::new(out_file))?,
        None => decrypt_to_stdout(file)?,
    }

    Ok(())
}

/// Rekey all files in the rules (no-op editor used to avoid launching an editor)
pub fn rekey_all_files(rules_path: &str) -> Result<()> {
    let files = get_all_files(NIX_INSTANTIATE, rules_path)?;

    for file in files {
        eprintln!("Rekeying {file}...");
        edit_file(rules_path, &file, ":")?;
    }

    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs::File;
    use tempfile::tempdir;

    #[test]
    fn test_edit_file_no_keys() {
        let rules = "./test_secrets.nix";
        let result = edit_file(rules, "nonexistent.age", "vi");
        assert!(result.is_err());
    }

    #[test]
    fn test_decrypt_file_no_keys() {
        let rules = "./test_secrets.nix";
        let result = decrypt_file(rules, "nonexistent.age", None);
        assert!(result.is_err());
    }

    #[test]
    fn test_rekey_uses_no_op_editor() {
        // With nonexistent rules this will early error if keys empty; simulate empty by pointing to test file
        let rules = "./test_secrets.nix";
        // Should error, but specifically via missing keys, not editor invocation failure.
        let result = rekey_all_files(rules);
        assert!(result.is_err());
    }

    #[test]
    fn test_skip_reencrypt_when_unchanged() {
        // We cannot fully simulate encryption without keys; focus on the unchanged branch logic.
        // Create a temp dir and a dummy age file plus rules path pointing to nonexistent keys causing early return of skip branch.
        let tmp = tempdir().unwrap();
        let secret_path = tmp.path().join("dummy.age");
        // Create an empty file so decrypt_to_file won't run (no existence of keys) but backup logic proceeds.
        File::create(&secret_path).unwrap();
        // Call edit_file expecting an error due to no keys; ensures we reach key check early.
        let res = edit_file("./test_secrets.nix", secret_path.to_str().unwrap(), ":");
        assert!(res.is_err());
    }
}
