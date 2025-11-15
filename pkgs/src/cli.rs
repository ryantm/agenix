use clap::Parser;

#[derive(Parser, Debug)]
#[command(
    name = "agenix",
    version = env!("CARGO_PKG_VERSION"),
    about = "edit and rekey age secret files",
    long_about = None
)]
pub struct Args {
    /// Edit FILE using $EDITOR
    #[arg(short, long, value_name = "FILE")]
    pub edit: Option<String>,

    /// Identity to use when decrypting
    #[arg(short, long, value_name = "PRIVATE_KEY")]
    pub identity: Option<String>,

    /// Re-encrypts all secrets with specified recipients
    #[arg(short, long)]
    pub rekey: bool,

    /// Decrypt FILE to STDOUT
    #[arg(short, long, value_name = "FILE")]
    pub decrypt: Option<String>,

    /// Verbose output
    #[arg(short, long)]
    pub verbose: bool,
}

impl Args {
    pub fn show_help() {
        const PACKAGE: &str = "agenix";
        const VERSION: &str = env!("CARGO_PKG_VERSION");

        println!("{PACKAGE} - edit and rekey age secret files");
        println!(" ");
        println!("{PACKAGE} -e FILE [-i PRIVATE_KEY]");
        println!("{PACKAGE} -r [-i PRIVATE_KEY]");
        println!(" ");
        println!("options:");
        println!("-h, --help                show help");
        println!("-e, --edit FILE           edits FILE using $EDITOR");
        println!("-r, --rekey               re-encrypts all secrets with specified recipients");
        println!("-d, --decrypt FILE        decrypts FILE to STDOUT");
        println!("-i, --identity            identity to use when decrypting");
        println!("-v, --verbose             verbose output");
        println!(" ");
        println!("FILE an age-encrypted file");
        println!(" ");
        println!("PRIVATE_KEY a path to a private SSH key used to decrypt file");
        println!(" ");
        println!("EDITOR environment variable of editor to use when editing FILE");
        println!(" ");
        println!("If STDIN is not interactive, EDITOR will be set to \"cp /dev/stdin\"");
        println!(" ");
        println!(
            "RULES environment variable with path to Nix file specifying recipient public keys."
        );
        println!("Defaults to './secrets.nix'");
        println!(" ");
        println!("agenix version: {VERSION}");
        println!("age binary path: age");

        // Try to get age version
        if let Ok(output) = std::process::Command::new("age").arg("--version").output() {
            if let Ok(version) = String::from_utf8(output.stdout) {
                println!("age version: {}", version.trim());
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_args_parsing() {
        let args = Args::try_parse_from(["agenix", "-e", "test.age"]).unwrap();
        assert_eq!(args.edit, Some("test.age".to_string()));
        assert!(!args.rekey);
        assert_eq!(args.decrypt, None);
        assert_eq!(args.identity, None);
        assert!(!args.verbose);
    }

    #[test]
    fn test_rekey_flag() {
        let args = Args::try_parse_from(["agenix", "-r"]).unwrap();
        assert!(args.rekey);
        assert_eq!(args.edit, None);
    }

    #[test]
    fn test_decrypt_with_identity() {
        let args =
            Args::try_parse_from(["agenix", "-d", "secret.age", "-i", "/path/to/key"]).unwrap();
        assert_eq!(args.decrypt, Some("secret.age".to_string()));
        assert_eq!(args.identity, Some("/path/to/key".to_string()));
    }

    #[test]
    fn test_verbose_flag() {
        let args = Args::try_parse_from(["agenix", "-v", "-e", "test.age"]).unwrap();
        assert!(args.verbose);
        assert_eq!(args.edit, Some("test.age".to_string()));
    }
}
