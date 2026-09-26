{
  pkgs,
}:
pkgs.testers.nixosTest {
  name = "agenix-userborn";

  nodes.machine =
    { config, ... }:
    {
      imports = [ ../modules/age.nix ];

      services.userborn.enable = true;
      users.mutableUsers = false;
      users.users.user1 = {
        isNormalUser = true;
        uid = 1000;
        hashedPasswordFile = config.age.secrets.password.path;
      };

      # This private key is a public test fixture, never a real identity.
      environment.etc."agenix-test-key".source = ../example_keys/system1;
      age.identityPaths = [ "/etc/agenix-test-key" ];
      age.secrets = {
        password.file = ../example/passwordfile-user1.age;
        owned = {
          file = ../example/secret1.age;
          owner = "user1";
          group = "users";
        };
      };
    };

  testScript = ''
    machine.wait_for_unit("multi-user.target")

    # userborn must see the decrypted password hash when it creates user1.
    machine.succeed('test "$(getent shadow user1 | cut -d: -f2)" = "$(cat /run/agenix/password)"')

    # Ownership must be applied after userborn creates the user and group.
    machine.succeed('test "$(stat -Lc %U:%G /run/agenix/owned)" = user1:users')

    machine.succeed("systemctl is-active agenix-install-secrets.service")
    machine.succeed("systemctl is-active agenix-chown.service")
  '';
}
