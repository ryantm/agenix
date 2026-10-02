# Do not copy this! It is insecure. This is only okay because we are testing.
{
  # nix-darwin 26.05 runs activation as root, including this test setup.
  system.activationScripts.preActivation.text = ''
    echo "Installing system SSH host key"
    cp ${../example_keys/system1.pub} /etc/ssh/ssh_host_ed25519_key.pub
    cp ${../example_keys/system1} /etc/ssh/ssh_host_ed25519_key
    chmod 644 /etc/ssh/ssh_host_ed25519_key.pub
    chmod 600 /etc/ssh/ssh_host_ed25519_key

    echo "Installing user SSH host key"
    runner_home=$(dscl . -read /Users/runner NFSHomeDirectory | cut -d ' ' -f 2)
    mkdir -p "$runner_home/.ssh"
    cp ${../example_keys/user1.pub} "$runner_home/.ssh/id_ed25519.pub"
    cp ${../example_keys/user1} "$runner_home/.ssh/id_ed25519"
    chmod 644 "$runner_home/.ssh/id_ed25519.pub"
    chmod 600 "$runner_home/.ssh/id_ed25519"
    chown -R runner "$runner_home/.ssh"
  '';
}
