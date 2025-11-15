use anyhow::{anyhow, Context, Result};
use std::path::Path;
use std::process::{Command, Stdio};
use std::io::Write;

use crate::config::Config;

/// Handles age encryption and decryption operations
#[derive(Debug)]
pub struct CryptoManager {
    config: Config,
    identities: Vec<String>,
}

impl CryptoManager {
    pub fn new(config: Config) -> Self {
        Self {
            config,
            identities: Vec::new(),
        }
    }

    /// Add an identity file for decryption
    pub fn add_identity<P: AsRef<Path>>(&mut self, identity_path: P) {
        self.identities.push(identity_path.as_ref().to_string_lossy().to_string());
    }

    /// Get all configured identities, including defaults if none specified
    fn get_identities(&self) -> Vec<String> {
        if self.identities.is_empty() {
            Config::get_default_identities()
                .into_iter()
                .map(|p| p.to_string_lossy().to_string())
                .collect()
        } else {
            self.identities.clone()
        }
    }

    /// Decrypt a file to the specified output path or stdout
    pub fn decrypt<P: AsRef<Path>>(&self, input_file: P, output_path: Option<P>) -> Result<()> {
        let input_file = input_file.as_ref();
        
        if !input_file.exists() {
            return Err(anyhow!("Input file does not exist: {}", input_file.display()));
        }

        let identities = self.get_identities();
        if identities.is_empty() {
            let home = std::env::var("HOME").unwrap_or_default();
            return Err(anyhow!(
                "No identity found to decrypt {}. Try adding an SSH key at {}/.ssh/id_rsa or {}/.ssh/id_ed25519 or using the --identity flag to specify a file.",
                input_file.display(), home, home
            ));
        }

        let mut cmd = Command::new(&self.config.age_bin);
        cmd.arg("--decrypt");

        // Add identity arguments
        for identity in &identities {
            cmd.args(&["--identity", identity]);
        }

        // Add output argument if specified
        if let Some(output) = output_path {
            cmd.args(&["-o", &output.as_ref().to_string_lossy()]);
        } else {
            cmd.args(&["-o", "-"]); // stdout
        }

        cmd.arg("--").arg(input_file);

        let status = cmd.status().context("Failed to run age decrypt")?;

        if !status.success() {
            return Err(anyhow!("Failed to decrypt {}", input_file.display()));
        }

        Ok(())
    }

    /// Encrypt data to a file with the specified recipients
    pub fn encrypt<P: AsRef<Path>>(
        &self,
        input_data: &[u8],
        output_file: P,
        recipients: &[String],
        armor: bool,
    ) -> Result<()> {
        let output_file = output_file.as_ref();

        if recipients.is_empty() {
            return Err(anyhow!("No recipients specified for encryption"));
        }

        let mut cmd = Command::new(&self.config.age_bin);

        if armor {
            cmd.arg("--armor");
        }

        // Add recipients
        for recipient in recipients {
            if !recipient.is_empty() {
                cmd.args(&["--recipient", recipient]);
            }
        }

        cmd.args(&["-o", &output_file.to_string_lossy()]);
        cmd.stdin(Stdio::piped());

        let mut child = cmd.spawn().context("Failed to spawn age encrypt")?;

        if let Some(stdin) = child.stdin.as_mut() {
            stdin.write_all(input_data).context("Failed to write to age stdin")?;
        }

        let status = child.wait().context("Failed to wait for age encrypt")?;

        if !status.success() {
            return Err(anyhow!("Failed to encrypt to {}", output_file.display()));
        }

        Ok(())
    }

    /// Check if two files have the same content (used to detect changes)
    pub fn files_equal<P: AsRef<Path>>(&self, file1: P, file2: P) -> Result<bool> {
        let file1 = file1.as_ref();
        let file2 = file2.as_ref();

        if !file1.exists() || !file2.exists() {
            return Ok(false);
        }

        let status = Command::new(&self.config.diff_bin)
            .args(&["-q", "--"])
            .arg(file1)
            .arg(file2)
            .status()
            .context("Failed to run diff")?;

        Ok(status.success())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::NamedTempFile;
    use std::io::Write as IoWrite;

    fn create_test_config() -> Config {
        Config {
            age_bin: "age".to_string(),
            diff_bin: "diff".to_string(),
            ..Config::default()
        }
    }

    #[test]
    fn test_crypto_manager_creation() {
        let config = create_test_config();
        let manager = CryptoManager::new(config);
        assert_eq!(manager.identities.len(), 0);
    }

    #[test]
    fn test_add_identity() {
        let config = create_test_config();
        let mut manager = CryptoManager::new(config);
        
        manager.add_identity("/path/to/key");
        assert_eq!(manager.identities.len(), 1);
        assert_eq!(manager.identities[0], "/path/to/key");
    }

    #[test]
    fn test_get_identities_with_custom() {
        let config = create_test_config();
        let mut manager = CryptoManager::new(config);
        
        manager.add_identity("/custom/key");
        let identities = manager.get_identities();
        assert_eq!(identities, vec!["/custom/key"]);
    }

    #[test]
    fn test_get_identities_default() {
        let config = create_test_config();
        let manager = CryptoManager::new(config);
        
        // This will return system defaults, which may be empty
        let identities = manager.get_identities();
        assert!(identities.len() <= 2); // At most id_rsa and id_ed25519
    }

    #[test]
    fn test_files_equal_nonexistent() {
        let config = create_test_config();
        let manager = CryptoManager::new(config);
        
        let result = manager.files_equal("/nonexistent1", "/nonexistent2");
        assert!(result.is_ok());
        assert!(!result.unwrap());
    }

    #[test]
    fn test_files_equal_same_content() -> Result<()> {
        let config = create_test_config();
        let manager = CryptoManager::new(config);
        
        let mut file1 = NamedTempFile::new()?;
        let mut file2 = NamedTempFile::new()?;
        
        let content = b"test content";
        file1.write_all(content)?;
        file2.write_all(content)?;
        file1.flush()?;
        file2.flush()?;
        
        let result = manager.files_equal(file1.path(), file2.path())?;
        assert!(result);
        
        Ok(())
    }

    #[test]
    fn test_files_equal_different_content() -> Result<()> {
        let config = create_test_config();
        let manager = CryptoManager::new(config);
        
        let mut file1 = NamedTempFile::new()?;
        let mut file2 = NamedTempFile::new()?;
        
        file1.write_all(b"content1")?;
        file2.write_all(b"content2")?;
        file1.flush()?;
        file2.flush()?;
        
        let result = manager.files_equal(file1.path(), file2.path())?;
        assert!(!result);
        
        Ok(())
    }

    #[test]
    fn test_decrypt_nonexistent_file() {
        let config = create_test_config();
        let manager = CryptoManager::new(config);
        
        let result = manager.decrypt("/nonexistent/file.age", None::<&str>);
        assert!(result.is_err());
        assert!(result.unwrap_err().to_string().contains("does not exist"));
    }

    #[test]
    fn test_encrypt_no_recipients() {
        let config = create_test_config();
        let manager = CryptoManager::new(config);
        
        let temp_file = NamedTempFile::new().unwrap();
        let result = manager.encrypt(b"test", temp_file.path(), &[], false);
        
        assert!(result.is_err());
        assert!(result.unwrap_err().to_string().contains("No recipients"));
    }
}
