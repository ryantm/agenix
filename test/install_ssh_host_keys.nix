# Do not copy this! It is insecure. This is only okay because we are testing.
{ config, ... }:
{
  system.activationScripts.agenixInstall.deps = [ "installSSHHostKeys" ];

  system.activationScripts.installSSHHostKeys.text = ''
    USER1_UID="${toString config.users.users.user1.uid}"
    USERS_GID="${toString config.users.groups.users.gid}"

    mkdir -p /etc/ssh /home/user1/.ssh
    chown $USER1_UID:$USERS_GID /home/user1/.ssh
    (
      umask u=rw,g=r,o=r
      cp ${../example_keys/system1.pub} /etc/ssh/ssh_host_ed25519_key.pub
      cp ${../example_keys/user1.pub} /home/user1/.ssh/id_ed25519.pub
      chown $USER1_UID:$USERS_GID /home/user1/.ssh/id_ed25519.pub
    )
    (
      umask u=rw,g=,o=
      cp ${../example_keys/system1} /etc/ssh/ssh_host_ed25519_key
      cp ${../example_keys/user1} /home/user1/.ssh/id_ed25519
      chown $USER1_UID:$USERS_GID /home/user1/.ssh/id_ed25519
      touch /etc/ssh/ssh_host_rsa_key
    )
    cp -r "${../example}" /tmp/secrets
    chmod -R u+rw /tmp/secrets
    chown -R $USER1_UID:$USERS_GID /tmp/secrets
  '';
}
