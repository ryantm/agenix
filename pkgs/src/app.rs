use anyhow::{Context, Result};
use std::env;

use crate::cli::Args;
use crate::config::Config;
use crate::crypto::CryptoManager;
use crate::editor::EditorManager;

/// Main application that orchestrates all the components
pub struct AgenixApp {
    config: Config,
}

impl AgenixApp {
    pub fn new() -> Self {
        Self {
            config: Config::new(),
        }
    }

    pub fn with_config(config: Config) -> Self {
        Self { config }
    }

    /// Run the application with the given command-line arguments
    pub fn run(&self, args: Args) -> Result<()> {
        // Set verbose mode if requested
        if args.verbose {
            env::set_var("RUST_LOG", "debug");
            // In a real application, you might initialize a logger here
        }

        // Validate dependencies first
        if let Err(missing) = self.config.validate_dependencies() {
            eprintln!("Missing required dependencies:");
            for dep in missing {
                eprintln!("  - {}", dep);
            }
            return Err(anyhow::anyhow!("Required dependencies are missing"));
        }

        // Create crypto manager
        let mut crypto_manager = CryptoManager::new(self.config.clone());

        // Add identity if specified
        if let Some(identity) = &args.identity {
            crypto_manager.add_identity(identity);
        }

        // Create editor manager
        let editor_manager = EditorManager::new(self.config.clone());

        // Handle different commands
        if args.rekey {
            return self.handle_rekey(&editor_manager, &mut crypto_manager);
        }

        if let Some(file) = &args.decrypt {
            return self.handle_decrypt(file, &editor_manager, &crypto_manager);
        }

        if let Some(file) = &args.edit {
            return self.handle_edit(file, &editor_manager, &mut crypto_manager);
        }

        // If no command specified, show help
        Args::show_help();
        Ok(())
    }

    fn handle_rekey(&self, editor_manager: &EditorManager, crypto_manager: &mut CryptoManager) -> Result<()> {
        editor_manager.rekey_all_files(crypto_manager)
            .context("Failed to rekey files")
    }

    fn handle_decrypt(&self, file: &str, editor_manager: &EditorManager, crypto_manager: &CryptoManager) -> Result<()> {
        editor_manager.decrypt_file(file, crypto_manager)
            .with_context(|| format!("Failed to decrypt {}", file))
    }

    fn handle_edit(&self, file: &str, editor_manager: &EditorManager, crypto_manager: &mut CryptoManager) -> Result<()> {
        editor_manager.edit_file(file, crypto_manager)
            .with_context(|| format!("Failed to edit {}", file))
    }

    /// Get the configuration
    pub fn config(&self) -> &Config {
        &self.config
    }
}

impl Default for AgenixApp {
    fn default() -> Self {
        Self::new()
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
    fn test_app_creation() {
        let app = AgenixApp::new();
        assert_eq!(app.config.age_bin, "age");
    }

    #[test]
    fn test_app_with_config() {
        let config = create_test_config();
        let app = AgenixApp::with_config(config);
        assert_eq!(app.config.rules_path, "./test_secrets.nix");
    }

    #[test]
    fn test_app_default() {
        let app = AgenixApp::default();
        assert_eq!(app.config.age_bin, "age");
    }

    #[test]
    fn test_config_access() {
        let app = AgenixApp::new();
        let config = app.config();
        assert_eq!(config.age_bin, "age");
    }

    #[test]
    fn test_run_no_args_shows_help() {
        let app = AgenixApp::new();
        let args = Args {
            edit: None,
            identity: None,
            rekey: false,
            decrypt: None,
            verbose: false,
        };
        
        // This should succeed and show help
        let result = app.run(args);
        assert!(result.is_ok());
    }

    #[test]
    fn test_run_with_verbose() {
        let app = AgenixApp::new();
        let args = Args {
            edit: None,
            identity: None,
            rekey: false,
            decrypt: None,
            verbose: true,
        };
        
        let result = app.run(args);
        // Should succeed (just shows help with verbose flag set)
        assert!(result.is_ok());
        
        // Check if RUST_LOG was set
        assert_eq!(env::var("RUST_LOG").unwrap_or_default(), "debug");
        env::remove_var("RUST_LOG"); // Clean up
    }

    #[test]
    fn test_run_with_identity() {
        let app = AgenixApp::new();
        let args = Args {
            edit: None,
            identity: Some("/path/to/key".to_string()),
            rekey: false,
            decrypt: None,
            verbose: false,
        };
        
        let result = app.run(args);
        // Should succeed (just shows help)
        assert!(result.is_ok());
    }

    #[test]
    fn test_handle_edit_nonexistent_file() {
        let config = create_test_config();
        let app = AgenixApp::with_config(config.clone());
        let editor_manager = EditorManager::new(config.clone());
        let mut crypto_manager = CryptoManager::new(config);
        
        let result = app.handle_edit("nonexistent.age", &editor_manager, &mut crypto_manager);
        // Should fail because rules file doesn't exist
        assert!(result.is_err());
    }

    #[test]
    fn test_handle_decrypt_nonexistent_file() {
        let config = create_test_config();
        let app = AgenixApp::with_config(config.clone());
        let editor_manager = EditorManager::new(config.clone());
        let crypto_manager = CryptoManager::new(config);
        
        let result = app.handle_decrypt("nonexistent.age", &editor_manager, &crypto_manager);
        // Should fail because rules file doesn't exist
        assert!(result.is_err());
    }

    #[test]
    fn test_handle_rekey_nonexistent_rules() {
        let config = create_test_config();
        let app = AgenixApp::with_config(config.clone());
        let editor_manager = EditorManager::new(config.clone());
        let mut crypto_manager = CryptoManager::new(config);
        
        let result = app.handle_rekey(&editor_manager, &mut crypto_manager);
        // Should fail because rules file doesn't exist
        assert!(result.is_err());
    }
}
