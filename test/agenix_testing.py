"""Provide a class and helper methods for agenix integration tests."""


import typing as t

T = t.TypeVar("T", str, list[str])


class AgenixTester:
    """Provide a class to help reduce repetition in setup."""

    def __init__(self, system, user, password) -> None:
        """Necessary setup can be put here."""
        self.system = system
        self.user = user
        self.password = password
        self.setup()

    def login(self) -> None:
        """Start with the common login function."""
        self.system.wait_for_unit("multi-user.target")
        self.system.wait_until_succeeds("pgrep -f 'agetty.*tty1'")
        self.system.sleep(2)
        self.system.send_key("alt-f2")
        self.system.wait_until_succeeds("[ $(fgconsole) = 2 ]")
        self.system.wait_for_unit("getty@tty2.service")
        self.system.wait_until_succeeds("pgrep -f 'agetty.*tty2'")
        self.system.wait_until_tty_matches("2", "login: ")
        self.system.send_chars(f"{self.user}\n")
        self.system.wait_until_tty_matches("2", f"login: {self.user}")
        self.system.wait_until_succeeds("pgrep login")
        self.system.sleep(2)
        self.system.send_chars(f"{self.password}\n")

    def setup(self) -> None:
        """Run common setup code."""
        self.login()

    def user_succeed(
        self,
        cmds: T,
        directory: str | None = None,
        debug: bool = False,
    ) -> T:
        """Run cmds as `self.user`, optionally in a specified directory.

        For convenience, if cmds is a sequence, returns output as a list of
        outputs corresponding with each line in cmds. if cmds is a string,
        returns output as a string.
        """
        context: list[str] = [
            "set -Eeu -o pipefail",
            "shopt -s inherit_errexit",
        ]
        if debug:
            context.append("set -x")

        if directory:
            context.append(f"cd {directory}")

        if isinstance(cmds, str):
            commands_str = "\n".join([*context, cmds])
            final_command = f"sudo -u {self.user} -- bash -c '{commands_str}'"
            return self.system.succeed(final_command)

        results: list[str] = []
        for cmd in cmds:
            commands_str = "\n".join([*context, cmd])
            final_command = f"sudo -u {self.user} -- bash -c '{commands_str}'"
            result = self.system.succeed(final_command)
            results.append(result.strip())
        return t.cast(T, results)

    def run_all(self) -> None:
        self.test_rekeying()
        self.test_user_edit()

    def test_decrypt(self):
        """User can get data out to stdout."""
        contents = self.system.succeed("cat /run/agenix/passwordfile-user1")

        # Make sure we got something back
        assert len(contents) > 0

        user_decrypted = self.user_succeed("agenix -d passwordfile-user1.age")

        assert contents == user_decrypted

    def test_rekeying(self) -> None:
        """Ensure we can rekey a file and its hash changes."""

        before_hash, _, after_hash = self.user_succeed(
            [
                "sha256sum passwordfile-user1.age",
                f"agenix -r -i /home/{self.user}/.ssh/id_ed25519",
                "sha256sum passwordfile-user1.age",
            ],
            directory="/tmp/secrets",
        )

        # Ensure we actually have hashes
        for line in [before_hash, after_hash]:
            h = line.split()
            assert len(h) == 2, f"hash should be [hash, filename], got {h}"
            assert h[1] == "passwordfile-user1.age", "filename is incorrect"
            assert len(h[0].strip()) == 64, "hash length is incorrect"
        assert (
            before_hash[0] != after_hash[0]
        ), "hash did not change with rekeying"

    def test_user_edit(self):
        """Ensure user1 can edit passwordfile-user1.age."""
        self.user_succeed(
            "EDITOR=cat agenix -e passwordfile-user1.age",
            directory="/tmp/secrets",
        )

        self.user_succeed("echo bogus > ~/.ssh/id_rsa")

        # Cannot edit with bogus default id_rsa
        self.system.fail(
            f"sudo -u {self.user} -- bash -c '"
            "cd /tmp/secrets; "
            "EDITOR=cat agenix -e /tmp/secrets/passwordfile-user1.age; "
            "'"
        )

        # user1 can still edit if good identity specified
        *_, pw = self.user_succeed(
            [
                (
                    "EDITOR=cat agenix -e passwordfile-user1.age "
                    "-i /home/user1/.ssh/id_ed25519"
                ),
                "rm ~/.ssh/id_rsa",
                "echo 'secret1234' | agenix -e passwordfile-user1.age",
                "EDITOR=cat agenix -e passwordfile-user1.age",
            ],
            directory="/tmp/secrets",
        )
        assert pw == "secret1234", f"password didn't match, got '{pw}'"

    def test_user_piping_data(self):
        """User can edit secrets by piping in data."""

        self.user_succeed(
            "echo 'secret1234' | agenix -e passwordfile-user1.age"
        )

        assert "secret1234" == self.user_succeed(
            "agenix -d passwordfile-user1.age"
        )

        # finally, the plain text should not linger around anywhere in the
        # filesystem
        self.system.fail("grep -r secret1234 /tmp")
