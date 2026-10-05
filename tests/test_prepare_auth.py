"""Exercise real age/SOPS encryption against a mocked Incus transport."""
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location(
    "prepare_auth", Path(__file__).resolve().parents[1] / "scripts/prepare-auth.py")
module = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(module)


class PrepareAuthTest(unittest.TestCase):
    def test_encryption_recovery_and_no_rotation(self):
        with tempfile.TemporaryDirectory() as directory:
            work = Path(directory)
            root = work / "checkout"
            (root / "scripts").mkdir(parents=True)
            script = root / "scripts/prepare-auth.py"
            shutil.copyfile(module.__file__, script)
            operator = work / "operator.agekey"
            machine = {}
            real_run = subprocess.run

            def transport(args, **kwargs):
                if args[0] != "incus":
                    # Keep real repository SOPS policies out of this isolated test.
                    return real_run(args, cwd=root, **kwargs)
                command = args[args.index("--") + 1:]
                if command[0] == "mountpoint":
                    return subprocess.CompletedProcess(args, 0, b"", b"")
                if command[0] == "test":
                    return subprocess.CompletedProcess(args, 0 if "key" in machine else 1, b"", b"")
                if command[0] == "sh":
                    if "recipient.txt" in command[-1]:
                        machine["recipient"] = kwargs["input"]
                    else:
                        if "key" in machine:
                            raise RuntimeError("Identity would be overwritten")
                        machine["key"] = kwargs["input"]
                    return subprocess.CompletedProcess(args, 0, b"", b"")
                if command[0] == "cat":
                    return subprocess.CompletedProcess(args, 0, machine["recipient"], b"")
                raise RuntimeError("Unexpected Incus operation")

            answers = ["henner", "Test Operator", "operator@example.invalid",
                       "submission://smtp.example.invalid:587", "smtp-user",
                       "sender@example.invalid"]
            passwords = ["a-test-password-long-enough", "a-test-password-long-enough",
                         "a-test-smtp-password"]
            with patch.object(module, "__file__", str(script)), \
                 patch("sys.argv", ["prepare-auth.py", "test", "--operator-key", str(operator)]), \
                 patch("builtins.input", side_effect=answers), \
                 patch("getpass.getpass", side_effect=passwords), \
                 patch("subprocess.run", side_effect=transport), patch("builtins.print"):
                module.main()
                with self.assertRaises(SystemExit):
                    module.main()  # Existing ciphertext must block regeneration.

            ciphertext = (root / "secrets/edge.yaml").read_bytes()
            for value in answers + passwords:
                self.assertTrue(value.encode() not in ciphertext)
            if os.environ.get("GARDEN_CI_FIXTURE") == "1" and os.environ.get("CI") == "true":
                destination = Path(__file__).resolve().parents[1] / "secrets/edge.yaml"
                if not destination.exists():
                    destination.write_bytes(ciphertext)
                    real_run(["git", "add", "secrets/edge.yaml"], check=True)
            env = os.environ.copy()
            env["SOPS_AGE_KEY_FILE"] = str(operator)
            operator_doc = json.loads(real_run(
                ["sops", "--decrypt", "--output-type", "json", str(root / "secrets/edge.yaml")],
                check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=env).stdout)
            env.pop("SOPS_AGE_KEY_FILE")
            env["SOPS_AGE_KEY"] = machine["key"].decode()
            machine_doc = json.loads(real_run(
                ["sops", "--decrypt", "--output-type", "json", str(root / "secrets/edge.yaml")],
                check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=env).stdout)
            self.assertTrue(operator_doc == machine_doc)
            users = json.loads(operator_doc["users"])["users"]
            self.assertTrue(module.PasswordHasher().verify(
                users["henner"]["password"], passwords[0]))
            self.assertTrue(operator.stat().st_mode & 0o777 == 0o600)


if __name__ == "__main__":
    unittest.main()
