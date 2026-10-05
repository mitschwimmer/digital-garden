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
start = (root / "llama/start.sh").read_text()
assert "--models-max 1" in start and "--models-autoload" in start
assert "exec /app/llama-server" in start
assert "LLAMA_CACHE=/var/cache/llama" in start
assert not (root / "llama/Dockerfile").exists()
tofu = (root / "tofu/llama.tf").read_text()
assert 'file("${path.module}/../llama/image.lock.json")' in tofu
assert 'readonly = "true"' in tofu
assert "models.ini" not in tofu and "environment.LLAMA" not in tofu
assert 'file {' not in tofu
assert "ignore_changes = [running]" in tofu
print("Immutable model URLs, lazy loading, official image, and external read-only configuration verified.")
