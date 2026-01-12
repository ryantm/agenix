# Do not copy this! It is insecure. This is only okay because we are testing.
{
  system.activationScripts.postActivation.text = ''
    echo "Installing system SSH host key"
    cp ${../example_keys/system1.pub} /etc/ssh/ssh_host_ed25519_key.pub
    cp ${../example_keys/system1} /etc/ssh/ssh_host_ed25519_key
    chmod 644 /etc/ssh/ssh_host_ed25519_key.pub
    chmod 600 /etc/ssh/ssh_host_ed25519_key

    echo "Installing user SSH host key"
    USER_HOME="/Users/runner"
    sudo -u runner mkdir -p "$USER_HOME/.ssh"
    sudo -u runner cp ${../example_keys/user1.pub} "$USER_HOME/.ssh/id_ed25519.pub"
    sudo -u runner cp ${../example_keys/user1} "$USER_HOME/.ssh/id_ed25519"
    sudo -u runner chmod 644 "$USER_HOME/.ssh/id_ed25519.pub"
    sudo -u runner chmod 600 "$USER_HOME/.ssh/id_ed25519"
  '';
}
