mod cli;
mod crypto;
mod editor;
mod nix;
use anyhow::{Context, Result};
use std::process::Command;

use crate::cli::Args;
use crate::crypto::AGE_BIN;
use crate::editor::{decrypt_file, edit_file, rekey_all_files};
use crate::nix::NIX_INSTANTIATE;
use clap::Parser;

fn main() -> Result<()> {
    let args = cli::Args::parse_from(std::env::args());
    run(&args)
}

/// Validate that required dependencies are available
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
fn run(args: &Args) -> Result<()> {
    // Note: verbose flag is kept for compatibility with bash version
    // but doesn't affect output in this implementation

    // Validate dependencies first
    if let Err(missing) = validate_dependencies() {
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
        return edit_file(&args.rules, file, &args.editor)
            .with_context(|| format!("Failed to edit {file}"));
    }

    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_run_no_args_shows_help() {
        let args = Args {
            edit: None,
            identity: None,
            rekey: false,
            decrypt: None,
            rules: "./test_secrets.nix".to_string(),
            editor: "vi".to_string(),
            verbose: false,
        };
        let result = run(&args);
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
            editor: "vi".to_string(),
            verbose: true,
        };
        let result = run(&args);
        assert!(result.is_ok());
    }

    #[test]
    fn test_handle_edit_nonexistent_file() {
        let args = Args {
            edit: Some("nonexistent.age".to_string()),
            identity: None,
            rekey: false,
            decrypt: None,
            rules: "./test_secrets.nix".to_string(),
            editor: "vi".to_string(),
            verbose: false,
        };
        let result = run(&args);
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
            editor: "vi".to_string(),
            verbose: false,
        };
        let result = run(&args);
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
            editor: "vi".to_string(),
            verbose: false,
        };
        let result = run(&args);
        assert!(result.is_err());
    }
}
