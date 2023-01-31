# Do not copy this! It is insecure. This is only okay because we are testing.
{
  system.activationScripts.extraUserActivation.text = ''
    echo "Installing SSH host key"
    sudo cp ${../example_keys/system1.pub} /etc/ssh/ssh_host_ed25519_key.pub
    sudo cp ${../example_keys/system1} /etc/ssh/ssh_host_ed25519_key
    sudo chmod 644 /etc/ssh/ssh_host_ed25519_key.pub
    sudo chmod 600 /etc/ssh/ssh_host_ed25519_key
  '';
}
