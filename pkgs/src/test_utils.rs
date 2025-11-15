/// Test utilities and helpers for agenix
#[cfg(test)]
use std::io::Write;
#[cfg(test)]
use tempfile::NamedTempFile;

#[cfg(test)]
pub fn create_test_rules_file() -> std::io::Result<NamedTempFile> {
    let mut file = NamedTempFile::new()?;
    writeln!(
        file,
        r#"{{
  "secret1.age" = {{
    publicKeys = [ "age1abc123def456ghi789" "age1xyz987uvw654rst321" ];
    armor = true;
  }};
  "secret2.age" = {{
    publicKeys = [ "age1mno456pqr789stu012" ];
  }};
  "secret3.age" = {{
    publicKeys = [ "age1vwx345yzab678cdef901" ];
    armor = false;
  }};
}}"#
    )?;
    file.flush()?;
    Ok(file)
}

#[cfg(test)]
pub fn create_test_encrypted_content() -> Vec<u8> {
    // This would be actual age-encrypted content in a real scenario
    b"-----BEGIN AGE ENCRYPTED FILE-----
YWdlLWVuY3J5cHRpb24ub3JnL3YxCi0+IGFnZTE...
-----END AGE ENCRYPTED FILE-----"
        .to_vec()
}

#[cfg(test)]
pub fn create_mock_config() -> crate::config::Config {
    crate::config::Config {
        age_bin: "echo".to_string(), // Use echo as a mock for testing
        nix_instantiate: "echo".to_string(),
        mktemp_bin: "mktemp".to_string(),
        diff_bin: "diff".to_string(),
        rules_path: "./test_secrets.nix".to_string(),
    }
}
