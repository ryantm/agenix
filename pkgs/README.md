# Agenix Rust Implementation

Pure Rust port of agenix - edit and rekey age secret files using Nix expressions.

## Dependencies

- `age` - Age encryption tool
- `nix-instantiate` - Nix expression evaluator

## Improvements over shell version

- No `jq` dependency (uses `serde_json`)
- Native binary (no bash required)
- Better error handling and type safety

## Usage

```bash
agenix -e secret.age    # Edit
agenix -d secret.age    # Decrypt  
agenix -r              # Rekey all
```

## Build & Test

```bash
cargo build --release
cargo test
```
