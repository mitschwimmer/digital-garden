import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location(
    "configure_llama", Path(__file__).resolve().parents[1] / "scripts/configure-llama.py")
module = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(module)


class GPULocalInputsTest(unittest.TestCase):
    def test_selection_and_ambiguity(self):
        cards = [{"vendor_id": "8086", "pci_address": "0000:00:02.0"},
                 {"vendor_id": "1002", "pci_address": "0000:01:00.0"}]
        self.assertEqual(module.select(cards), "0000:01:00.0")
        with self.assertRaises(ValueError):
            module.select(cards, "0000:00:02.0")
        cards.append({"vendor_id": "1002", "pci_address": "0000:02:00.0"})
        with self.assertRaises(ValueError):
            module.select(cards)
        self.assertEqual(module.select(cards, "0000:02:00.0"), "0000:02:00.0")

    def test_preserve_seed_and_lan_inputs(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "scripts").mkdir()
            (root / "tofu").mkdir()
            path = root / "tofu/site.auto.tfvars.json"
            previous = {"incus_remote": "test", "image_directory": "/nix/store/existing-seed",
                        "edge_lan_parent": "test0", "edge_lan_mac": "02:00:00:00:00:01"}
            path.write_text(json.dumps(previous))
            resources = {"gpu": {"cards": [{"vendor_id": "1002", "pci_address": "0000:01:00.0"}]}}
            response = subprocess.CompletedProcess([], 0, json.dumps(resources).encode())
            with patch.object(module, "__file__", str(root / "scripts/configure-llama.py")), \
                 patch("sys.argv", ["configure-llama.py", "test"]), \
                 patch("subprocess.run", return_value=response), patch("builtins.print"):
                module.main()
                module.main()
            self.assertEqual(json.loads(path.read_text()), previous | {"llama_gpu_pci": "0000:01:00.0"})


if __name__ == "__main__":
    unittest.main()
