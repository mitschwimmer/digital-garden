import contextlib
import importlib.util
import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location("watcher", Path(__file__).parents[1] / "operations/watch_walter_image.py")
watcher = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(watcher)

OLD = "sha256:" + "1" * 64
NEW = "sha256:" + "2" * 64
RUN = dict(databaseId=123, headSha="b" * 40, status="completed", conclusion="success")
IMAGE = dict(repository="mitschwimmer/walter", platform="linux/amd64", revision="b" * 40,
             publication="https://github.com/mitschwimmer/walter/actions/runs/123", digest=NEW)


class WatchTests(unittest.TestCase):
    def test_waits_for_success_and_skips_the_current_digest(self):
        runs = [[], [dict(RUN, status="in_progress")], [RUN], [RUN], [dict(RUN, databaseId=124)]]
        with patch.object(watcher, "gh", side_effect=[json.dumps(r) for r in runs]), \
             patch.object(watcher, "publication", side_effect=[dict(IMAGE, digest=OLD), IMAGE]) as download, \
             patch.object(watcher.time, "sleep") as sleep:
            self.assertEqual(watcher.watch(OLD), IMAGE)
        self.assertEqual(download.call_count, 2)
        self.assertEqual(sleep.call_count, 4)

    def test_failed_run_is_not_downloaded(self):
        with patch.object(watcher, "gh", side_effect=[json.dumps([dict(RUN, conclusion="failure")]), json.dumps([RUN])]), \
             patch.object(watcher, "publication", return_value=IMAGE) as download, \
             patch.object(watcher.time, "sleep"):
            self.assertEqual(watcher.watch(OLD), IMAGE)
        download.assert_called_once_with(RUN)

    def test_artifact_must_match_the_run(self):
        for key, value in [("repository", "other/app"), ("platform", "linux/arm64"),
                           ("revision", "a" * 40), ("publication", "other"), ("digest", "latest")]:
            def download(*args):
                directory = Path(args[args.index("--dir") + 1])
                (directory / "image.lock.json").write_text(json.dumps(dict(IMAGE, **{key: value})))
            with self.subTest(key=key), patch.object(watcher, "gh", side_effect=download), self.assertRaises(ValueError):
                watcher.publication(RUN)

    def test_matching_artifact_is_returned(self):
        def download(*args):
            (Path(args[args.index("--dir") + 1]) / "image.lock.json").write_text(json.dumps(IMAGE))
        with patch.object(watcher, "gh", side_effect=download):
            self.assertEqual(watcher.publication(RUN), IMAGE)

    def test_stdout_is_pipeable_and_source_lock_is_unchanged(self):
        with tempfile.TemporaryDirectory() as directory:
            lock = Path(directory) / "image.lock.json"
            original = json.dumps(dict(IMAGE, digest=OLD))
            lock.write_text(original)
            for arguments, expected in [([], NEW), (["--json"], json.dumps(IMAGE, indent=2))]:
                output = io.StringIO()
                with self.subTest(arguments=arguments), patch.object(watcher, "LOCK", lock), \
                     patch.object(watcher, "watch", return_value=IMAGE), \
                     patch("sys.argv", ["watch_walter_image.py", *arguments]), contextlib.redirect_stdout(output):
                    watcher.main()
                self.assertEqual(output.getvalue(), expected + "\n")
                self.assertEqual(lock.read_text(), original)


if __name__ == "__main__":
    unittest.main()
