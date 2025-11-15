//! Agenix - A tool for managing age-encrypted secrets in Nix environments
//!
//! This library provides functionality to edit, decrypt, and rekey age-encrypted files
//! using Nix expressions to manage recipient public keys.

pub mod app;
pub mod cli;
pub mod config;
pub mod crypto;
pub mod editor;
pub mod nix;

#[cfg(test)]
pub mod test_utils;

pub use app::AgenixApp;
pub use cli::Args;
pub use config::Config;

use anyhow::Result;
use clap::Parser;

/// Main entry point for the library
pub fn run() -> Result<()> {
    let args = cli::Args::try_parse_from(std::env::args())?;
    let config = config::Config::default();
    let app = app::AgenixApp::with_config(config);
    app.run(args)
}
