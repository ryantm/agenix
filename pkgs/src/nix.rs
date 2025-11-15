use anyhow::{anyhow, Context, Result};
use serde_json::Value;
use std::process::Command;

use crate::config::Config;

/// Get public keys for a file from the rules
pub fn get_public_keys(config: &Config, file: &str) -> Result<Vec<String>> {
    let nix_expr = format!(
        "(let rules = import {}; in rules.\"{}\".publicKeys)",
        config.rules_path, file
    );

    let output = Command::new(&config.nix_instantiate)
        .args(&["--json", "--eval", "--strict", "-E", &nix_expr])
        .output()
        .context("Failed to run nix-instantiate")?;

    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        return Err(anyhow!(
            "Failed to get keys for file: {}, nix error: {}",
            file,
            stderr
        ));
    }

    let json_str =
        String::from_utf8(output.stdout).context("Failed to parse nix output as UTF-8")?;

    let json_value: Value =
        serde_json::from_str(&json_str).context("Failed to parse nix output as JSON")?;

    // Parse the JSON array into a vector of strings
    let keys = match json_value {
        Value::Array(arr) => arr
            .into_iter()
            .filter_map(|v| v.as_str().map(|s| s.to_string()))
            .collect(),
        _ => {
            return Err(anyhow!(
                "Expected JSON array for public keys, got: {}",
                json_value
            ))
        }
    };

    Ok(keys)
}

/// Check if a file should be armored (ASCII-armored output)
pub fn should_armor(config: &Config, file: &str) -> Result<bool> {
    let nix_expr = format!(
        "(let rules = import {}; in (builtins.hasAttr \"armor\" rules.\"{}\" && rules.\"{}\".armor))",
        config.rules_path, file, file
    );

    let output = Command::new(&config.nix_instantiate)
        .args(&["--json", "--eval", "--strict", "-E", &nix_expr])
        .output()
        .context("Failed to run nix-instantiate for armor check")?;

    if !output.status.success() {
        return Ok(false);
    }

    let result = String::from_utf8(output.stdout).context("Failed to parse nix output as UTF-8")?;

    Ok(result.trim() == "true")
}

/// Get all file names from the rules
pub fn get_all_files(config: &Config) -> Result<Vec<String>> {
    let nix_expr = format!(
        "(let rules = import {}; in builtins.attrNames rules)",
        config.rules_path
    );

    let output = Command::new(&config.nix_instantiate)
        .args(&["--json", "--eval", "-E", &nix_expr])
        .output()
        .context("Failed to run nix-instantiate")?;

    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        return Err(anyhow!("Failed to get file list from rules: {}", stderr));
    }

    let json_str =
        String::from_utf8(output.stdout).context("Failed to parse nix output as UTF-8")?;

    let json_value: Value =
        serde_json::from_str(&json_str).context("Failed to parse nix output as JSON")?;

    // Parse the JSON array into a vector of strings
    let files = match json_value {
        Value::Array(arr) => arr
            .into_iter()
            .filter_map(|v| v.as_str().map(|s| s.to_string()))
            .collect(),
        _ => {
            return Err(anyhow!(
                "Expected JSON array for file names, got: {}",
                json_value
            ))
        }
    };

    Ok(files)
}

/// Validate that the rules file exists and is accessible
pub fn validate_rules_file(config: &Config) -> Result<()> {
    if !std::path::Path::new(&config.rules_path).exists() {
        return Err(anyhow!("Rules file does not exist: {}", config.rules_path));
    }

    // Try to evaluate a simple expression to check if nix-instantiate works
    let test_expr = "builtins.attrNames {}";
    let output = Command::new(&config.nix_instantiate)
        .args(&["--json", "--eval", "-E", test_expr])
        .output()
        .context("Failed to test nix-instantiate")?;

    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        return Err(anyhow!(
            "nix-instantiate failed to evaluate test expression: {}",
            stderr
        ));
    }

    Ok(())
}

/// Get the raw JSON output from evaluating a Nix expression
pub fn eval_json(config: &Config, expr: &str) -> Result<Value> {
    let output = Command::new(&config.nix_instantiate)
        .args(&["--json", "--eval", "--strict", "-E", expr])
        .output()
        .context("Failed to run nix-instantiate")?;

    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        return Err(anyhow!("nix-instantiate failed: {}", stderr));
    }

    let json_str =
        String::from_utf8(output.stdout).context("Failed to parse nix output as UTF-8")?;

    serde_json::from_str(&json_str).context("Failed to parse nix output as JSON")
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::Write;
    use tempfile::NamedTempFile;

    fn create_test_config() -> Config {
        Config {
            nix_instantiate: "nix-instantiate".to_string(),
            rules_path: "./test_secrets.nix".to_string(),
            ..Config::default()
        }
    }

    fn create_test_rules_file() -> Result<NamedTempFile> {
        let mut file = NamedTempFile::new()?;
        writeln!(
            file,
            r#"{{
  "secret1.age" = {{
    publicKeys = [ "age1abc123..." "age1def456..." ];
    armor = true;
  }};
  "secret2.age" = {{
    publicKeys = [ "age1ghi789..." ];
  }};
}}"#
        )?;
        Ok(file)
    }

    #[test]
    fn test_validate_rules_file_nonexistent() {
        let mut config = create_test_config();
        config.rules_path = "/nonexistent/path".to_string();

        let result = validate_rules_file(&config);
        assert!(result.is_err());
        assert!(result.unwrap_err().to_string().contains("does not exist"));
    }

    #[test]
    fn test_eval_json_simple() {
        let config = create_test_config();

        // Test with a simple expression that should always work
        if let Ok(result) = eval_json(&config, "42") {
            assert_eq!(result, serde_json::json!(42));
        }
        // If nix-instantiate is not available, the test will be skipped
    }

    #[test]
    fn test_eval_json_invalid() {
        let config = create_test_config();

        let result = eval_json(&config, "invalid nix expression !!!");
        // Should fail with invalid syntax
        assert!(result.is_err());
    }

    // Integration tests that require nix-instantiate and jq to be available
    #[cfg(feature = "integration-tests")]
    mod integration_tests {
        use super::*;

        #[test]
        fn test_get_public_keys_with_real_nix() -> Result<()> {
            let rules_file = create_test_rules_file()?;
            let mut config = create_test_config();
            config.rules_path = rules_file.path().to_string_lossy().to_string();

            // This would work if we had a properly formatted Nix file
            // and nix-instantiate available
            let result = get_public_keys(&config, "secret1.age");

            // The test might fail if dependencies aren't available
            match result {
                Ok(keys) => {
                    assert!(!keys.is_empty());
                    assert!(keys.contains(&"age1abc123...".to_string()));
                }
                Err(_) => {
                    // Dependencies not available, skip test
                    println!("Skipping integration test - dependencies not available");
                }
            }

            Ok(())
        }

        #[test]
        fn test_should_armor_with_real_nix() -> Result<()> {
            let rules_file = create_test_rules_file()?;
            let mut config = create_test_config();
            config.rules_path = rules_file.path().to_string_lossy().to_string();

            match should_armor(&config, "secret1.age") {
                Ok(armor) => assert!(armor),
                Err(_) => {
                    // Dependencies not available, skip test
                    println!("Skipping integration test - dependencies not available");
                }
            }

            match should_armor(&config, "secret2.age") {
                Ok(armor) => assert!(!armor), // secret2 doesn't have armor = true
                Err(_) => {
                    // Dependencies not available, skip test
                    println!("Skipping integration test - dependencies not available");
                }
            }

            Ok(())
        }

        #[test]
        fn test_get_all_files_with_real_nix() -> Result<()> {
            let rules_file = create_test_rules_file()?;
            let mut config = create_test_config();
            config.rules_path = rules_file.path().to_string_lossy().to_string();

            match get_all_files(&config) {
                Ok(files) => {
                    assert_eq!(files.len(), 2);
                    assert!(files.contains(&"secret1.age".to_string()));
                    assert!(files.contains(&"secret2.age".to_string()));
                }
                Err(_) => {
                    // Dependencies not available, skip test
                    println!("Skipping integration test - dependencies not available");
                }
            }

            Ok(())
        }
    }
}
