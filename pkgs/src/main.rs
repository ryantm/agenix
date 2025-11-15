mod app;
mod cli;
mod config;
mod crypto;
mod editor;
mod nix;

use anyhow::Result;
use clap::Parser;

fn main() -> Result<()> {
    let args = cli::Args::parse_from(std::env::args());
    let config = config::Config::default();
    let app = app::AgenixApp::with_config(config);
    app.run(&args)
}
