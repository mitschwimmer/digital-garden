#!/usr/bin/env python3
"""Prepare only new OIDC/WebUI secrets; never rotate existing Authelia secrets."""
import argparse
import json
import os
from pathlib import Path
import re
import secrets
import subprocess
import tempfile

from argon2 import PasswordHasher
import yaml


def run(command, **kwargs):
    return subprocess.run(command, check=True, stdout=subprocess.PIPE,
                          stderr=subprocess.PIPE, **kwargs).stdout


def encrypt(document, recipients):
    return run(["sops", "--config", "/dev/null", "--encrypt", "--age", ",".join(recipients),
                "--input-type", "json", "--output-type", "yaml", "/dev/stdin"],
               input=json.dumps(document).encode())


def documents():
    client = secrets.token_hex(32)
    signing = run(["openssl", "genpkey", "-algorithm", "RSA",
                   "-pkeyopt", "rsa_keygen_bits:3072"]).decode()
    edge = {"hmac": secrets.token_hex(32), "signing": signing,
            "client": PasswordHasher().hash(client)}
    webui = {"environment": "WEBUI_SECRET_KEY=" + secrets.token_hex(32) +
             "\nOAUTH_CLIENT_SECRET=" + client + "\n"}
    return edge, webui


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("remote")
    parser.add_argument("--operator-key", type=Path,
                        default=Path.home() / ".config/digital-garden/operator.agekey")
    args = parser.parse_args()
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_.-]*", args.remote):
        parser.error("Invalid remote alias")
    root = Path(__file__).resolve().parent.parent
    operator = args.operator_key.expanduser().resolve()
    if operator.is_relative_to(root) or not operator.is_file():
        parser.error("Existing operator age key must be outside the repository")
    paths = [root / "secrets/edge-oidc.yaml", root / "secrets/open-webui.yaml"]
    if any(path.exists() for path in paths):
        parser.error("OIDC/WebUI ciphertext already exists; edit with SOPS, never reinitialize")
    policy_path = root / ".sops.yaml"
    policy = yaml.safe_load(policy_path.read_text())
    rules = policy["creation_rules"]
    operator_recipient = run(["age-keygen", "-y", str(operator)]).decode().strip()

    def guest(name, *command, **kwargs):
        return run(["incus", "exec", args.remote + ":" + name,
                    "--project", "default", "-T", "--", *command], **kwargs)

    for name in ["edge", "open-webui"]:
        guest(name, "mountpoint", "-q", "/var/lib/garden-secrets")
    edge_recipient = guest("edge", "cat", "/var/lib/garden-secrets/recipient.txt").decode().strip()
    exists = subprocess.run(["incus", "exec", args.remote + ":open-webui",
                             "--project", "default", "-T", "--", "test", "-s",
                             "/var/lib/garden-secrets/age.key"],
                            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    if exists.returncode not in (0, 1):
        raise RuntimeError("Cannot check WebUI identity")
    if exists.returncode == 1:
        with tempfile.TemporaryDirectory(prefix="garden-webui-age-") as directory:
            key = Path(directory) / "machine.agekey"
            run(["age-keygen", "-o", str(key)])
            recipient = run(["age-keygen", "-y", str(key)]).decode().strip()
            guest("open-webui", "sh", "-eu", "-c",
                  'umask 077; t=$(mktemp /var/lib/garden-secrets/.age.XXXXXX); '
                  'trap \'rm -f "$t"\' EXIT; cat > "$t"; '
                  'ln "$t" /var/lib/garden-secrets/age.key', input=key.read_bytes())
            guest("open-webui", "sh", "-eu", "-c",
                  "umask 077; cat > /var/lib/garden-secrets/recipient.txt",
                  input=(recipient + "\n").encode())
    else:
        recipient = guest("open-webui", "cat", "/var/lib/garden-secrets/recipient.txt").decode().strip()
    for public in [operator_recipient, edge_recipient, recipient]:
        if not re.fullmatch(r"age1[0-9a-z]+", public):
            raise ValueError("Invalid public recipient")
    generated = documents()
    recipients = [[operator_recipient, edge_recipient], [operator_recipient, recipient]]
    ciphertexts = [encrypt(doc, keys) for doc, keys in zip(generated, recipients)]
    env = os.environ.copy()
    env["SOPS_AGE_KEY_FILE"] = str(operator)
    for ciphertext, expected in zip(ciphertexts, generated):
        restored = json.loads(run(["sops", "--decrypt", "--input-type", "yaml",
                                  "--output-type", "json", "/dev/stdin"],
                                 input=ciphertext, env=env))
        if restored != expected:
            raise RuntimeError("Encrypted recovery check failed")
    # Existing rules and existing edge ciphertext are preserved.
    additions = [{"path_regex": r"^secrets/edge-oidc\.yaml$", "age": ",".join(recipients[0])},
                 {"path_regex": r"^secrets/open-webui\.yaml$", "age": ",".join(recipients[1])}]
    policy["creation_rules"] = additions + rules
    for path, ciphertext in zip(paths, ciphertexts):
        with path.open("xb") as stream:
            stream.write(ciphertext)
    temporary = policy_path.with_suffix(".yaml.tmp")
    temporary.write_text(yaml.safe_dump(policy, sort_keys=False))
    temporary.replace(policy_path)
    print("Prepared encrypted OIDC/WebUI configuration. Existing Authelia secrets were preserved.")
    print("Stage .sops.yaml, secrets/edge-oidc.yaml and secrets/open-webui.yaml before deployment.")


if __name__ == "__main__":
    try:
        main()
    except (ValueError, RuntimeError, subprocess.CalledProcessError) as error:
        raise SystemExit("Preparation failed (" + type(error).__name__ + "). No existing secrets were rotated.")
