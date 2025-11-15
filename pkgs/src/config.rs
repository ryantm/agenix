use std::env;

/// Simple configuration struct
#[derive(Debug, Clone)]
pub struct Config {
    pub age_bin: String,
    pub nix_instantiate: String,
    pub rules_path: String,
}

impl Default for Config {
    fn default() -> Self {
        Self {
            age_bin: "age".to_string(),
            nix_instantiate: "nix-instantiate".to_string(),
            rules_path: env::var("RULES").unwrap_or_else(|_| "./secrets.nix".to_string()),
        }
    }
}

/// Check if required dependencies are available
pub fn validate_dependencies(config: &Config) -> Result<(), Vec<String>> {
    let mut missing = Vec::new();

    let binaries = [
        (&config.age_bin, "age"),
        (&config.nix_instantiate, "nix-instantiate"),
    ];

    for (path, name) in &binaries {
        if std::process::Command::new(path)
            .arg("--version")
            .output()
            .is_err()
        {
            missing.push(format!("{} ({})", name, path));
        }
    }

    if missing.is_empty() {
        Ok(())
    } else {
        Err(missing)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::env;

    #[test]
    fn test_config_default() {
        let config = Config::default();
        assert_eq!(config.age_bin, "age");
        assert_eq!(config.nix_instantiate, "nix-instantiate");
    }

    #[test]
    fn test_config_with_rules_env() {
        env::set_var("RULES", "/custom/path/secrets.nix");
        let config = Config::default();
        assert_eq!(config.rules_path, "/custom/path/secrets.nix");
        env::remove_var("RULES");
    }
}
