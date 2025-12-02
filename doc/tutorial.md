# Tutorial {#tutorial}

1. The system you want to deploy secrets to should already exist and
   have `sshd` running on it so that it has generated SSH host keys in
   `/etc/ssh/`.

2. Make a directory to store secrets and `secrets.nix` file for listing secrets and their public keys (This file is **not** imported into your NixOS configuration. It is only used for the `agenix` CLI.):

   ```ShellSession
   $ mkdir secrets
   $ cd secrets
   $ touch secrets.nix
   ```
3. Add public keys to `secrets.nix` file (hint: use `ssh-keyscan` or GitHub (for example, https://github.com/ryantm.keys)):
   ```nix
   let
     user1 = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIL0idNvgGiucWgup/mP78zyC23uFjYq0evcWdjGQUaBH";
     user2 = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILI6jSq53F/3hEmSs+oq9L4TwOo1PrDMAgcA1uo1CCV/";
     users = [ user1 user2 ];

     system1 = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPJDyIr/FSz1cJdcoW69R+NrWzwGK/+3gJpqD1t8L2zE";
     system2 = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKzxQgondgEYcLpcPdJLrTdNgZ2gznOHCAxMdaceTUT1";
     systems = [ system1 system2 ];
   in
   {
     "secret1.age".publicKeys = [ user1 system1 ];
     "secret2.age".publicKeys = users ++ systems;
     "armored-secret.age" = {
       publicKeys = [ user1 ];
       armor = true;
     };
   }
   ```
4. Edit secret files (these instructions assume your SSH private key is in ~/.ssh/):
   ```ShellSession
   $ agenix -e secret1.age
   ```
5. Add secret to a NixOS module config:
   ```nix
   {
     age.secrets.secret1.file = ../secrets/secret1.age;
   }
   ```
6. Use the secret in your config:
   ```nix
   {
     users.users.user1 = {
       isNormalUser = true;
       hashedPasswordFile = config.age.secrets.secret1.path;
     };
   }
   ```
7. NixOS rebuild or use your deployment tool like usual.

   The secret will be decrypted to the value of `config.age.secrets.secret1.path` (`/run/agenix/secret1` by default).
