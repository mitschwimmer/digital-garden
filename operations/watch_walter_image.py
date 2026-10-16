#!/usr/bin/env python3
"""Wait for a successful main image different from the configured Walter digest."""
import argparse
import json
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import time

REPOSITORY = "mitschwimmer/walter"
LOCK = Path(__file__).resolve().parents[1] / "systems/walter/image.lock.json"


def gh(*args):
    return subprocess.run(["gh", *args], check=True, text=True,
                          stdout=subprocess.PIPE).stdout.strip()


def publication(run):
    with tempfile.TemporaryDirectory(prefix="walter-image-") as directory:
        gh("run", "download", str(run["databaseId"]), "--repo", REPOSITORY,
           "--name", "walter-image", "--dir", directory)
        image = json.loads((Path(directory) / "image.lock.json").read_text())
    expected_url = f"https://github.com/{REPOSITORY}/actions/runs/{run['databaseId']}"
    if (image.get("repository") != REPOSITORY or image.get("platform") != "linux/amd64"
            or image.get("revision") != run["headSha"] or image.get("publication") != expected_url
            or not re.fullmatch(r"sha256:[0-9a-f]{64}", image.get("digest", ""))):
        raise ValueError("Published image record does not match the successful run")
    return image


def watch(current):
    checked = None
    print("Waiting for a new successful Walter main image...", file=sys.stderr)
    while True:
        runs = json.loads(gh("run", "list", "--repo", REPOSITORY, "--workflow", "oci.yml",
                             "--branch", "main", "--event", "push", "--limit", "1",
                             "--json", "databaseId,headSha,status,conclusion"))
        if runs:
            run = runs[0]
            if run["status"] == "completed" and (run["databaseId"], run["conclusion"]) != checked:
                checked = (run["databaseId"], run["conclusion"])
                if run["conclusion"] == "success":
                    image = publication(run)
                    if image["digest"] != current:
                        return image
                else:
                    print(f"Run {run['databaseId']}: {run['conclusion']}; waiting for another push.", file=sys.stderr)
        time.sleep(5)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--json", action="store_true", help="Print the complete image lock, including provenance")
    args = parser.parse_args()
    current = json.loads(LOCK.read_text())["digest"]
    image = watch(current)
    print(json.dumps(image, indent=2) if args.json else image["digest"])


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        sys.exit(130)
    except (OSError, ValueError, KeyError, subprocess.CalledProcessError) as error:
        sys.exit(f"Stopped: {error}")
