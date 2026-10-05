#!/usr/bin/env python3
"""Resolve public GGUF files once; keep their immutable revision and checksum in Git."""
import json
from pathlib import Path
import re
from urllib.request import urlopen

SELECTED = {
    "mimo": ("bartowski/MiMo-V2.6-Distill-Qwen-9B-GGUF", "MiMo-V2.6-Distill-Qwen-9B-Q5_K_M.gguf"),
    "qwen36": ("unsloth/Qwen3.6-35B-A3B-MTP-GGUF", "Qwen3.6-35B-A3B-UD-IQ3_XXS.gguf"),
}


def main():
    path = Path(__file__).resolve().parents[1] / "llama/models.lock.json"
    if path.exists():
        print("Existing model lock retained; upgrades require an explicit reviewed edit.")
        return
    result = {}
    for name, (repo, filename) in SELECTED.items():
        with urlopen("https://huggingface.co/api/models/" + repo + "?blobs=true", timeout=30) as response:
            metadata = json.load(response)
        item = next(item for item in metadata["siblings"] if item["rfilename"] == filename)
        revision, sha = metadata["sha"], item["lfs"]["sha256"]
        if not re.fullmatch(r"[0-9a-f]{40}", revision) or not re.fullmatch(r"[0-9a-f]{64}", sha):
            raise ValueError("Invalid model revision/checksum")
        result[name] = {"repository": repo, "file": filename, "revision": revision,
                        "sha256": sha, "size": item["lfs"]["size"]}
    encoded = json.dumps(result, indent=2) + "\n"
    temporary = path.with_suffix(".json.tmp")
    temporary.write_text(encoded)
    temporary.replace(path)
    # All metadata is public. No model data is downloaded by this helper.
    print(encoded)


if __name__ == "__main__":
    main()
