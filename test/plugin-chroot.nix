{ pkgs }:
let
  inherit (pkgs) lib;
  # A real age plugin using only the repository's public fixture identity.
  # rage creates a temporary working directory before executing this binary.
  pluginSource = pkgs.writeText "agenix-fixture-plugin.go" ''
    package main

    import (
      "flag"
      "fmt"
      "os"
      "filippo.io/age"
      "filippo.io/age/agessh"
      "filippo.io/age/plugin"
    )

    func main() {
      if len(os.Args) == 1 {
        fmt.Println(plugin.EncodeIdentity("fixture", nil))
        return
      }
      p, err := plugin.New("fixture")
      if err != nil { panic(err) }
      p.RegisterFlags(nil)
      flag.Parse()
      p.HandleIdentity(func(_ []byte) (age.Identity, error) {
        if _, err := os.Stat("/run/agenix-plugin-fail"); err == nil {
          return nil, fmt.Errorf("requested fixture failure")
        }
        key, err := os.ReadFile("${../example_keys/system1}")
        if err != nil { return nil, err }
        // Record the actual plugin working directory and its parent TMPDIR.
        cwd, err := os.Getwd()
        if err != nil { return nil, err }
        err = os.WriteFile("/run/agenix-plugin-paths", []byte(os.Getenv("TMPDIR") + "\n" + cwd + "\n"), 0600)
        if err != nil { return nil, err }
        return agessh.ParseIdentity(key)
      })
      os.Exit(p.Main())
    }
  '';
  plugin = pkgs.age.overrideAttrs (old: {
    pname = "agenix-public-fixture-plugin";
    subPackages = [ "cmd/age-plugin-fixture" ];
    postPatch = (old.postPatch or "") + ''
      mkdir -p cmd/age-plugin-fixture
      cp ${pluginSource} cmd/age-plugin-fixture/main.go
    '';
    preInstall = "";
    doCheck = false;
    doInstallCheck = false;
  });
  identity = pkgs.runCommand "agenix-public-plugin-identity" { } ''
    ${plugin}/bin/age-plugin-fixture > "$out"
  '';
  verify = pkgs.writeShellApplication {
    name = "agenix-check-plugin-chroot";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.findutils
    ];
    text = ''
      test "$(cat /run/agenix/secret)" = hello
      mapfile -t paths < /run/agenix-plugin-paths
      [[ "''${paths[0]}" == /run/agenix.d/.plugin-tmp.* ]]
      [[ "''${paths[1]}" == "''${paths[0]}"/* ]]
      test ! -e "''${paths[0]}"
      test "$(stat -Lc %a /run/agenix/secret)" = 400
      test -z "$(find /run/agenix.d -name '.plugin-tmp.*')"
      touch /run/agenix-plugin-fail
      if "$1/activate"; then
        echo 'activation unexpectedly succeeded after plugin failure' >&2
        exit 1
      fi
      test -z "$(find /run/agenix.d -name '.plugin-tmp.*')"
      test "$(cat /run/agenix/secret)" = hello
    '';
  };
  target =
    (import (pkgs.path + "/nixos/lib/eval-config.nix") {
      system = pkgs.stdenv.hostPlatform.system;
      modules = [
        ../modules/age.nix
        {
          boot.isContainer = true;
          services.userborn.enable = false;
          systemd.sysusers.enable = false;
          system.stateVersion = lib.trivial.release;
          environment.systemPackages = [ verify ];
          age = {
            ageBin = "${pkgs.rage}/bin/rage";
            pluginPackages = [ plugin ];
            identityPaths = [ "${identity}" ];
            secrets.secret.file = ../example/secret1.age;
          };
        }
      ];
    }).config.system.build.toplevel;
in
pkgs.testers.nixosTest {
  name = "agenix-plugin-chroot";
  nodes.installer = {
    virtualisation.additionalPaths = [ target ];
    virtualisation.diskSize = 4096;
    environment.systemPackages = [ pkgs.nixos-install-tools ];
  };
  testScript = ''
    installer.wait_for_unit("multi-user.target")
    installer.succeed("mkdir -p /mnt/tmp.fixture")
    installer.succeed("nixos-install --root /mnt --system ${target} --no-bootloader --no-root-password --no-channel-copy", timeout=300)
    # nixos-enter activates the target before it clears the inherited TMPDIR.
    # That path exists in the installer but not inside the target's chroot.
    installer.fail("test -d /mnt/mnt/tmp.fixture")
    # Verify before leaving nixos-enter's private mount namespace: its ramfs
    # disappears with that namespace after the command exits.
    installer.succeed("TMPDIR=/mnt/tmp.fixture nixos-enter --root /mnt -c '${lib.getExe verify} ${target}' > /tmp/enter.log 2>&1")

    # Prove that the same rage/plugin pair fails with the original broken
    # environment: it must allocate a working directory before invoking it.
    installer.fail("chroot /mnt ${pkgs.coreutils}/bin/env TMPDIR=/mnt/tmp.fixture PATH=${plugin}/bin ${pkgs.rage}/bin/rage -d -i ${identity} ${../example/secret1.age} >/tmp/broken-output 2>/tmp/broken-error")
    installer.succeed("test ! -s /tmp/broken-output")
  '';
}
