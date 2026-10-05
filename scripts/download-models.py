#!/usr/bin/env python3
"""Download locked GGUF files into the new protected volume and verify SHA256."""
import argparse
import json
from pathlib import Path
import re
import subprocess

DOWNLOAD = r'''
set -eu
name=$1; url=$2; expected=$3
destination=/var/cache/llama/$name.gguf
check() { actual=$(sha256sum "$1"); test "${actual%% *}" = "$expected"; }
if test -f "$destination"; then
  check "$destination" || { echo 'Existing model checksum differs; review it before replacing.' >&2; exit 1; }
  echo "$name: existing verified model retained"
  exit 0
fi
t=$(mktemp /var/cache/llama/.download.XXXXXX)
trap 'rm -f "$t"' EXIT
curl --fail --location --retry 3 --connect-timeout 15 --max-time 7200 --output "$t" "$url"
check "$t" || { echo 'Downloaded model checksum failed.' >&2; exit 1; }
chmod 0640 "$t"
mv "$t" "$destination"
echo "$name: downloaded and checksum verified"
'''


def main():
    root = Path(__file__).resolve().parents[1]
    models = json.loads((root / "llama/models.lock.json").read_text())
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("remote")
    parser.add_argument("--model", choices=list(models))
    args = parser.parse_args()
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_.-]*", args.remote):
        parser.error("Invalid remote alias")
    for name in ([args.model] if args.model else list(models)):
        entry = models[name]
        if not re.fullmatch(r"[a-z0-9_-]+", name) or not re.fullmatch(r"[0-9a-f]{64}", entry["sha256"]):
            raise ValueError("Invalid model lock")
        if not re.fullmatch(r"[0-9a-f]{40}", entry["revision"]):
            raise ValueError("Model revision must be immutable")
        url = "https://huggingface.co/" + entry["repository"] + "/resolve/" + entry["revision"] + "/" + entry["file"]
        subprocess.run(["incus", "exec", args.remote + ":garden-llama", "--project", "default",
                        "--user", "1000", "--group", "1000", "-T", "--", "sh", "-c", DOWNLOAD,
                        "garden-download", name, url, entry["sha256"]], check=True)


if __name__ == "__main__":
    main()
