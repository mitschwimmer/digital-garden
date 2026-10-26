"""Regression tests for the cross-system deployment failure and fail-closed ordering."""
import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch, MagicMock

spec = importlib.util.spec_from_file_location("activation", Path(__file__).parents[1] / "operations/activate.py")
a = importlib.util.module_from_spec(spec)
spec.loader.exec_module(a)
CLOSURE = "/nix/store/" + "a" * 32 + "-nixos-system-edge"
TARGET = {"system": "edge", "project": "default", "instance": "edge", "remote": "lab",
          "mounts": ["/var/lib/caddy"], "units": ["caddy"]}


class ActivationTests(unittest.TestCase):
    def test_wrong_local_closure_rejected(self):
        with patch.object(Path, "read_text", return_value="identity\n"):
            with self.assertRaisesRegex(RuntimeError, "Closure identity"):
                a.check_local(TARGET, CLOSURE)

    def test_missing_metadata_rejected(self):
        with patch.object(a, "run", return_value="") as run:
            with self.assertRaisesRegex(RuntimeError, "metadata"):
                a.activate(TARGET, CLOSURE)
        self.assertEqual(run.call_count, 1)

    def test_wrong_remote_closure_never_changes_profile(self):
        calls = []
        def command(*args):
            calls.append(args)
            if args[:3] == ("incus", "config", "get"):
                return "edge"
            if "cat" in args:
                return "identity"
            return ""
        with patch.object(a, "run", side_effect=command):
            with self.assertRaisesRegex(RuntimeError, "Remote closure identity"):
                a.activate(TARGET, CLOSURE)
        self.assertFalse(any("nix-env" in c for c in calls))

    def test_missing_mount_never_changes_profile(self):
        def command(*args):
            if "mountpoint" in args:
                raise subprocess.CalledProcessError(1, args)
            return "edge"
        with patch.object(a, "run", side_effect=command) as run:
            with self.assertRaises(subprocess.CalledProcessError):
                a.activate(TARGET, CLOSURE)
        self.assertFalse(any("nix-env" in c.args for c in run.call_args_list))

    def test_correct_closure_checks_before_profile_and_switch(self):
        calls = []
        def command(*args):
            calls.append(args)
            if args[:3] == ("incus", "config", "get") or "cat" in args:
                return "edge"
            if "readlink" in args:
                return CLOSURE
            return ""
        def switch(args, **kwargs):
            calls.append(tuple(args))
        with patch.object(a, "run", side_effect=command), patch.object(a.subprocess, "run", side_effect=switch):
            a.activate(TARGET, CLOSURE)
        index = lambda token: next(i for i, c in enumerate(calls) if token in c)
        self.assertLess(index("cat"), index("nix-env"))
        self.assertLess(index("mountpoint"), index("nix-env"))
        self.assertLess(index("nix-env"), index("switch"))
        self.assertLess(index("switch"), index("readlink"))
        self.assertTrue(all("lab:edge" in c and "default" in c for c in calls))

    def test_transfer_requires_both_commands_to_succeed(self):
        for exporter, importer in [(1, 0), (0, 1)]:
            with self.subTest(exporter=exporter, importer=importer):
                process = MagicMock()
                process.__enter__.return_value = process
                process.wait.return_value = exporter
                with patch.object(a, "run", return_value=CLOSURE), \
                     patch.object(a.subprocess, "Popen", return_value=process), \
                     patch.object(a.subprocess, "run", return_value=MagicMock(returncode=importer)):
                    with self.assertRaisesRegex(RuntimeError, "transfer failed"):
                        a.transfer(TARGET, CLOSURE)

    def test_other_roots_applied_target_rejected(self):
        root = a.REPO / "systems/edge"
        other = dict(TARGET, system="identity", instance="identity", project="identity")
        with patch.dict(a.os.environ, {}, clear=True), \
             patch.object(a, "run", side_effect=["default", json.dumps(other)]):
            with self.assertRaisesRegex(RuntimeError, "differs"):
                a.target(root)

    def test_nondefault_workspace_rejected(self):
        with patch.dict(a.os.environ, {}, clear=True), patch.object(a, "run", return_value="other"):
            with self.assertRaisesRegex(RuntimeError, "default workspace"):
                a.target(a.REPO / "systems/edge")

    def test_ambient_state_override_rejected(self):
        with patch.dict(a.os.environ, {"TF_DATA_DIR": "/somewhere"}, clear=True):
            with self.assertRaisesRegex(RuntimeError, "TF_"):
                a.target(a.REPO / "systems/edge")

    def test_record_uses_running_closure_after_failed_profile_selection(self):
        selected = "/nix/store/" + "b" * 32 + "-failed-system"
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / ".operations").mkdir()
            def command(*args):
                if args[0:2] == ("nix", "build"):
                    return json.dumps([{"outputs": {"out": CLOSURE}}])
                if "/run/current-system" in args:
                    return CLOSURE
                if "/nix/var/nix/profiles/system" in args:
                    return selected
                return "revision"
            with patch.object(a, "target", return_value=TARGET), \
                 patch.object(a, "preflight"), patch.object(a, "check_local"), \
                 patch.object(a, "transfer"), patch.object(a, "activate"), \
                 patch.object(a, "run", side_effect=command):
                a.operation(root, SimpleNamespace(action="deploy"))
            record = json.loads(next((root / ".operations").glob("*/deployment.json")).read_text())
            self.assertEqual(record["previous"], CLOSURE)
            self.assertEqual(record["selected_profile"], selected)

    def test_build_mismatch_stops_before_transfer(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / ".operations").mkdir()
            with patch.object(a, "target", return_value=TARGET), \
                 patch.object(a, "preflight"), \
                 patch.object(a, "run", return_value=json.dumps([{"outputs": {"out": CLOSURE}}])), \
                 patch.object(a, "check_local", side_effect=RuntimeError("Closure identity mismatch")), \
                 patch.object(a, "transfer") as transfer, patch.object(a, "activate") as activate:
                with self.assertRaisesRegex(RuntimeError, "identity"):
                    a.operation(root, SimpleNamespace(action="deploy"))
            transfer.assert_not_called()
            activate.assert_not_called()

    def test_invalid_store_paths_rejected(self):
        for path in ["result", CLOSURE + "/bin/tool", CLOSURE + "\n" + CLOSURE, "--option"]:
            with self.subTest(path=path), self.assertRaises(RuntimeError):
                a.store_path(path)


if __name__ == "__main__":
    unittest.main()
