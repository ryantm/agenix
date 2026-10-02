{ pkgs }:
let
  levels = [
    "quiet"
    "summary"
    "progress"
    "detailed"
  ];
  levelOrder = {
    quiet = 0;
    summary = 1;
    progress = 2;
    detailed = 3;
  };
  atLeast = level: minimum: levelOrder.${level} >= levelOrder.${minimum};
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
      name = level;
      value = makeNode level;
    }) levels
  );

  testScript = pkgs.lib.concatMapStringsSep "\n" (level: ''
    ${level}.start()
    ${level}.wait_for_unit("multi-user.target")
    assert ${level}.succeed("cat /run/agenix/one").strip() == "hello"
    # Force installation so this test covers all decryption messages.
    ${level}.succeed("rm /run/agenix/one")
    ${level}.succeed("/run/current-system/activate > /tmp/agenix-stdout 2> /tmp/agenix-stderr")
    stdout = ${level}.succeed("cat /tmp/agenix-stdout")
    stderr = ${level}.succeed("cat /tmp/agenix-stderr")
    assert ${level}.succeed("cat /run/agenix/one").strip() == "hello"
    assert "[agenix] WARNING: config.age.identityPaths entry /etc/agenix-missing-key not present!" in stderr
    assert "[agenix] WARNING:" not in stdout
    assert ("[agenix] decrypting secrets..." in stdout) == (${
      if atLeast level "summary" then "True" else "False"
    })
    assert ("[agenix] creating new generation" in stdout) == (${
      if atLeast level "progress" then "True" else "False"
    })
    assert ("[agenix] symlinking new secrets" in stdout) == (${
      if atLeast level "progress" then "True" else "False"
    })
    assert ("[agenix] removing old secrets" in stdout) == (${
      if atLeast level "progress" then "True" else "False"
    })
    assert ("[agenix] chowning..." in stdout) == (${
      if atLeast level "progress" then "True" else "False"
    })
    assert ("decrypting '" in stdout) == (${if atLeast level "detailed" then "True" else "False"})
    ${level}.shutdown()
  '') levels;
}
