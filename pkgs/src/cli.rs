use clap::Parser;

#[derive(Parser, Debug)]
#[command(
    version = env!("CARGO_PKG_VERSION"),
    about = "edit and rekey age secret files",
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
