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
    (
      umask u=rw,g=,o=
      cp ${../example_keys/user1-pq.age} /home/user1/.ssh/age.key
      chown $USER1_UID:$USERS_GID /home/user1/.ssh/age.key
    )
    cp -r "${../example}" /tmp/secrets
    chmod -R u+rw /tmp/secrets
    chown -R $USER1_UID:$USERS_GID /tmp/secrets

    # Create secrets.nix without post-quantum secrets for rekey test
    # The rekey test uses -i with only the ed25519 key, so it cannot decrypt
    # secrets encrypted only to the PQ key. Excluding PQ secrets here allows
    # the rekey test to succeed with just the ed25519 identity.
    cp /tmp/secrets/secrets.nix /tmp/secrets/secrets-rekey.nix
    sed -i '/secret-pq.age/,+3d' /tmp/secrets/secrets-rekey.nix
  '';
}
