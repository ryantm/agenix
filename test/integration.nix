{
  nixpkgs ? <nixpkgs>,
  pkgs ?
    import <nixpkgs> {
      inherit system;
      config = {};
    },
  system ? builtins.currentSystem,
}:
pkgs.nixosTest {
  name = "agenix-integration";
  extraPythonPackages = ps: let
    agenixTesting = let
      version = (pkgs.callPackage ../pkgs/agenix.nix {}).version;
    in
      ps.buildPythonPackage rec {
        inherit version;
        pname = "agenix_testing";
        src = ./.;
        format = "pyproject";
        propagatedBuildInputs = [ps.setuptools];
        postPatch = ''
          # Keep a default version makes for easy installation outside of
          # nix for debugging
          substituteInPlace pyproject.toml \
            --replace 'version = "0.1.0"' 'version = "${version}"'
        '';
      };
  in [agenixTesting];
  nodes.system1 = {
    config,
    pkgs,
    options,
    ...
  }: {
    imports = [
      ../modules/age.nix
      ./install_ssh_host_keys.nix
    ];

    services.openssh.enable = true;

    age.secrets.passwordfile-user1 = {
      file = ../example/passwordfile-user1.age;
    };

    age.identityPaths = options.age.identityPaths.default ++ ["/etc/ssh/this_key_wont_exist"];

    environment.systemPackages = [
      (pkgs.callPackage ../pkgs/agenix.nix {})
    ];

    users = {
      mutableUsers = false;

      users = {
        user1 = {
          isNormalUser = true;
          passwordFile = config.age.secrets.passwordfile-user1.path;
          uid = 1000;
        };
      };
    };
  };

  testScript = let
    user = "user1";
    password = "password1234";
  in ''
    # Skipping analyzing "agenix_testing": module is installed, but missing
    # library stubs or py.typed marker
    from agenix_testing import AgenixTester  # type: ignore
    tester = AgenixTester(system=system1, user="${user}", password="${password}")

    # Can still be used as before
    system1.send_chars("whoami > /tmp/1\n")
    # Or from `tester.system`
    tester.system.wait_for_file("/tmp/1")
    assert "${user}" in tester.system.succeed("cat /tmp/1")

    tester.run_all()
  '';
}
