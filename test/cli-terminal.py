import errno
import fcntl
import os
import pathlib
import pty
import select
import signal
import subprocess
import sys
import termios
import time

agenix, identity = sys.argv[1:]
ciphertext = pathlib.Path("secret.age").read_bytes()


def run(cancel, controlling=True):
    master, slave = pty.openpty()
    initial = termios.tcgetattr(slave)

    def terminal_session():
        os.setsid()
        if controlling:
            fcntl.ioctl(0, termios.TIOCSCTTY, 0)

    proc = subprocess.Popen(
        [agenix, "-e" if cancel else "-d", "secret.age", "-i", identity],
        stdin=slave, stdout=slave, stderr=slave, preexec_fn=terminal_session,
    )
    output = b""
    answered = False
    deadline = time.monotonic() + 30
    try:
        while proc.poll() is None and time.monotonic() < deadline:
            readable, _, _ = select.select([master], [], [], 0.1)
            if readable:
                try:
                    output += os.read(master, 65536)
                except OSError as error:
                    if error.errno != errno.EIO:
                        raise
            if not answered and b"Enter passphrase" in output:
                # The prompt is printed just before age disables terminal echo.
                if termios.tcgetattr(slave)[3] & termios.ECHO:
                    continue
                if cancel and not controlling:
                    os.killpg(proc.pid, signal.SIGINT)
                else:
                    os.write(master, b"\x03" if cancel else b"fixture-passphrase\n")
                answered = True
        assert answered, output
        assert proc.poll() is not None, output
        assert proc.returncode != 0 if cancel else proc.returncode == 0, output
        assert termios.tcgetattr(slave) == initial, "terminal state was not restored"
        assert pathlib.Path("secret.age").read_bytes() == ciphertext
    finally:
        if proc.poll() is None:
            os.killpg(proc.pid, signal.SIGKILL)
            proc.wait()
        termios.tcsetattr(slave, termios.TCSANOW, initial)
        os.close(master)
        os.close(slave)


run(cancel=True)
run(cancel=True, controlling=False)
run(cancel=False)

# A background command can inspect its controlling terminal, but attempting to
# change its settings would stop the job with SIGTTOU. Leave unchanged state alone.
master, slave = pty.openpty()


def terminal_session():
    os.setsid()
    fcntl.ioctl(0, termios.TIOCSCTTY, 0)


helper = r'''
import os, signal, subprocess, sys
proc = subprocess.Popen([sys.argv[1], "--check"], stdin=subprocess.DEVNULL,
                        stdout=subprocess.PIPE, stderr=subprocess.PIPE, process_group=0)
try:
    output, error = proc.communicate(timeout=15)
    assert proc.returncode == 0, error
finally:
    try:
        os.killpg(proc.pid, signal.SIGKILL)
    except ProcessLookupError:
        pass
'''
try:
    result = subprocess.run([sys.executable, "-c", helper, agenix], stdin=slave,
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                            preexec_fn=terminal_session, timeout=20)
    assert result.returncode == 0, result.stderr
finally:
    os.close(master)
    os.close(slave)
