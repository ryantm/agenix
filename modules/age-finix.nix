{
  config,
  lib,
  ...
}:
let
  source = builtins.readFile ./age.nix;

  splice =
    {
      name,
      text,
      start,
      end,
      replacement,
    }:
    let
      before = builtins.split start text;
      after = builtins.split end text;
    in
    if builtins.length before < 2 then
      throw "agenix Finix patch failed: ${name} start marker not found"
    else if builtins.length after < 2 then
      throw "agenix Finix patch failed: ${name} end marker not found"
    else
      (builtins.head before) + replacement + (builtins.elemAt after 2);

  noSysusers = splice {
    name = "sysusers";
    text = source;
    start = "  sysusersEnabled =";
    end = "  mountCommand =";
    replacement = "  sysusersEnabled = false;\n  mountCommand =";
  };

  noSystemd = splice {
    name = "systemd";
    text = noSysusers;
    start = "      # When using sysusers we no longer be started as an activation script";
    end = "      # Create a new directory full of secrets for symlinking";
    replacement = "      # Create a new directory full of secrets for symlinking";
  };

  agenixFinixModule = import (builtins.toFile "agenix-finix.nix" noSystemd);
in
{
  imports = [ agenixFinixModule ];

  options.system.activationScripts = lib.mkOption {
    default = { };
    type = lib.types.attrsOf (
      lib.types.submodule {
        options = {
          text = lib.mkOption {
            type = lib.types.lines;
            default = "";
          };
          deps = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [ ];
          };
        };
      }
    );
  };

  config = {
    users.groups.keys = { };

    system.activation.scripts = lib.mapAttrs (_: script: {
      inherit (script) text;
      deps = lib.filter (dep: dep != "groups") script.deps;
    }) config.system.activationScripts;
  };
}
