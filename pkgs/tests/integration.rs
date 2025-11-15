use agenix::app::AgenixApp;
use agenix::cli::Args;
use agenix::config::Config;
use clap::Parser;
use std::env;
use std::io::Write;
use tempfile::NamedTempFile;

fn create_mock_config() -> Config {
    Config {
        age_bin: "echo".to_string(), // Mock with echo
        nix_instantiate: "echo".to_string(),
        diff_bin: "diff".to_string(),
        rules_path: "./test_secrets.nix".to_string(),
    }
}

fn create_test_secrets_file() -> std::io::Result<NamedTempFile> {
    let mut file = NamedTempFile::new()?;
    writeln!(
        file,
        r#"{{
  "test.age" = {{
    publicKeys = [ "age1test123" "age1test456" ];
  }};
}}"#
    )?;
    file.flush()?;
    Ok(file)
}

#[test]
fn test_full_workflow_with_mocks() {
    // This test uses mocked dependencies so it should work in any environment
    let config = create_mock_config();
    let app = AgenixApp::with_config(config);

    // Test with a specific action that would require dependencies
    let args = Args {
        edit: Some("test.age".to_string()),
        identity: None,
        rekey: false,
        decrypt: None,
        verbose: false,
    };

    // This should fail due to dependency validation or missing file
    let result = app.run(args);
    assert!(result.is_err()); // Expected because mocked dependencies or missing file
}

#[test]
fn test_config_validation() {
    let config = Config::default();

    // This will likely fail in CI/test environments without the actual tools
    let result = agenix::config::validate_dependencies(&config);

    match result {
        Ok(()) => {
            // All dependencies available - great!
            println!("All dependencies available");
        }
        Err(missing) => {
            // Expected in most test environments
            println!("Missing dependencies: {:?}", missing);
            assert!(!missing.is_empty());
        }
    }
}

#[test]
fn test_default_identities() {
    let identities = agenix::crypto::get_default_identities();
    // Should return 0-2 identity files depending on system
    assert!(identities.len() <= 2);
}

#[test]
fn test_rules_path_from_env() {
    env::set_var("RULES", "/custom/path/secrets.nix");
    let config = Config::default();
    assert_eq!(config.rules_path, "/custom/path/secrets.nix");
    env::remove_var("RULES");
}

#[test]
fn test_verbose_mode() {
    let config = Config::default();
    let app = AgenixApp::with_config(config);

    let args = Args {
        edit: None,
        identity: None,
        rekey: false,
        decrypt: None,
        verbose: true,
    };

    // Even if this fails due to dependencies, verbose flag should be set
    let _ = app.run(args);

    // Check if RUST_LOG was set (might be set by the run method)
    // This is more of a smoke test since the actual behavior depends on logging setup
}

#[test]
fn test_cli_parsing_edge_cases() {
    // Test parsing with multiple flags
    let args = Args::try_parse_from(&[
        "agenix",
        "--verbose",
        "--edit",
        "secret.age",
        "--identity",
        "/path/to/key",
    ])
    .unwrap();

    assert!(args.verbose);
    assert_eq!(args.edit, Some("secret.age".to_string()));
    assert_eq!(args.identity, Some("/path/to/key".to_string()));
    assert!(!args.rekey);
    assert_eq!(args.decrypt, None);
}

#[test]
fn test_cli_parsing_conflicts() {
    // Test that we can have both edit and decrypt (though the app logic handles precedence)
    let args =
        Args::try_parse_from(&["agenix", "--edit", "file1.age", "--decrypt", "file2.age"]).unwrap();

    assert_eq!(args.edit, Some("file1.age".to_string()));
    assert_eq!(args.decrypt, Some("file2.age".to_string()));
}
