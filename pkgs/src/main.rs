mod app;
mod cli;
mod crypto;
mod editor;
mod nix;

use anyhow::Result;
use clap::Parser;

fn main() -> Result<()> {
    let args = cli::Args::parse_from(std::env::args());
    let app = app::AgenixApp::new();
    app.run(&args)
}
