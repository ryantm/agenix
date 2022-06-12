let
  user1 = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIL0idNvgGiucWgup/mP78zyC23uFjYq0evcWdjGQUaBH";
  system1 = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPJDyIr/FSz1cJdcoW69R+NrWzwGK/+3gJpqD1t8L2zE";
in
{
  "secret1.age".publicKeys = [ user1 system1 ];
  "secret1-copy.age".publicKeys = [ user1 system1 ];
  "secret2.age".publicKeys = [ user1 ];
  "passwordfile-user1.age".publicKeys = [ user1 system1 ];
}
