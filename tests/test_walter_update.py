import copy
import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location("walter_update", Path(__file__).parents[1] / "operations/update_walter.py")
updater = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(updater)

OLD = dict(repository="mitschwimmer/walter", digest="sha256:" + "1" * 64,
           revision="a" * 40, platform="linux/amd64", publication="old")
NEW = dict(repository="mitschwimmer/walter", digest="sha256:" + "2" * 64,
           revision="b" * 40, platform="linux/amd64",
           publication="https://github.com/mitschwimmer/walter/actions/runs/123")
INPUTS = dict(start=True, incus_remote="test", storage_pool="local")
INSTANCE = dict(name="walter", project="ai", remote="test", running=True,
                image=updater.image_reference(OLD), config={"oci.uid": "65532"}, device=[])
RESOURCES = [dict(address=updater.IMAGE, mode="managed", values=INSTANCE)] + [
    dict(address="incus_storage_volume." + name, mode="managed",
         values=dict(name="walter-" + volume, pool="local", project="ai", remote="test"))
    for name, volume in [("data", "data"), ("secrets", "secrets")]
]
GUEST = dict(name="walter", status="Running", expanded_devices={
    "data": dict(source="walter-data", pool="local", path="/data"),
    "secrets": dict(source="walter-secrets", pool="local", path="/run/secrets", readonly="true"),
})


def plan():
    after = dict(INSTANCE, image=updater.image_reference(NEW))
    return dict(resource_changes=[dict(address=updater.IMAGE, change=dict(
        actions=["delete", "create"], before=copy.deepcopy(INSTANCE), after=after))])


class GuardTests(unittest.TestCase):
    def test_wrong_publication_is_rejected(self):
        for key, value in [("repository", "other/app"), ("platform", "linux/arm64"),
                           ("revision", "c" * 40), ("digest", "latest"), ("publication", "other")]:
            with self.subTest(key=key), self.assertRaises(RuntimeError):
                updater.validate_publication(dict(NEW, **{key: value}), "b" * 40, 123)

    def test_only_image_replacement_is_accepted(self):
        updater.validate_plan(plan(), OLD, NEW)
        for key, value in [("config", {}), ("device", [{}]), ("remote", "other"), ("running", False)]:
            changed = plan()
            changed["resource_changes"][0]["change"]["after"][key] = value
            with self.subTest(key=key), self.assertRaises(RuntimeError):
                updater.validate_plan(changed, OLD, NEW)

    def test_volume_changes_are_rejected(self):
        changed = plan()
        changed["resource_changes"].append(dict(address="incus_storage_volume.data",
                                               change=dict(actions=["delete", "create"])))
        with self.assertRaises(RuntimeError):
            updater.validate_plan(changed, OLD, NEW)

    def test_foreign_target_or_mount_is_rejected(self):
        updater.validate_target(RESOURCES, INPUTS, GUEST, OLD)
        for inputs in [dict(INPUTS, incus_remote="other"), dict(INPUTS, start=False)]:
            with self.assertRaises(RuntimeError):
                updater.validate_target(RESOURCES, inputs, GUEST, OLD)
        changed = copy.deepcopy(GUEST)
        changed["expanded_devices"]["data"]["source"] = "other-data"
        with self.assertRaises(RuntimeError):
            updater.validate_target(RESOURCES, INPUTS, changed, OLD)


class PublicationTests(unittest.TestCase):
    def fetch(self, status="completed", conclusion="success", artifact=NEW):
        self.commands = []
        with tempfile.TemporaryDirectory() as directory:
            folder = Path(directory) / "publication"

            def execute(*args, capture=False, timeout=None):
                self.commands.append(args)
                if args[:2] == ("gh", "api"):
                    return "b" * 40
                if args[:3] == ("gh", "run", "list"):
                    return json.dumps([dict(databaseId=123, headSha="b" * 40,
                                            status=status, conclusion=conclusion)])
                if args[:3] == ("gh", "run", "view"):
                    return json.dumps(dict(headSha="b" * 40, status="completed", conclusion=conclusion))
                if args[:3] == ("gh", "run", "download"):
                    folder.mkdir()
                    (folder / "image.lock.json").write_text(json.dumps(artifact))
                return ""

            with patch.object(updater, "run", execute):
                return updater.published_image(folder)

    def test_success_downloads_the_matching_publication(self):
        self.assertEqual(self.fetch(), NEW)
        listing = next(args for args in self.commands if args[:3] == ("gh", "run", "list"))
        self.assertIn("--commit", listing)
        self.assertIn("b" * 40, listing)

    def test_in_progress_run_is_watched_before_download(self):
        self.assertEqual(self.fetch(status="in_progress", conclusion="success"), NEW)
        verbs = [args[:3] for args in self.commands]
        self.assertLess(verbs.index(("gh", "run", "watch")), verbs.index(("gh", "run", "download")))

    def test_failed_latest_run_is_not_replaced_with_an_older_success(self):
        with self.assertRaises(RuntimeError):
            self.fetch(conclusion="failure")
        self.assertNotIn(("gh", "run", "download"), [args[:3] for args in self.commands])

    def test_mismatched_artifact_is_rejected(self):
        with self.assertRaises(RuntimeError):
            self.fetch(artifact=dict(NEW, revision="c" * 40))


class FlowTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        (self.root / "site.auto.tfvars.json").write_text(json.dumps(INPUTS))
        self.old_bytes = json.dumps(OLD).encode()
        (self.root / "image.lock.json").write_bytes(self.old_bytes)
        self.folder = self.root / "operation"
        self.folder.mkdir()
        self.commands = []
        self.plan = plan()
        self.failure = None

    def fake_run(self, *args, capture=False, timeout=None):
        self.commands.append(args)
        if self.failure and args[:len(self.failure)] == self.failure:
            raise subprocess.CalledProcessError(1, args)
        if args[:2] == ("tofu", "workspace"):
            return "default"
        if args == ("tofu", "show", "-json"):
            return json.dumps(dict(values=dict(root_module=dict(resources=RESOURCES))))
        if args[:3] == ("tofu", "show", "-json"):
            return json.dumps(self.plan)
        if args[:2] == ("incus", "query"):
            return json.dumps(GUEST)
        return ""

    def perform(self, answer="y", publication=NEW):
        with patch.object(updater, "ROOT", self.root), patch.object(updater, "run", self.fake_run), \
             patch.object(updater, "published_image", return_value=publication), \
             patch.dict(updater.os.environ, {}, clear=True), patch("builtins.input", return_value=answer):
            updater.update(self.folder)

    def test_success_stops_only_after_plan_review_then_applies_and_checks_health(self):
        self.perform()
        commands = [args[:2] for args in self.commands]
        self.assertLess(commands.index(("tofu", "plan")), commands.index(("incus", "stop")))
        self.assertLess(commands.index(("incus", "stop")), commands.index(("tofu", "apply")))
        self.assertEqual(commands[-1], ("incus", "exec"))
        self.assertEqual(json.loads((self.root / "image.lock.json").read_text()), NEW)

    def test_decline_restores_pin_without_stopping(self):
        self.perform(answer="n")
        self.assertEqual((self.root / "image.lock.json").read_bytes(), self.old_bytes)
        self.assertNotIn(("incus", "stop"), [args[:2] for args in self.commands])

    def test_volume_plan_failure_restores_pin_without_stopping(self):
        self.plan["resource_changes"][0]["address"] = "incus_storage_volume.data"
        with self.assertRaises(RuntimeError):
            self.perform()
        self.assertEqual((self.root / "image.lock.json").read_bytes(), self.old_bytes)
        self.assertNotIn(("incus", "stop"), [args[:2] for args in self.commands])

    def test_stop_failure_prevents_apply(self):
        self.failure = ("incus", "stop")
        with self.assertRaises(subprocess.CalledProcessError):
            self.perform()
        self.assertNotIn(("tofu", "apply"), [args[:2] for args in self.commands])
        self.assertEqual((self.root / "image.lock.json").read_bytes(), self.old_bytes)

    def test_apply_failure_retains_pin_and_recovery_record_without_health_check(self):
        self.failure = ("tofu", "apply")
        with self.assertRaises(subprocess.CalledProcessError):
            self.perform()
        self.assertEqual(json.loads((self.root / "image.lock.json").read_text()), NEW)
        self.assertTrue((self.folder / "previous-image.lock.json").is_file())
        self.assertNotIn(("incus", "exec"), [args[:2] for args in self.commands])

    def test_same_digest_does_not_stop_or_plan(self):
        self.perform(publication=OLD)
        self.assertNotIn(("tofu", "plan"), [args[:2] for args in self.commands])
        self.assertNotIn(("incus", "stop"), [args[:2] for args in self.commands])

    def test_publication_failure_does_not_write_pin_or_stop(self):
        with patch.object(updater, "ROOT", self.root), patch.object(updater, "run", self.fake_run), \
             patch.object(updater, "published_image", side_effect=RuntimeError("failed workflow")), \
             patch.dict(updater.os.environ, {}, clear=True):
            with self.assertRaises(RuntimeError):
                updater.update(self.folder)
        self.assertEqual((self.root / "image.lock.json").read_bytes(), self.old_bytes)
        self.assertNotIn(("incus", "stop"), [args[:2] for args in self.commands])


if __name__ == "__main__":
    unittest.main()
