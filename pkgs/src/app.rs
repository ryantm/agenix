use anyhow::{Context, Result};
use std::env;

use crate::cli::Args;
use crate::config::{validate_dependencies, Config};
use crate::editor::{decrypt_file, edit_file, rekey_all_files};

/// Main application that orchestrates all the components
pub struct AgenixApp {
    config: Config,
}

impl AgenixApp {
    pub fn new() -> Self {
        Self {
            config: Config::default(),
        }
    }

    pub fn with_config(config: Config) -> Self {
        Self { config }
    }

    /// Run the application with the given command-line arguments
    pub fn run(&self, args: &Args) -> Result<()> {
        // Set verbose mode if requested
        if args.verbose {
            env::set_var("RUST_LOG", "debug");
        }

        // Validate dependencies first
        if let Err(missing) = validate_dependencies(&self.config) {
            eprintln!("Missing required dependencies:");
            for dep in missing {
                eprintln!("  - {dep}");
            }
            return Err(anyhow::anyhow!("Required dependencies are missing"));
        }

        // Handle different commands
        if args.rekey {
            return rekey_all_files(&self.config).context("Failed to rekey files");
        }

        if let Some(file) = &args.decrypt {
            return decrypt_file(&self.config, file, None)
                .with_context(|| format!("Failed to decrypt {file}"));
        }

        if let Some(file) = &args.edit {
            return edit_file(&self.config, file).with_context(|| format!("Failed to edit {file}"));
        }

        Ok(())
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
        assert_eq!(app.config.age_bin, "age");
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
        let result = app.run(&args);
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

        let result = app.run(&args);
        // Should succeed (just shows help with verbose flag set)
        assert!(result.is_ok());

        // Check if RUST_LOG was set
        assert_eq!(env::var("RUST_LOG").unwrap_or_default(), "debug");
        env::remove_var("RUST_LOG"); // Clean up
    }

    #[test]
    fn test_handle_edit_nonexistent_file() {
        let config = create_test_config();
        let app = AgenixApp::with_config(config.clone());

        let args = Args {
            edit: Some("nonexistent.age".to_string()),
            identity: None,
            rekey: false,
            decrypt: None,
            verbose: false,
        };

        let result = app.run(&args);
        // Should fail because rules file doesn't exist
        assert!(result.is_err());
    }

    #[test]
    fn test_handle_decrypt_nonexistent_file() {
        let config = create_test_config();
        let app = AgenixApp::with_config(config);

        let args = Args {
            edit: None,
            identity: None,
            rekey: false,
            decrypt: Some("nonexistent.age".to_string()),
            verbose: false,
        };

        let result = app.run(&args);
        // Should fail because rules file doesn't exist
        assert!(result.is_err());
    }

    #[test]
    fn test_handle_rekey_nonexistent_rules() {
        let config = create_test_config();
        let app = AgenixApp::with_config(config);

        let args = Args {
            edit: None,
            identity: None,
            rekey: true,
            decrypt: None,
            verbose: false,
        };

        let result = app.run(&args);
        // Should fail because rules file doesn't exist
        assert!(result.is_err());
    }
}
