use clap::Parser;

#[derive(Parser, Debug)]
#[command(
    version = env!("CARGO_PKG_VERSION"),
    about = "edit and rekey age secret files",
    after_help = concat!("agenix version: ", env!("CARGO_PKG_VERSION"))
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

    /// Path to Nix rules file (can also be set via RULES env var)
    #[arg(
        long,
        env = "RULES",
        value_name = "FILE",
        default_value = "./secrets.nix"
    )]
    pub rules: String,

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

    #[test]
    fn test_rules_env_var() {
        use std::env;
        let original = env::var("RULES").ok();
        unsafe {
            env::set_var("RULES", "/custom/path/secrets.nix");
        }

        let args = Args::try_parse_from(["agenix"]).unwrap();
        assert_eq!(args.rules, "/custom/path/secrets.nix");

        match original {
            Some(val) => unsafe { env::set_var("RULES", val) },
            None => unsafe { env::remove_var("RULES") },
        }
    }

    #[test]
    fn test_help_contains_version() {
        use clap::CommandFactory;
        
        let mut cmd = Args::command();
        let help = cmd.render_help().to_string();
        
        // Check that help contains the version information at the end
        let expected_version_line = format!("agenix version: {}", env!("CARGO_PKG_VERSION"));
        assert!(help.contains(&expected_version_line), 
               "Help output should contain version line: {}", expected_version_line);
        
        // Also verify it's near the end (after the options section)
        let options_pos = help.find("Options:").expect("Help should contain Options section");
        let version_pos = help.find(&expected_version_line).expect("Help should contain version line");
        assert!(version_pos > options_pos, "Version line should appear after Options section");
    }
}
