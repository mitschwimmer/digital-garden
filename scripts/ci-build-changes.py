#!/usr/bin/env python3
"""Skip only Nix builds whose derivation is identical to the event's base."""
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile


def command(*args):
    return subprocess.run(args, check=True, stdout=subprocess.PIPE,
                          stderr=subprocess.PIPE, text=True).stdout.strip()


def main():
    event = json.loads(Path(os.environ["GITHUB_EVENT_PATH"]).read_text())
    base = event.get("pull_request", {}).get("base", {}).get("sha") or event.get("before", "")
    attrs = {
        "guest": "nixosConfigurations.edge.config.system.build.toplevel.drvPath",
        "image": "packages.x86_64-linux.edge-image.drvPath",
    }
    changed = {name: True for name in attrs}
    if re.fullmatch(r"[0-9a-f]{40}", base) and base != "0" * 40:
        with tempfile.TemporaryDirectory(prefix="garden-ci-base-") as directory:
            baseline = Path(directory) / "checkout"
            added = False
            try:
                command("git", "worktree", "add", "--detach", str(baseline), base)
                added = True
                for name, attr in attrs.items():
                    # Evaluate current unconditionally: a broken head must fail CI.
                    current = command("nix", "eval", "--no-update-lock-file",
                                      "--raw", ".#" + attr)
                    try:
                        previous = command("nix", "eval", "--no-update-lock-file",
                                           "--raw", "path:" + str(baseline) + "#" + attr)
                        changed[name] = current != previous
                    except subprocess.CalledProcessError:
                        # Unknown/broken baseline cannot justify skipping a build.
                        changed[name] = True
            except subprocess.CalledProcessError:
                # Subsequent validator/build steps still fail on broken head code.
                changed = {name: True for name in attrs}
            finally:
                if added:
                    command("git", "worktree", "remove", "--force", str(baseline))
    with open(os.environ["GITHUB_OUTPUT"], "a") as output:
        for name, needed in changed.items():
            output.write(f"{name}={str(needed).lower()}\n")
            print(f"{name}: {'build required' if needed else 'unchanged derivation; skip build'}")


if __name__ == "__main__":
    main()
