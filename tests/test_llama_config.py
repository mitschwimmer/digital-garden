#!/usr/bin/env python3
"""Verify immutable sources and ownership boundaries of the actual image configuration."""
import configparser
import json
from pathlib import Path

root = Path(__file__).resolve().parents[1]
models = json.loads((root / "llama/models.lock.json").read_text())
presets = configparser.ConfigParser()
presets.read_string("[router]\n" + (root / "llama/models.ini").read_text())
assert set(presets.sections()) == {"router", "*", *models}
assert presets["*"]["load-on-startup"] == "false"
for name, entry in models.items():
    expected = "https://huggingface.co/" + entry["repository"] + "/resolve/" + entry["revision"] + "/" + entry["file"]
    assert presets[name]["model-url"] == expected
    assert entry["sha256"] in presets[name]["model"]
    assert presets[name]["model"].startswith("/var/cache/llama/")
base = json.loads((root / "llama/image.lock.json").read_text())
dockerfile = (root / "llama/Dockerfile").read_text()
assert dockerfile.splitlines()[0] == "FROM ghcr.io/" + base["repository"] + "@" + base["digest"]
assert "LLAMA_ARG_MODELS_MAX=1" in dockerfile
assert "LLAMA_ARG_MODELS_AUTOLOAD=true" in dockerfile
assert "USER 1000:1000" in dockerfile
tofu = (root / "tofu/llama.tf").read_text()
assert 'resource "incus_storage_volume" "llama_config"' not in tofu and "models.ini" not in tofu
assert 'destroy = false' in tofu
assert "environment.LLAMA" not in tofu
print("Immutable model sources, lazy loading, and image-owned application configuration verified.")
