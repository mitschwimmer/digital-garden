#!/usr/bin/env python3
"""Initialize encrypted Authelia inputs; never send plaintext through OpenTofu."""
import argparse
import getpass
import json
import os
from pathlib import Path
import re
import secrets
import subprocess
import tempfile

from argon2 import PasswordHasher


def run(args, **kwargs):
    return subprocess.run(args, check=True, stdout=subprocess.PIPE,
                          stderr=subprocess.PIPE, **kwargs).stdout


def prompt(label, pattern=None):
    value = input(label + ": ").strip()
    if not value or (pattern and not re.fullmatch(pattern, value)):
        raise ValueError("Invalid input for " + label)
    return value


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("remote", help="Authenticated Incus remote alias")
    parser.add_argument("--operator-key", type=Path,
                        default=Path.home() / ".config/digital-garden/operator.agekey")
    args = parser.parse_args()
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_.-]*", args.remote):
        parser.error("Invalid remote alias")
    root = Path(__file__).resolve().parent.parent
    encrypted = root / "secrets/edge.yaml"
    policy = root / ".sops.yaml"
    if encrypted.exists() or policy.exists():
        parser.error("Existing secrets/policy: edit with SOPS; initialization never rotates keys.")
    target = args.remote + ":edge"

    def guest(*command, **kwargs):
        return run(["incus", "exec", target, "--project", "default", "-T", "--",
                    *command], **kwargs)

    for mount in ["/var/lib/garden-secrets", "/var/lib/authelia-main"]:
        guest("mountpoint", "-q", mount)
    username = prompt("Initial login username", r"[a-z][a-z0-9_-]{0,31}")
    displayname = prompt("Display name")
    email = prompt("Your email address", r"[^@\s]+@[^@\s]+\.[^@\s]+")
    password = getpass.getpass("New Authelia password (at least 12 characters): ")
    if len(password) < 12 or password != getpass.getpass("Confirm password: "):
        raise ValueError("Passwords must match and contain at least 12 characters")
    smtp_address = prompt("SMTP address (submission://host:587 or submissions://host:465)",
                          r"submissions?://[A-Za-z0-9.-]+:(587|465)")
    smtp_username = prompt("SMTP username")
    smtp_sender = prompt("SMTP sender email", r"[^@\s]+@[^@\s]+\.[^@\s]+")
    smtp_password = getpass.getpass("SMTP password/app password: ")
    if not smtp_password:
        raise ValueError("An SMTP password is required")

    operator_key = args.operator_key.expanduser().resolve()
    if operator_key.is_relative_to(root):
        raise ValueError("Private operator key must be outside the repository")
    operator_key.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    if not operator_key.exists():
        run(["age-keygen", "-o", str(operator_key)])
    os.chmod(operator_key, 0o600)
    operator_recipient = run(["age-keygen", "-y", str(operator_key)]).decode().strip()

    # Persist the machine identity exactly once; keep it independent of the root image.
    exists = subprocess.run(["incus", "exec", target, "--project", "default", "-T", "--",
                             "test", "-s", "/var/lib/garden-secrets/age.key"],
                            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    if exists.returncode not in (0, 1):
        raise RuntimeError("Cannot check guest identity")
    if exists.returncode == 1:
        with tempfile.TemporaryDirectory(prefix="garden-age-") as directory:
            key = Path(directory) / "edge.agekey"
            run(["age-keygen", "-o", str(key)])
            machine_recipient = run(["age-keygen", "-y", str(key)]).decode().strip()
            guest("sh", "-eu", "-c",
                  'umask 077; t=$(mktemp /var/lib/garden-secrets/.age.XXXXXX); '
                  'trap \'rm -f "$t"\' EXIT; cat > "$t"; '
                  'ln "$t" /var/lib/garden-secrets/age.key',
                  input=key.read_bytes())
            guest("sh", "-eu", "-c",
                  "umask 077; cat > /var/lib/garden-secrets/recipient.txt",
                  input=(machine_recipient + "\n").encode())
    else:
        machine_recipient = guest("cat", "/var/lib/garden-secrets/recipient.txt").decode().strip()
    for recipient in (operator_recipient, machine_recipient):
        if not re.fullmatch(r"age1[0-9a-z]+", recipient):
            raise ValueError("Invalid age public recipient")

    users = {"users": {username: {
        "displayname": displayname,
        "password": PasswordHasher(time_cost=3, memory_cost=65536, parallelism=4).hash(password),
        "email": email, "groups": ["admins"],
    }}}
    smtp = {"notifier": {"smtp": {
        "address": smtp_address, "username": smtp_username,
        "password": smtp_password, "sender": smtp_sender,
        "startup_check_address": email,
    }}}
    document = {
        "jwt": secrets.token_hex(32), "session": secrets.token_hex(32),
        "storage": secrets.token_hex(32),
        "users": json.dumps(users), "smtp": json.dumps(smtp),
    }
    plaintext = json.dumps(document).encode()
    ciphertext = run(["sops", "--encrypt", "--age",
                      operator_recipient + "," + machine_recipient,
                      "--input-type", "json", "--output-type", "yaml", "/dev/stdin"],
                     input=plaintext)
    env = os.environ.copy()
    env["SOPS_AGE_KEY_FILE"] = str(operator_key)
    recovered = run(["sops", "--decrypt", "--input-type", "yaml", "--output-type",
                     "json", "/dev/stdin"], input=ciphertext, env=env)
    if json.loads(recovered) != document:
        raise RuntimeError("Encrypted round-trip failed")
    encrypted.parent.mkdir(exist_ok=True)
    with encrypted.open("xb") as handle:
        handle.write(ciphertext)
    with policy.open("x") as handle:
        handle.write("creation_rules:\n  - path_regex: ^secrets/edge\\.yaml$\n"
                     "    age: " + operator_recipient + "," + machine_recipient + "\n")
    print("Created SOPS ciphertext and public recipient policy.")
    print("Back up your private operator key securely:", operator_key)
    print("Stage only: git add secrets/edge.yaml .sops.yaml")


if __name__ == "__main__":
    try:
        main()
    except (ValueError, RuntimeError, subprocess.CalledProcessError) as error:
        # Subprocess stderr can contain sensitive inputs; never echo it.
        raise SystemExit("Preparation failed (" + type(error).__name__ +
                         "). No existing secrets were rotated.") from None
