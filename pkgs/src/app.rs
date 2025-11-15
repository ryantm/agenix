use anyhow::{Context, Result};
use std::env;
use std::process::Command;

use crate::cli::Args;
use crate::crypto::AGE_BIN;
use crate::editor::{decrypt_file, edit_file, rekey_all_files};
use crate::nix::NIX_INSTANTIATE;

/// Main application that orchestrates all the components
pub struct AgenixApp {}

impl AgenixApp {
    pub fn new() -> Self {
        Self {}
    }

    fn validate_dependencies() -> Result<(), Vec<String>> {
        let mut missing = Vec::new();

        let binaries = [(AGE_BIN, "age"), (NIX_INSTANTIATE, "nix-instantiate")];

        for (path, name) in &binaries {
            if Command::new(path).arg("--version").output().is_err() {
                missing.push(format!("{name} ({path})"));
            }
        }

        if missing.is_empty() {
            Ok(())
        } else {
            Err(missing)
        }
    }

    /// Run the application with the given command-line arguments
    pub fn run(args: &Args) -> Result<()> {
        // Set verbose mode if requested
        if args.verbose {
            unsafe {
                env::set_var("RUST_LOG", "debug");
            }
        }

        // Validate dependencies first
        if let Err(missing) = Self::validate_dependencies() {
            eprintln!("Missing required dependencies:");
            for dep in missing {
                eprintln!("  - {dep}");
            }
            return Err(anyhow::anyhow!("Required dependencies are missing"));
        }

        // Handle different commands
        if args.rekey {
            return rekey_all_files(&args.rules).context("Failed to rekey files");
        }

        if let Some(file) = &args.decrypt {
            return decrypt_file(&args.rules, file, None)
                .with_context(|| format!("Failed to decrypt {file}"));
        }

        if let Some(file) = &args.edit {
            return edit_file(&args.rules, file).with_context(|| format!("Failed to edit {file}"));
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

    #[test]
    fn test_app_creation() {
        let _app = AgenixApp::new();
        // No config anymore; just ensure creation succeeds
    }

    #[test]
    fn test_app_default() {
        let _app = AgenixApp::default();
        // creation ok
    }

    #[test]
    fn test_config_access() {
        let _app = AgenixApp::new();
        // no config access
    }

    #[test]
    fn test_run_no_args_shows_help() {
        let args = Args {
            edit: None,
            identity: None,
            rekey: false,
            decrypt: None,
            rules: "./test_secrets.nix".to_string(),
            verbose: false,
        };

        // This should succeed and show help
        let result = AgenixApp::run(&args);
        assert!(result.is_ok());
    }

    #[test]
    fn test_run_with_verbose() {
        let args = Args {
            edit: None,
            identity: None,
            rekey: false,
            decrypt: None,
            rules: "./test_secrets.nix".to_string(),
            verbose: true,
        };

        let result = AgenixApp::run(&args);
        // Should succeed (just shows help with verbose flag set)
        assert!(result.is_ok());

        // Check if RUST_LOG was set
        assert_eq!(env::var("RUST_LOG").unwrap_or_default(), "debug");
        unsafe {
            env::remove_var("RUST_LOG");
        } // Clean up
    }

    #[test]
    fn test_handle_edit_nonexistent_file() {
        let args = Args {
            edit: Some("nonexistent.age".to_string()),
            identity: None,
            rekey: false,
            decrypt: None,
            rules: "./test_secrets.nix".to_string(),
            verbose: false,
        };

        let result = AgenixApp::run(&args);
        // Should fail because rules file doesn't exist
        assert!(result.is_err());
    }

    #[test]
    fn test_handle_decrypt_nonexistent_file() {
        let args = Args {
            edit: None,
            identity: None,
            rekey: false,
            decrypt: Some("nonexistent.age".to_string()),
            rules: "./test_secrets.nix".to_string(),
            verbose: false,
        };

        let result = AgenixApp::run(&args);
        // Should fail because rules file doesn't exist
        assert!(result.is_err());
    }

    #[test]
    fn test_handle_rekey_nonexistent_rules() {
        let args = Args {
            edit: None,
            identity: None,
            rekey: true,
            decrypt: None,
            rules: "./test_secrets.nix".to_string(),
            verbose: false,
        };

        let result = AgenixApp::run(&args);
        // Should fail because rules file doesn't exist
        assert!(result.is_err());
    }
}
