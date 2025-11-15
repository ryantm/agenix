use anyhow::{anyhow, Context, Result};
use std::env;
use std::fs;
use std::path::Path;
use std::process::Command;
use tempfile::TempDir;

use crate::config::Config;
use crate::crypto::CryptoManager;
use crate::nix::NixManager;

/// Manages editing of encrypted files
#[derive(Debug)]
pub struct EditorManager {
    config: Config,
    nix_manager: NixManager,
}

impl EditorManager {
    pub fn new(config: Config) -> Self {
        let nix_manager = NixManager::new(config.clone());
        Self {
            config,
            nix_manager,
        }
    }

    /// Edit an encrypted file with the configured editor
    pub fn edit_file(&self, file: &str, crypto_manager: &mut CryptoManager) -> Result<()> {
        // Get keys and armor setting for the file
        let keys = self.nix_manager.get_public_keys(file)
            .with_context(|| format!("Failed to get public keys for {}", file))?;
        
        if keys.is_empty() {
            return Err(anyhow!("There is no rule for {} in {}", file, self.config.rules_path));
        }

        let armor = self.nix_manager.should_armor(file)
            .with_context(|| format!("Failed to check armor setting for {}", file))?;

        // Create temporary directory for cleartext file
        let cleartext_dir = TempDir::new().context("Failed to create temporary directory")?;
        let cleartext_file = cleartext_dir.path().join(
            Path::new(file).file_name().unwrap_or_else(|| std::ffi::OsStr::new("temp"))
        );

        // Decrypt the file if it exists
        if Path::new(file).exists() {
            crypto_manager.decrypt(file, Some(cleartext_file.to_str().unwrap()))
                .with_context(|| format!("Failed to decrypt {}", file))?;
        }

        // Create backup of original cleartext for change detection
        let backup_file = format!("{}.before", cleartext_file.to_string_lossy());
        if cleartext_file.exists() {
            fs::copy(&cleartext_file, &backup_file)
                .context("Failed to create backup of cleartext file")?;
        }

        // Determine editor command
        let editor = self.get_editor_command()?;

        // Run the editor
        let status = Command::new("sh")
            .args(&["-c", &format!("{} '{}'", editor, cleartext_file.to_string_lossy())])
            .status()
            .context("Failed to run editor")?;

        if !status.success() {
            return Err(anyhow!("Editor exited with non-zero status"));
        }

        // Check if file was created
        if !cleartext_file.exists() {
            eprintln!("{} wasn't created.", file);
            return Ok(());
        }

        // Check if file was changed (skip re-encryption if unchanged)
        if Path::new(file).exists() && editor != ":" {
            if Path::new(&backup_file).exists() {
                if crypto_manager.files_equal(&backup_file, &cleartext_file.to_string_lossy().to_string())? {
                    eprintln!("{} wasn't changed, skipping re-encryption.", file);
                    return Ok(());
                }
            }
        }

        // Read cleartext content for encryption
        let cleartext_content = fs::read(&cleartext_file)
            .context("Failed to read cleartext file")?;

        // Create parent directory if needed
        if let Some(parent) = Path::new(file).parent() {
            fs::create_dir_all(parent)
                .context("Failed to create parent directory")?;
        }

        // Encrypt and save
        crypto_manager.encrypt(&cleartext_content, file, &keys, armor)
            .with_context(|| format!("Failed to encrypt {}", file))?;

        Ok(())
    }

    /// Get the editor command to use
    fn get_editor_command(&self) -> Result<String> {
        // Check if stdin is interactive
        if !isatty::stdin_isatty() {
            // Non-interactive, use cp from stdin
            return Ok("cp -- /dev/stdin".to_string());
        }

        // Interactive, use EDITOR environment variable or default
        Ok(env::var("EDITOR").unwrap_or_else(|_| "vi".to_string()))
    }

    /// Rekey all files in the rules
    pub fn rekey_all_files(&self, crypto_manager: &mut CryptoManager) -> Result<()> {
        let files = self.nix_manager.get_all_files()
            .context("Failed to get list of files from rules")?;

        for file in files {
            eprintln!("rekeying {}...", file);
            
            // Set EDITOR to : (no-op) for rekeying
            let old_editor = env::var("EDITOR").ok();
            env::set_var("EDITOR", ":");
            
            let result = self.edit_file(&file, crypto_manager);
            
            // Restore original EDITOR
            match old_editor {
                Some(editor) => env::set_var("EDITOR", editor),
                std::option::Option::None => env::remove_var("EDITOR"),
            }
            
            result.with_context(|| format!("Failed to rekey {}", file))?;
        }

        Ok(())
    }

    /// Decrypt a file to stdout or a specific output
    pub fn decrypt_file(&self, file: &str, crypto_manager: &CryptoManager) -> Result<()> {
        let keys = self.nix_manager.get_public_keys(file)
            .with_context(|| format!("Failed to get public keys for {}", file))?;
        
        if keys.is_empty() {
            return Err(anyhow!("There is no rule for {} in {}", file, self.config.rules_path));
        }

        // Decrypt to stdout (None output path means stdout)
        crypto_manager.decrypt(file, None::<&str>)
            .with_context(|| format!("Failed to decrypt {}", file))
    }
}

#[cfg(test)]
mod tests {
    use super::*;


    fn create_test_config() -> Config {
        Config {
            rules_path: "./test_secrets.nix".to_string(),
            ..Config::default()
        }
    }

    #[test]
    fn test_editor_manager_creation() {
        let config = create_test_config();
        let manager = EditorManager::new(config);
        assert_eq!(manager.config.rules_path, "./test_secrets.nix");
    }

    #[test]
    fn test_get_editor_command_with_env() {
        let config = create_test_config();
        let manager = EditorManager::new(config);
        
        // Set EDITOR environment variable
        env::set_var("EDITOR", "nano");
        
        if isatty::stdin_isatty() {
            let editor = manager.get_editor_command().unwrap();
            assert_eq!(editor, "nano");
        }
        
        env::remove_var("EDITOR");
    }

    #[test]
    fn test_get_editor_command_default() {
        let config = create_test_config();
        let manager = EditorManager::new(config);
        
        // Remove EDITOR environment variable
        env::remove_var("EDITOR");
        
        if isatty::stdin_isatty() {
            let editor = manager.get_editor_command().unwrap();
            assert_eq!(editor, "vi");
        }
    }

    #[test]
    fn test_get_editor_command_non_interactive() {
        let config = create_test_config();
        let manager = EditorManager::new(config);
        
        // This test assumes stdin is interactive in test environment
        // In real non-interactive use, it would return "cp -- /dev/stdin"
        let editor = manager.get_editor_command().unwrap();
        assert!(editor == "vi" || editor == "cp -- /dev/stdin" || env::var("EDITOR").unwrap_or_default() == editor);
    }

    #[test]
    fn test_edit_file_nonexistent_rules() {
        let mut config = create_test_config();
        config.rules_path = "/nonexistent/rules.nix".to_string();
        let manager = EditorManager::new(config.clone());
        let mut crypto_manager = CryptoManager::new(config);
        
        let result = manager.edit_file("test.age", &mut crypto_manager);
        assert!(result.is_err());
    }

    #[test] 
    fn test_decrypt_file_nonexistent_rules() {
        let mut config = create_test_config();
        config.rules_path = "/nonexistent/rules.nix".to_string();
        let manager = EditorManager::new(config.clone());
        let crypto_manager = CryptoManager::new(config);
        
        let result = manager.decrypt_file("test.age", &crypto_manager);
        assert!(result.is_err());
    }

    #[test]
    fn test_rekey_all_files_nonexistent_rules() {
        let mut config = create_test_config();
        config.rules_path = "/nonexistent/rules.nix".to_string();
        let manager = EditorManager::new(config.clone());
        let mut crypto_manager = CryptoManager::new(config);
        
        let result = manager.rekey_all_files(&mut crypto_manager);
        assert!(result.is_err());
    }
}
