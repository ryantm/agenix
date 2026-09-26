{
  nixpkgs ? <nixpkgs>,
  pkgs ? import <nixpkgs> {
    inherit system;
    config = { };
  },
  system ? builtins.currentSystem,
  home-manager ? <home-manager>,
}:
pkgs.testers.nixosTest {
  name = "agenix-integration";
  nodes.system1 =
    {
      config,
      pkgs,
      options,
      ...
    }:
    {
      imports = [
        ../modules/age.nix
        ./install_ssh_host_keys.nix
        "${home-manager}/nixos"
      ];

      services.openssh.enable = true;

      age.secrets = {
        disabled.enable = false;
        passwordfile-user1.file = ../example/passwordfile-user1.age;
        leading-hyphen.file = ../example/-leading-hyphen-filename.age;
        named-owner = {
          file = ../example/secret1.age;
          owner = "getpsyched";
        };
      };

      age.identityPaths = options.age.identityPaths.default ++ [ "/etc/ssh/this_key_wont_exist" ];

      environment.systemPackages = [
        (pkgs.callPackage ../pkgs/agenix.nix { })
      ];

      users = {
        mutableUsers = false;

        users = {
          user1 = {
            isNormalUser = true;
            hashedPasswordFile = config.age.secrets.passwordfile-user1.path;
            uid = 1000;
          };
          primary = {
            name = "getpsyched";
            isNormalUser = true;
            group = "users";
            uid = 1001;
          };
        };
      };

      home-manager.users.user1 =
        { options, ... }:
        {
          imports = [
            ../modules/age-home.nix
          ];

          home.stateVersion = pkgs.lib.trivial.release;

          age = {
            secrets.disabled.enable = false;
            identityPaths = options.age.identityPaths.default ++ [ "/home/user1/.ssh/this_key_wont_exist" ];
            secrets.secret2 = {
              # Only decryptable by user1's key
              file = ../example/secret2.age;
            };
            secrets.secret2Path = {
              file = ../example/secret2.age;
              path = "/home/user1/secret2";
            };
            secrets.armored-secret = {
              file = ../example/armored-secret.age;
            };
          };
        };
    };

  nodes.disabled = { pkgs, ... }: {
    imports = [
      ../modules/age.nix
      "${home-manager}/nixos"
    ];
    age.secrets.only-disabled.enable = false;
    home-manager.users.user1 = { ... }: {
      imports = [ ../modules/age-home.nix ];
      home.username = "user1";
      home.homeDirectory = "/home/user1";
      home.stateVersion = pkgs.lib.trivial.release;
      age.secrets.only-disabled.enable = false;
    };
    users.users.user1 = {
      isNormalUser = true;
      uid = 1000;
    };
  };

  nodes.forcedDisabled = { pkgs, ... }: {
    imports = [
      ../modules/age.nix
      "${home-manager}/nixos"
    ];
    age.enable = false;
    age.secrets.configured.file = ../example/secret1.age;
    users.users.user1 = {
      isNormalUser = true;
      uid = 1000;
    };
    home-manager.users.user1 = { ... }: {
      imports = [ ../modules/age-home.nix ];
      home.username = "user1";
      home.homeDirectory = "/home/user1";
      home.stateVersion = pkgs.lib.trivial.release;
      age.enable = false;
      age.secrets.configured.file = ../example/secret2.age;
    };
  };

  testScript =
    let
      user = "user1";
      password = "password1234";
      secret2 = "world!";
      hyphen-secret = "filename started with hyphen";
      armored-secret = "Hello World!";
    in
    ''
      system1.wait_for_unit("multi-user.target")
      system1.succeed("test -e /home/user1/.config/systemd/user/agenix.service")
      disabled.wait_for_unit("multi-user.target")
      disabled.fail("test -e /run/agenix")
      disabled.fail("systemctl cat agenix-install-secrets.service")
      disabled.fail("systemctl cat agenix-chown.service")
      disabled.fail("test -e /home/user1/.config/systemd/user/agenix.service")
      forcedDisabled.wait_for_unit("multi-user.target")
      forcedDisabled.fail("test -e /run/agenix")
      forcedDisabled.fail("test -e /home/user1/.config/systemd/user/agenix.service")
      # The owner is a Linux username, while its users.users attribute is "primary".
      # The default secret group should come from that user's configuration.
      owner_group = system1.succeed("stat -Lc '%U:%G' /run/agenix/named-owner").strip()
      assert owner_group == "getpsyched:users", owner_group
      system1.wait_until_succeeds("pgrep -f 'agetty.*tty1'")
      system1.sleep(2)
      system1.send_key("alt-f2")
      system1.wait_until_succeeds("[ $(fgconsole) = 2 ]")
      system1.wait_for_unit("getty@tty2.service")
      system1.wait_until_succeeds("pgrep -f 'agetty.*tty2'")
      system1.wait_until_tty_matches("2", "login: ")
      system1.send_chars("${user}\n")
      system1.wait_until_tty_matches("2", "login: ${user}")
      system1.wait_until_succeeds("pgrep login")
      system1.sleep(2)
      system1.send_chars("${password}\n")
      system1.send_chars("whoami > /tmp/1\n")
      system1.wait_for_file("/tmp/1")
      assert "${user}" in system1.succeed("cat /tmp/1")
      system1.send_chars("cat /run/user/$(id -u)/agenix/secret2 > /tmp/2\n")
      system1.wait_for_file("/tmp/2")
      assert "${secret2}" in system1.succeed("cat /tmp/2")
      system1.fail("test -e /run/user/1000/agenix/disabled")
      system1.send_chars("cat /run/user/$(id -u)/agenix/armored-secret > /tmp/3\n")
      system1.wait_for_file("/tmp/3")
      assert "${armored-secret}" in system1.succeed("cat /tmp/3")

      assert "${hyphen-secret}" in system1.succeed("cat /run/agenix/leading-hyphen")
      system1.fail("test -e /run/agenix/disabled")

      userDo = lambda input, directory="/tmp/secrets": f"sudo -u user1 -- bash -c 'set -eou pipefail; cd {directory}; {input}'"

      # A leading ./ in a CLI path should match the same rules entry.
      assert "hello" in system1.succeed(userDo("agenix -d ./secret1.age"))
      system1.succeed(userDo("EDITOR=: agenix -e ./secret1.age -i /home/user1/.ssh/id_ed25519"))
      assert "hello" in system1.succeed(userDo("agenix -d secret1.age"))

      # Legacy lookup and RULES warn, while an explicitly selected filename does not.
      legacy_default = system1.succeed(userDo("env -u AGENIX_RULES -u RULES agenix -d secret1.age 2>&1"))
      assert "hello" in legacy_default
      assert "RULES and automatic discovery of secrets.nix are deprecated and will be removed in a future version of agenix" in legacy_default

      legacy_variable = system1.succeed(userDo("env RULES=secrets.nix agenix -d secret1.age 2>&1"))
      assert "hello" in legacy_variable
      assert "RULES and automatic discovery of secrets.nix are deprecated and will be removed in a future version of agenix" in legacy_variable

      explicit_filename = system1.succeed(userDo("env AGENIX_RULES=secrets.nix agenix -d secret1.age 2>&1"))
      assert "hello" in explicit_filename
      assert "deprecated" not in explicit_filename

      system1.succeed(userDo("cp secrets.nix agenix-rules.nix"))
      new_default = system1.succeed(userDo("env -u AGENIX_RULES -u RULES agenix -d secret1.age 2>&1"))
      assert "hello" in new_default
      assert "deprecated" not in new_default

      legacy_variable_new_file = system1.succeed(userDo("env RULES=agenix-rules.nix agenix -d secret1.age 2>&1"))
      assert "hello" in legacy_variable_new_file
      assert "RULES and automatic discovery of secrets.nix are deprecated and will be removed in a future version of agenix" in legacy_variable_new_file

      new_variable = system1.succeed(userDo("env RULES=secrets.nix AGENIX_RULES=agenix-rules.nix agenix -d secret1.age 2>&1"))
      assert "hello" in new_variable
      assert "deprecated" not in new_variable

      # An explicitly selected missing file must not silently fall back.
      system1.fail(userDo("env AGENIX_RULES=missing.nix agenix -d secret1.age"))

      system1.succeed(userDo("mkdir nested"))
      parent_rules = system1.succeed(userDo("cd nested && env -u AGENIX_RULES -u RULES agenix -d secret1.age 2>&1"))
      assert "hello" in parent_rules
      assert "deprecated" not in parent_rules

      # A parent secrets.nix is not discovered; the current directory still is.
      system1.succeed(userDo("mv agenix-rules.nix agenix-rules.nix.hidden"))
      missing_status, missing_output = system1.execute(userDo("cd nested && env -u AGENIX_RULES -u RULES agenix -d secret1.age 2>&1"))
      assert missing_status != 0
      assert "needs a rules file" in missing_output
      system1.succeed(userDo("mv agenix-rules.nix.hidden agenix-rules.nix && cp secrets.nix secret1.age nested/"))
      local_legacy = system1.succeed(userDo("cd nested && env -u AGENIX_RULES -u RULES agenix -d secret1.age 2>&1"))
      assert "hello" in local_legacy
      assert "automatic discovery of secrets.nix are deprecated" in local_legacy

      # Rekey from a child directory must update files beside the discovered rules.
      nested_before = system1.succeed(userDo("sha256sum passwordfile-user1.age")).split()[0]
      system1.succeed(userDo("mkdir nested-rekey && ln -s /home/user1/.ssh/id_ed25519 nested-rekey/identity"))
      nested_rekey = system1.succeed(userDo("cd nested-rekey && agenix -r -i identity 2>&1"))
      assert "wasn't created" not in nested_rekey
      nested_after = system1.succeed(userDo("sha256sum passwordfile-user1.age")).split()[0]
      assert nested_before != nested_after
      system1.succeed(userDo("test ! -e nested-rekey/passwordfile-user1.age"))
      explicit_parent = system1.succeed(userDo("cd nested-rekey && AGENIX_RULES=../agenix-rules.nix agenix -d secret1.age 2>&1"))
      assert "hello" in explicit_parent
      assert "deprecated" not in explicit_parent

      before_hash = system1.succeed(userDo('sha256sum passwordfile-user1.age')).split()
      print(system1.succeed(userDo('agenix -r -i /home/user1/.ssh/id_ed25519')))
      after_hash = system1.succeed(userDo('sha256sum passwordfile-user1.age')).split()

      # Ensure we actually have hashes
      for h in [before_hash, after_hash]:
          assert len(h) == 2, "hash should be [hash, filename]"
          assert h[1] == "passwordfile-user1.age", "filename is incorrect"
          assert len(h[0].strip()) == 64, "hash length is incorrect"
      assert before_hash[0] != after_hash[0], "hash did not change with rekeying"

      # user1 can edit passwordfile-user1.age
      system1.succeed(userDo("EDITOR=cat agenix -e passwordfile-user1.age"))

      # user1 can edit even if bogus id_rsa present
      system1.succeed(userDo("echo bogus > ~/.ssh/id_rsa"))
      system1.fail(userDo("EDITOR=cat agenix -e passwordfile-user1.age"))
      system1.succeed(userDo("EDITOR=cat agenix -e passwordfile-user1.age -i /home/user1/.ssh/id_ed25519"))
      system1.succeed(userDo("rm ~/.ssh/id_rsa"))

      # user1 can edit a secret by piping in contents
      system1.succeed(userDo("echo 'secret1234' | agenix -e passwordfile-user1.age"))

      # and get it back out via --decrypt
      assert "secret1234" in system1.succeed(userDo("agenix -d passwordfile-user1.age"))

      # finally, the plain text should not linger around anywhere in the filesystem.
      system1.fail("grep -r secret1234 /tmp")

      # A user without a recipient identity can create and replace a secret via stdin.
      one_way_dir = "/tmp/secrets-one-way"
      system1.succeed(userDo("echo eye1234 | agenix -e one-way.age", one_way_dir))
      system1.fail(userDo("agenix -d one-way.age </dev/null", one_way_dir))
      assert system1.succeed(f"cd {one_way_dir}; agenix -d one-way.age -i /etc/ssh/ssh_host_ed25519_key </dev/null").strip() == "eye1234"

      # An attempted interactive edit without an identity must leave the file intact.
      original_hash = system1.succeed(f"sha256sum {one_way_dir}/one-way.age").split()[0]
      system1.fail(userDo('script -q -e -c "EDITOR=cat agenix -e one-way.age" /dev/null', one_way_dir))
      assert system1.succeed(f"sha256sum {one_way_dir}/one-way.age").split()[0] == original_hash

      system1.succeed(userDo("echo nose1234 | agenix -e one-way.age", one_way_dir))
      assert system1.succeed(f"cd {one_way_dir}; agenix -d one-way.age -i /etc/ssh/ssh_host_ed25519_key </dev/null").strip() == "nose1234"

      # Direct decryption and rekeying still work when stdin is not a terminal.
      before_rekey = system1.succeed(f"sha256sum {one_way_dir}/one-way.age").split()[0]
      system1.fail(userDo("agenix -r </dev/null", one_way_dir))
      assert system1.succeed(f"sha256sum {one_way_dir}/one-way.age").split()[0] == before_rekey
      system1.succeed(f"cd {one_way_dir}; agenix -r -i /etc/ssh/ssh_host_ed25519_key </dev/null")
      assert system1.succeed(f"sha256sum {one_way_dir}/one-way.age").split()[0] != before_rekey
      assert system1.succeed(f"cd {one_way_dir}; agenix -d one-way.age -i /etc/ssh/ssh_host_ed25519_key </dev/null").strip() == "nose1234"
    '';
}
