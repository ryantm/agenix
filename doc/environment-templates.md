# Environment templates {#environment-templates}

An application configuration can remain public while selected values come from
an encrypted environment file. `age.derivedSecrets` performs this substitution
during activation and installs the result with the normal agenix ownership,
permissions, generation handling, and change hooks.

For example, encrypt this environment file as `application.env.age`:

```text
SECRET_1='foo with "quotes"'
SECRET_2=bar
```

Keep `config.template.json` unencrypted:

```json
{
  "secret": "$SECRET_1",
  "another_secret": "${SECRET_2}",
  "public_setting": true
}
```

Declare the inputs and output in a NixOS or nix-darwin module:

```nix
{ config, ... }:
{
  age.secrets.application-env.file = ./application.env.age;
  age.derivedSecrets.application-config = {
    template = ./config.template.json;
    environmentFiles = [ config.age.secrets.application-env ];
    format = "json";
    owner = "my-service";
    restartUnits = [ "my-service.service" ]; # NixOS only
  };
  # Configure the application to read:
  # config.age.derivedSecrets.application-config.path
}
```

JSON mode escapes inserted string contents and validates the result before
publishing it. The example's first value becomes `"foo with \"quotes\""` in
the generated JSON. Keep placeholders inside JSON strings; this mode does not
insert arbitrary JSON objects or numbers. The default `format = "text"` performs
literal substitution and does not apply format-specific escaping.

Environment files use a deliberately small syntax: one `KEY=value` assignment
per line, with optional `export`, blank lines, and `#` comments. Keys match
`[A-Za-z_][A-Za-z0-9_]*`. Shell-style single/double quoting and backslash escaping
are supported; quote values containing whitespace or `#`. Empty values are
allowed. Values are literal: variable references, backticks, and command
substitutions inside them are never evaluated. Multi-line quoted assignments
and shell statements are not supported. Use ordinary encrypted secret files and
the `secrets` list for multi-line or binary content.

Only the listed environment files provide variables; the activation process's
environment is not consulted. Repeated keys use the last assignment, including
across files in list order. When `environmentFiles` is non-empty, references to
undefined variables fail rather than silently inserting empty strings. With no
environment files, dollar expressions in existing templates are left unchanged.

`@secret-name@` placeholders from the `secrets` list and environment placeholders
can be combined. All replacements happen in one pass, so substituted content is
never treated as a new placeholder. `trimFinalNewline` applies to whole-file
inputs in `secrets`; environment assignment parsing handles its own line endings.

Malformed assignments, missing variables, and invalid JSON preserve the previous
generation and skip change hooks. Assignment errors identify the input and line;
missing-variable errors name the variable. Neither includes the environment
file's contents. Plaintext is rendered on the
target; keep the template itself free of secrets because Nix copies it to the store.
Home Manager does not currently support derived secrets.
