"""Real encryption tests: consumer isolation, stable recovery, and no reinitialization."""
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
    "prepare_webui", Path(__file__).resolve().parents[1] / "scripts/prepare-webui.py")
module = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(module)


class WebUISecretsTest(unittest.TestCase):
    def test_consumers_and_existing_secrets(self):
        with tempfile.TemporaryDirectory() as directory:
            work = Path(directory)
            root = work / "checkout"
            (root / "scripts").mkdir(parents=True)
            (root / "secrets").mkdir()
            script = root / "scripts/prepare-webui.py"
            shutil.copyfile(module.__file__, script)
            operator, edge = work / "operator.key", work / "edge.key"
            real_run = subprocess.run
            for key in [operator, edge]:
                real_run(["age-keygen", "-o", str(key)], check=True, capture_output=True)
            edge_recipient = real_run(["age-keygen", "-y", str(edge)], check=True, capture_output=True).stdout
            (root / "secrets/edge.yaml").write_bytes(b"existing ciphertext must remain byte-identical")
            (root / ".sops.yaml").write_text('creation_rules:\n  - path_regex: "^secrets/edge\\\\.yaml$"\n    age: existing-public-recipient\n')
            machine = {}

            def transport(command, **kwargs):
                if command[0] != "incus":
                    return real_run(command, cwd=root, **kwargs)
                guest = command[2]
                action = command[command.index("--") + 1:]
                output = b""
                if action[0] == "test":
                    return subprocess.CompletedProcess(command, 0 if "key" in machine else 1, b"", b"")
                if action[0] == "cat":
                    output = edge_recipient if guest.endswith(":edge") else machine["recipient"]
                elif action[0] == "sh":
                    name = "recipient" if "recipient.txt" in action[-1] else "key"
                    self.assertNotIn(name, machine)
                    machine[name] = kwargs["input"]
                elif action[0] != "mountpoint":
                    raise AssertionError("Unexpected transport command")
                return subprocess.CompletedProcess(command, 0, output, b"")

            with patch.object(module, "__file__", str(script)), \
                 patch("sys.argv", ["prepare-webui.py", "test", "--operator-key", str(operator)]), \
                 patch("subprocess.run", side_effect=transport), patch("builtins.print"):
                module.main()
                with self.assertRaises(SystemExit):
                    module.main()
            self.assertEqual((root / "secrets/edge.yaml").read_bytes(), b"existing ciphertext must remain byte-identical")

            def decrypt(path, key):
                env = os.environ.copy()
                env.pop("SOPS_AGE_KEY_FILE", None)
                env["SOPS_AGE_KEY"] = key
                result = real_run(["sops", "--decrypt", "--output-type", "json", str(path)],
                                  capture_output=True, env=env)
                return result

            edge_path, webui_path = root / "secrets/edge-oidc.yaml", root / "secrets/open-webui.yaml"
            edge_doc = json.loads(decrypt(edge_path, edge.read_text()).stdout)
            webui_doc = json.loads(decrypt(webui_path, machine["key"].decode()).stdout)
            for path, expected in [(edge_path, edge_doc), (webui_path, webui_doc)]:
                self.assertEqual(json.loads(decrypt(path, operator.read_text()).stdout), expected)
                self.assertNotIn(expected[next(iter(expected))].encode(), path.read_bytes())
            self.assertNotEqual(decrypt(edge_path, machine["key"].decode()).returncode, 0)
            self.assertNotEqual(decrypt(webui_path, edge.read_text()).returncode, 0)
            values = dict(line.split("=", 1) for line in webui_doc["environment"].splitlines())
            self.assertTrue(module.PasswordHasher().verify(edge_doc["client"], values["OAUTH_CLIENT_SECRET"]))
            self.assertNotIn(values["OAUTH_CLIENT_SECRET"].encode(), edge_path.read_bytes())
            self.assertNotIn(values["OAUTH_CLIENT_SECRET"].encode(), webui_path.read_bytes())
            if os.environ.get("CI") == "true":
                # Synthetic ciphertext only; machine private keys die with the test directory.
                for source in [edge_path, webui_path]:
                    destination = Path(__file__).resolve().parents[1] / "secrets" / source.name
                    if not destination.exists():
                        destination.write_bytes(source.read_bytes())
                        real_run(["git", "add", str(destination)], check=True)


if __name__ == "__main__":
    unittest.main()
