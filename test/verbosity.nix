{ pkgs }:
let
  levels = [
    0
    1
    2
    3
  ];
  makeNode = level: {
    imports = [ ../modules/age.nix ];
    # The identity must exist before agenix runs in initrd activation.
    system.activationScripts.agenixInstall.deps = [ "installAgenixTestKey" ];
    system.activationScripts.installAgenixTestKey.text = ''
      install -m 0600 ${../example_keys/system1} /etc/agenix-test-key
    '';
    age = {
      verbosity = level;
      identityPaths = [
        "/etc/agenix-test-key"
        "/etc/agenix-missing-key"
      ];
      secrets.one.file = ../example/secret1.age;
    };
  };
in
pkgs.testers.nixosTest {
  name = "agenix-verbosity";

  nodes = builtins.listToAttrs (
    map (level: {
      name = "level${toString level}";
      value = makeNode level;
    }) levels
  );

  testScript = pkgs.lib.concatMapStringsSep "\n" (level: ''
    level${toString level}.start()
    level${toString level}.wait_for_unit("multi-user.target")
    assert level${toString level}.succeed("cat /run/agenix/one").strip() == "hello"
    level${toString level}.succeed("/run/current-system/activate > /tmp/agenix-stdout 2> /tmp/agenix-stderr")
    stdout = level${toString level}.succeed("cat /tmp/agenix-stdout")
    stderr = level${toString level}.succeed("cat /tmp/agenix-stderr")
    assert level${toString level}.succeed("cat /run/agenix/one").strip() == "hello"
    assert "[agenix] WARNING: config.age.identityPaths entry /etc/agenix-missing-key not present!" in stderr
    assert "[agenix] WARNING:" not in stdout
    assert ("[agenix] decrypting secrets..." in stdout) == (${if level >= 1 then "True" else "False"})
    assert ("[agenix] creating new generation" in stdout) == (${if level >= 2 then "True" else "False"})
    assert ("[agenix] symlinking new secrets" in stdout) == (${if level >= 2 then "True" else "False"})
    assert ("[agenix] removing old secrets" in stdout) == (${if level >= 2 then "True" else "False"})
    assert ("[agenix] chowning..." in stdout) == (${if level >= 2 then "True" else "False"})
    assert ("decrypting '" in stdout) == (${if level >= 3 then "True" else "False"})
    level${toString level}.shutdown()
  '') levels;
}
