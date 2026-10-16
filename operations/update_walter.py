#!/usr/bin/env python3
"""Deploy the newest successful Walter main image, with one reviewed plan."""
import fcntl
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import time
import uuid

REPO = Path(__file__).resolve().parents[1]
ROOT = REPO / "systems/walter"
UPSTREAM = "mitschwimmer/walter"
IMAGE = "incus_instance.walter"
VOLUMES = {"incus_storage_volume.data", "incus_storage_volume.secrets"}


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def run(*args, capture=False, timeout=None):
    result = subprocess.run(args, cwd=ROOT, check=True, text=True,
                            stdout=subprocess.PIPE if capture else None,
                            timeout=timeout)
    return result.stdout.strip() if capture else None


def read_json(*args):
    return json.loads(run(*args, capture=True))


def write_json(path, value):
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(json.dumps(value, indent=2) + "\n")
    temporary.replace(path)


def published_image(folder):
    revision = run("gh", "api", f"repos/{UPSTREAM}/commits/main", "--jq", ".sha", capture=True)
    require(re.fullmatch(r"[0-9a-f]{40}", revision), "Invalid upstream revision")
    for attempt in range(20):
        runs = read_json("gh", "run", "list", "--repo", UPSTREAM,
                         "--workflow", "oci.yml", "--branch", "main", "--event", "push",
                         "--commit", revision, "--limit", "1",
                         "--json", "databaseId,headSha,status,conclusion")
        if runs:
            break
        if attempt == 0:
            print("Waiting for the latest main push to enter Actions...", flush=True)
        time.sleep(3)
    require(runs, "No main-push image run appeared; check Walter Actions")
    selected = runs[0]
    require(selected["headSha"] == revision, "Actions revision differs from upstream main")
    run_id = selected["databaseId"]
    require(type(run_id) is int and run_id > 0, "Invalid Actions run ID")
    if selected["status"] != "completed":
        print(f"Waiting for Walter publication: https://github.com/{UPSTREAM}/actions/runs/{run_id}", flush=True)
        run("gh", "run", "watch", str(run_id), "--repo", UPSTREAM, "--exit-status", timeout=900)
        selected = read_json("gh", "run", "view", str(run_id), "--repo", UPSTREAM,
                             "--json", "conclusion,headSha,status")
    require(selected["conclusion"] == "success" and selected["headSha"] == revision,
            "Latest main publication did not succeed; the running app was not touched")
    run("gh", "run", "download", str(run_id), "--repo", UPSTREAM,
        "--name", "walter-image", "--dir", str(folder))
    lock = json.loads((folder / "image.lock.json").read_text())
    validate_publication(lock, revision, run_id)
    return lock


def validate_publication(lock, revision, run_id):
    require(lock.get("repository") == UPSTREAM and lock.get("platform") == "linux/amd64",
            "Publication repository/platform mismatch")
    require(lock.get("revision") == revision, "Publication revision mismatch")
    require(re.fullmatch(r"sha256:[0-9a-f]{64}", lock.get("digest", "")), "Invalid image digest")
    require(lock.get("publication") == f"https://github.com/{UPSTREAM}/actions/runs/{run_id}",
            "Publication run mismatch")


def validate_target(resources, inputs, guest, old):
    require(inputs.get("start") is True, "This updater requires an installed Walter with start=true")
    remote = inputs.get("incus_remote", "")
    require(re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_.-]*", remote), "Invalid Incus remote")
    managed = {r["address"]: r["values"] for r in resources if r.get("mode") == "managed"}
    require(set(managed) == {IMAGE} | VOLUMES, "Walter state must own exactly its instance and two volumes")
    instance = managed[IMAGE]
    require((instance.get("name"), instance.get("project"), instance.get("remote")) ==
            ("walter", "ai", remote), "Applied Walter identity differs from local inputs")
    require(instance.get("image") == image_reference(old), "Existing image lock differs from applied state")
    require(guest.get("name") == "walter" and guest.get("status") in {"Running", "Stopped"},
            "Expected an existing running or stopped Walter container")
    devices = guest.get("expanded_devices", {})
    for address, device, volume, mount in [
        ("incus_storage_volume.data", "data", "walter-data", "/data"),
        ("incus_storage_volume.secrets", "secrets", "walter-secrets", "/run/secrets"),
    ]:
        attributes = managed[address]
        require((attributes.get("name"), attributes.get("pool"), attributes.get("project"), attributes.get("remote")) ==
                (volume, inputs.get("storage_pool"), "ai", remote), "Applied volume identity differs from inputs")
        actual = devices.get(device, {})
        require((actual.get("source"), actual.get("pool"), actual.get("path")) ==
                (volume, inputs.get("storage_pool"), mount), "Guest persistent mount differs from state")
    require(devices["secrets"].get("readonly") == "true", "Secret mount must be read-only")


def image_reference(lock):
    return f"garden-ghcr:{lock['repository']}@{lock['digest']}"


def validate_plan(plan, old, new):
    replacements = []
    for item in plan.get("resource_changes", []):
        change = item["change"]
        actions = change["actions"]
        if actions in (["no-op"], ["read"]):
            continue
        require(item["address"] == IMAGE, "Plan changes resources other than Walter; use the normal workflow")
        require(actions == ["delete", "create"], "Expected a stopped-before-replacement image update")
        before, after = change["before"], change["after"]
        require(before.get("image") == image_reference(old) and after.get("image") == image_reference(new),
                "Plan image differs from the reviewed publication")
        require(after.get("running") is True, "Plan must start the new image")
        for key in ("name", "project", "remote", "type", "ephemeral", "profiles", "config", "device"):
            require(before.get(key) == after.get(key), f"Plan also changes {key}; use the normal workflow")
        replacements.append(item)
    require(len(replacements) == 1, "Expected exactly one Walter image replacement")


def update(folder):
    require(not any(k.startswith("TF_") for k in os.environ), "Unset TF_* overrides before updating")
    require(run("tofu", "workspace", "show", capture=True) == "default", "Only the default workspace is supported")
    inputs = json.loads((ROOT / "site.auto.tfvars.json").read_text())
    old_path = ROOT / "image.lock.json"
    old_bytes = old_path.read_bytes()
    old = json.loads(old_bytes)
    state = read_json("tofu", "show", "-json")
    resources = state.get("values", {}).get("root_module", {}).get("resources", [])
    remote = inputs.get("incus_remote", "")
    require(re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_.-]*", remote), "Invalid Incus remote")
    target = f"{remote}:walter"
    guest = read_json("incus", "query", f"{remote}:/1.0/instances/walter?project=ai")
    validate_target(resources, inputs, guest, old)
    new = published_image(folder / "publication")
    if new["digest"] == old["digest"]:
        print(f"Walter already uses {new['revision']}; no update needed.")
        return
    (folder / "previous-image.lock.json").write_bytes(old_bytes)
    write_json(old_path, new)
    plan = folder / "change.tfplan"
    applying = False
    try:
        # Prepare/review while the old app is still available; stop only for apply.
        run("tofu", "plan", "-input=false", f"-out={plan}")
        validate_plan(read_json("tofu", "show", "-json", str(plan)), old, new)
        run("tofu", "show", "-no-color", str(plan))
        print(f"\nNew image: {new['digest']}\nSource: {new['publication']}")
        if input("Replace Walter with this image? [y/N] ").strip().lower() != "y":
            print("Cancelled; the running app was not touched.")
            return
        guest = read_json("incus", "query", f"{remote}:/1.0/instances/walter?project=ai")
        validate_target(resources, inputs, guest, old)
        if guest["status"] == "Running":
            run("incus", "stop", target, "--project", "ai", "--timeout", "30")
        applying = True
        run("tofu", "apply", "-input=false", str(plan))
        run("incus", "exec", f"{remote}:edge", "--project", "default", "-T", "--",
            "curl", "--fail", "--retry", "15", "--retry-connrefused", "--retry-delay", "2",
            "--connect-timeout", "5", "--max-time", "10", "--retry-max-time", "90",
            "http://walter.garden.internal:8080/healthz")
        print("Walter is ready. Sign in again and verify streaming and an existing conversation.")
        print("The image lock is updated locally; commit it after acceptance.")
    finally:
        if not applying:
            old_path.write_bytes(old_bytes)
        else:
            print(f"Update records: {folder}")


def main():
    if len(sys.argv) != 1:
        print(__doc__ + "\nUsage: python operations/update_walter.py", file=sys.stderr)
        return 0 if sys.argv[1:] == ["--help"] else 2
    os.umask(0o077)
    operations = ROOT / ".operations"
    operations.mkdir(exist_ok=True)
    with (operations / "update.lock").open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        folder = operations / uuid.uuid4().hex
        folder.mkdir()
        update(folder)
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (RuntimeError, OSError, ValueError, KeyError, EOFError,
            subprocess.CalledProcessError, subprocess.TimeoutExpired) as error:
        sys.exit(f"Stopped: {error}")
