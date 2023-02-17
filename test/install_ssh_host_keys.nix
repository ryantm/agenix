# Do not copy this! It is insecure. This is only okay because we are testing.
{
  system.activationScripts.agenixInstall.deps = ["installSSHHostKeys"];

  system.activationScripts.installSSHHostKeys.text = ''
    mkdir -p /etc/ssh /home/user1/.ssh
    (
      umask u=rw,g=r,o=r
      cp ${../example_keys/system1.pub} /etc/ssh/ssh_host_ed25519_key.pub
      cp ${../example_keys/user1.pub} /home/user1/.ssh/id_ed25519.pub
    )
    (
      umask u=rw,g=,o=
      cp ${../example_keys/system1} /etc/ssh/ssh_host_ed25519_key
      cp ${../example_keys/user1} /home/user1/.ssh/id_ed25519
      touch /etc/ssh/ssh_host_rsa_key
    )
  '';
}
