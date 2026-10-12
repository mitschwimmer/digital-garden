#!/usr/bin/env python3
"""Activate one system from its operation root; never accept a separate target."""
import argparse
import fcntl
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import uuid

REPO = Path(__file__).resolve().parents[1]
STORE = re.compile(r"/nix/store/[0-9a-z]{32}-[^/\s]+$")
NAME = re.compile(r"[A-Za-z0-9][A-Za-z0-9_.-]*$")


def run(*args):
    return subprocess.run(args, check=True, text=True, stdout=subprocess.PIPE).stdout.strip()


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def target(root):
    require(root.parent == REPO / "systems", "Run from a systems/<name> operation root")
    expected = json.loads((root / "target.json").read_text())
    require(expected["system"] == root.name, "Root and declared system differ")
    # Refuse ambient Tofu overrides that could silently select another state.
    require(not any(k.startswith("TF_") for k in os.environ), "Unset TF_* overrides before activation")
    require(run("tofu", "workspace", "show") == "default", "Only the default workspace is supported")
    actual = json.loads(run("tofu", "output", "-json", "deployment"))
    require({k: v for k, v in actual.items() if k != "remote"} == expected,
            "Applied infrastructure target differs from target.json; reconcile this root")
    require(NAME.fullmatch(actual["remote"]), "Invalid Incus remote")
    for key in ("system", "project", "instance"):
        require(NAME.fullmatch(actual[key]), f"Invalid {key}")
    return actual


def guest(t, *args):
    return ["incus", "exec", f'{t["remote"]}:{t["instance"]}',
            "--project", t["project"], "-T", "--", *args]


def preflight(t):
    identity = run("incus", "config", "get", f'{t["remote"]}:{t["instance"]}',
                   "user.garden.system", "--project", t["project"])
    require(identity == t["system"], "Incus metadata does not match selected system")
    for mount in t["mounts"]:
        run(*guest(t, "mountpoint", "-q", mount))


def store_path(path):
    require(isinstance(path, str) and STORE.fullmatch(path), "Expected exactly one Nix store closure")
    return path


def check_local(t, closure):
    store_path(closure)
    require((Path(closure) / "etc/garden-system").read_text().strip() == t["system"],
            "Closure identity does not match selected system")
    require(os.access(Path(closure) / "bin/switch-to-configuration", os.X_OK), "Not an executable NixOS closure")


def check_remote(t, closure):
    store_path(closure)
    require(run(*guest(t, "cat", closure + "/etc/garden-system")) == t["system"],
            "Remote closure identity does not match selected system")
    run(*guest(t, "test", "-x", closure + "/bin/switch-to-configuration"))


def transfer(t, closure):
    paths = run("nix-store", "--query", "--requisites", closure).splitlines()
    require(bool(paths), "Empty closure")
    for path in paths:
        store_path(path)
    with subprocess.Popen(["nix-store", "--export", *paths], stdout=subprocess.PIPE) as export:
        try:
            result = subprocess.run(guest(t, "nix-store", "--import"), stdin=export.stdout,
                                    stdout=subprocess.DEVNULL, check=False)
        finally:
            export.stdout.close()
        export_status = export.wait()
    require(export_status == 0 and result.returncode == 0, "Closure transfer failed; profile untouched")


def activate(t, closure):
    # Check again immediately before either mutating command.
    preflight(t)
    check_remote(t, closure)
    run(*guest(t, "nix-env", "--profile", "/nix/var/nix/profiles/system", "--set", closure))
    subprocess.run(guest(t, closure + "/bin/switch-to-configuration", "switch"), check=True)
    require(run(*guest(t, "readlink", "-f", "/run/current-system")) == closure,
            "Running generation differs from requested closure")
    for unit in t["units"]:
        run(*guest(t, "systemctl", "is-active", unit))
    failed = run(*guest(t, "systemctl", "--failed", "--no-legend", "--plain", "--no-pager"))
    require(not failed, "Guest has failed units; inspect journals before accepting deployment")


def operation(root, args):
    t = target(root)
    preflight(t)
    if args.action == "check":
        check_local(t, str(args.closure.resolve()))
        print("Target, mounts and closure identity match; no profile changed")
        return
    folder = root / ".operations" / uuid.uuid4().hex
    folder.mkdir(mode=0o700)
    if args.action == "rollback":
        record_path = args.record.resolve()
        require(record_path.parent.parent == root / ".operations", "Rollback record belongs to another root")
        old = json.loads(record_path.read_text())
        require(old["target"] == t, "Rollback record belongs to another deployment target")
        closure = store_path(old["previous"])
        check_remote(t, closure)
    else:
        result = json.loads(run("nix", "build",
                                f'{REPO}#nixosConfigurations.{t["system"]}.config.system.build.toplevel',
                                "--json", "--out-link", str(folder / "candidate")))
        require(len(result) == 1, "Expected one build result")
        closure = store_path(result[0]["outputs"]["out"])
        check_local(t, closure)
        transfer(t, closure)
    previous = store_path(run(*guest(t, "readlink", "-f", "/run/current-system")))
    selected_profile = store_path(run(*guest(t, "readlink", "-f", "/nix/var/nix/profiles/system")))
    # Do not require a healthy previous system: this also repairs a wrong deployment.
    record = {"target": t, "previous": previous, "selected_profile": selected_profile, "candidate": closure,
              "revision": run("git", "-C", str(REPO), "rev-parse", "HEAD"), "status": "attempting"}
    record_path = folder / "deployment.json"
    record_path.write_text(json.dumps(record, indent=2) + "\n")
    print(f"Deployment record: {record_path}", flush=True)
    # Retain the old closure on the guest even when generations are pruned.
    run(*guest(t, "nix-store", "--realise", previous, "--add-root",
               f'/nix/var/nix/gcroots/garden-{folder.name}-previous'))
    activate(t, closure)
    record["status"] = "activated; application acceptance still required"
    record_path.write_text(json.dumps(record, indent=2) + "\n")
    print("Activated. Complete application, authorization and restart checks before acceptance.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="action", required=True)
    commands.add_parser("deploy")
    check = commands.add_parser("check")
    check.add_argument("closure", type=Path)
    rollback = commands.add_parser("rollback")
    rollback.add_argument("record", type=Path)
    args = parser.parse_args()
    root = Path.cwd().resolve()
    require(root.parent == REPO / "systems" and (root / "target.json").is_file(),
            "Run from a NixOS systems/<name> operation root")
    os.umask(0o077)
    (root / ".operations").mkdir(exist_ok=True, mode=0o700)
    with (root / ".operations/lock").open("a") as lock:
        # Prevent interleaved deploys from this checkout; remote operators must also coordinate.
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        operation(root, args)


if __name__ == "__main__":
    try:
        main()
    except (RuntimeError, OSError, ValueError, KeyError, subprocess.CalledProcessError) as error:
        sys.exit(f"Stopped: {error}")
