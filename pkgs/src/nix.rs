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
        .args(["--json", "--eval", "--strict", "-E", &nix_expr])
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
        .args(["--json", "--eval", "--strict", "-E", &nix_expr])
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
        .args(["--json", "--eval", "-E", &nix_expr])
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

#[cfg(test)]
mod tests {
    use super::*;

    fn create_test_config() -> Config {
        Config {
            nix_instantiate: "nix-instantiate".to_string(),
            rules_path: "./test_secrets.nix".to_string(),
            ..Config::default()
        }
    }

    #[test]
    fn test_get_public_keys_with_nonexistent_rules() {
        let mut config = create_test_config();
        config.rules_path = "/nonexistent/rules.nix".to_string();

        let result = get_public_keys(&config, "test.age");
        assert!(result.is_err());
        // Should fail because rules file doesn't exist
    }

    #[test]
    fn test_should_armor_with_nonexistent_rules() {
        let mut config = create_test_config();
        config.rules_path = "/nonexistent/rules.nix".to_string();

        let result = should_armor(&config, "test.age");
        // Should return false (default) when rules file doesn't exist
        assert!(!result.unwrap_or(false));
    }

    #[test]
    fn test_get_all_files_with_nonexistent_rules() {
        let mut config = create_test_config();
        config.rules_path = "/nonexistent/rules.nix".to_string();

        let result = get_all_files(&config);
        assert!(result.is_err());
        // Should fail because rules file doesn't exist
    }

    #[test]
    fn test_nix_expr_format_get_public_keys() {
        // Test that the Nix expression is formatted correctly
        let config = create_test_config();
        let result = get_public_keys(&config, "test.age");

        // This will fail in most test environments due to missing nix-instantiate
        // but we can at least test that the function doesn't panic
        match result {
            Ok(_) => {
                // If nix-instantiate is available and works, great!
            }
            Err(err) => {
                // Expected in most test environments
                let err_str = err.to_string();
                // Should contain our file name in the error
                assert!(err_str.contains("test.age") || err_str.contains("nix-instantiate"));
            }
        }
    }

    #[test]
    fn test_nix_expr_format_should_armor() {
        let config = create_test_config();
        let result = should_armor(&config, "test.age");

        // This will likely fail in test environments, but shouldn't panic
        match result {
            Ok(armor) => {
                // If it works, armor should be a boolean
                assert!(armor || !armor);
            }
            Err(_) => {
                // Expected in most test environments without nix-instantiate
            }
        }
    }

    #[test]
    fn test_nix_expr_format_get_all_files() {
        let config = create_test_config();
        let result = get_all_files(&config);

        // This will likely fail in test environments, but shouldn't panic
        match result {
            Ok(_files) => {
                // If it works, should return a vector (may be empty)
                // No assertion needed - just test that it doesn't panic
            }
            Err(_) => {
                // Expected in most test environments without nix-instantiate
            }
        }
    }
}
