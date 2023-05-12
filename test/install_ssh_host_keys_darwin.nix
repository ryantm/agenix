# Do not copy this! It is insecure. This is only okay because we are testing.
{
  system.activationScripts.extraUserActivation.text = ''
    echo "Installing system SSH host key"
    sudo cp ${../example_keys/system1.pub} /etc/ssh/ssh_host_ed25519_key.pub
    sudo cp ${../example_keys/system1} /etc/ssh/ssh_host_ed25519_key
    sudo chmod 644 /etc/ssh/ssh_host_ed25519_key.pub
    sudo chmod 600 /etc/ssh/ssh_host_ed25519_key

    echo "Installing user SSH host key"
    mkdir -p $HOME/.ssh
    cp ${../example_keys/user1.pub} $HOME/.ssh/id_ed25519.pub
    cp ${../example_keys/user1} $HOME/.ssh/id_ed25519
    chmod 644 $HOME/.ssh/id_ed25519.pub
    chmod 600 $HOME/.ssh/id_ed25519
  '';
}
