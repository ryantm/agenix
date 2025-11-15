use std::env;
use std::path::PathBuf;

/// Configuration for external binary paths and settings
#[derive(Debug, Clone)]
pub struct Config {
    pub age_bin: String,
    pub nix_instantiate: String,
    pub mktemp_bin: String,
    pub diff_bin: String,
    pub rules_path: String,
}

impl Default for Config {
    fn default() -> Self {
        Self {
            age_bin: "age".to_string(),
            nix_instantiate: "nix-instantiate".to_string(),
            mktemp_bin: "mktemp".to_string(),
            diff_bin: "diff".to_string(),
            rules_path: env::var("RULES").unwrap_or_else(|_| "./secrets.nix".to_string()),
        }
    }
}

impl Config {
    pub fn new() -> Self {
        Self::default()
    }

    /// Builder method to set age binary path
    pub fn with_age_bin(mut self, age_bin: &str) -> Self {
        self.age_bin = age_bin.to_string();
        self
    }

    /// Builder method to set nix-instantiate binary path
    pub fn with_nix_instantiate(mut self, nix_instantiate: &str) -> Self {
        self.nix_instantiate = nix_instantiate.to_string();
        self
    }

    /// Builder method to set rules file path
    pub fn with_rules_path(mut self, rules_path: &str) -> Self {
        self.rules_path = rules_path.to_string();
        self
    }

    /// Getter methods for accessing configuration values
    pub fn age_bin(&self) -> &str {
        &self.age_bin
    }

    pub fn nix_instantiate(&self) -> &str {
        &self.nix_instantiate
    }

    pub fn rules_path(&self) -> &str {
        &self.rules_path
    }

    /// Get default SSH identity files from the user's home directory
    pub fn get_default_identities() -> Vec<PathBuf> {
        let mut identities = Vec::new();
        
        if let Ok(home) = env::var("HOME") {
            let id_rsa = PathBuf::from(&home).join(".ssh/id_rsa");
            let id_ed25519 = PathBuf::from(&home).join(".ssh/id_ed25519");
            
            if id_rsa.exists() {
                identities.push(id_rsa);
            }
            if id_ed25519.exists() {
                identities.push(id_ed25519);
            }
        }
        
        identities
    }

    /// Check if all required external binaries are available
    pub fn validate_dependencies(&self) -> Result<(), Vec<String>> {
        let mut missing = Vec::new();
        
        let binaries = [
            (&self.age_bin, "age"),
            (&self.nix_instantiate, "nix-instantiate"),
        ];
        
        for (path, name) in &binaries {
            if std::process::Command::new(path)
                .arg("--version")
                .output()
                .is_err()
            {
                missing.push(format!("{} ({})", name, path));
            }
        }
        
        if missing.is_empty() {
            Ok(())
        } else {
            Err(missing)
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::env;

    #[test]
    fn test_config_default() {
        let config = Config::default();
        assert_eq!(config.age_bin, "age");
        assert_eq!(config.nix_instantiate, "nix-instantiate");
        assert_eq!(config.mktemp_bin, "mktemp");
        assert_eq!(config.diff_bin, "diff");
    }

    #[test]
    fn test_config_with_rules_env() {
        env::set_var("RULES", "/custom/path/secrets.nix");
        let config = Config::default();
        assert_eq!(config.rules_path, "/custom/path/secrets.nix");
        env::remove_var("RULES");
    }

    #[test]
    fn test_get_default_identities() {
        // This test will pass even if no SSH keys exist
        let identities = Config::get_default_identities();
        // Just verify it returns a Vec, content depends on system state
        assert!(identities.len() <= 2); // At most 2 default identity files
    }

    #[test]
    fn test_new() {
        let config = Config::new();
        assert_eq!(config.age_bin, "age");
    }
}
