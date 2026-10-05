#!/usr/bin/env bash
# Build locally; writes only local input files. Does not contact the Incus host.
set -euo pipefail
if [[ $# -ne 2 || ! $1 =~ ^[[:alnum:]][[:alnum:]_.-]*$ || ! $2 =~ ^[[:alnum:]][[:alnum:]_.-]*$ ]]; then
  echo "Usage: bash scripts/prepare-edge.sh <incus-remote-alias> <existing-storage-pool>" >&2
  exit 2
fi
cd "$(dirname "$0")/.."
command -v nix >/dev/null || { echo "Nix with flakes is required." >&2; exit 1; }
command -v python3 >/dev/null || { echo "Python 3 is required." >&2; exit 1; }
image_directory="$(nix build .#edge-image --no-link --print-out-paths)"
python3 - "$1" "$2" "$image_directory" <<'PY'
import json
import pathlib
import sys

remote, storage_pool, directory = sys.argv[1:]
image = pathlib.Path(directory)
if not directory.startswith("/nix/store/") or not all(
    (image / name).is_file() for name in ("metadata.tar.xz", "rootfs.tar.xz")
):
    raise SystemExit("Build did not return one complete image in /nix/store.")
path = pathlib.Path("tofu/site.auto.tfvars.json")
temporary = path.with_suffix(".tmp")
temporary.write_text(json.dumps({
    "incus_remote": remote, "storage_pool": storage_pool, "image_directory": directory,
}, indent=2) + "\n")
temporary.replace(path)
print(f"Prepared {path}; no host changes made.")
PY
