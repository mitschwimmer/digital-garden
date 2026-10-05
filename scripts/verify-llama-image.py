#!/usr/bin/env python3
"""Verify the pinned OCI manifest/config without downloading the ROCm layers."""
import hashlib
import json
from pathlib import Path
from urllib.parse import urlencode
from urllib.request import Request, urlopen


def main():
    lock = json.loads((Path(__file__).resolve().parents[1] / "llama/image.lock.json").read_text())
    repo = lock["repository"]
    with urlopen("https://ghcr.io/token?" + urlencode({"service": "ghcr.io", "scope": "repository:" + repo + ":pull"}), timeout=30) as response:
        token = json.load(response)["token"]

    def fetch(path):
        headers = {"Authorization": "Bearer " + token,
                   "Accept": "application/vnd.oci.image.manifest.v1+json, application/vnd.docker.distribution.manifest.v2+json"}
        with urlopen(Request("https://ghcr.io/v2/" + repo + "/" + path, headers=headers), timeout=30) as response:
            return response.read()

    raw = fetch("manifests/" + lock["digest"])
    assert "sha256:" + hashlib.sha256(raw).hexdigest() == lock["digest"], "Manifest digest mismatch"
    manifest = json.loads(raw)
    config_digest = manifest["config"]["digest"]
    config_raw = fetch("blobs/" + config_digest)
    assert "sha256:" + hashlib.sha256(config_raw).hexdigest() == config_digest, "Configuration digest mismatch"
    config = json.loads(config_raw)
    assert config["os"] + "/" + config["architecture"] == lock["platform"], "Wrong image platform"
    assert config["config"]["Entrypoint"] == ["/app/llama-server"], "Changed upstream entrypoint"
    assert lock["tag"] == "server-rocm-" + config["config"]["Labels"]["org.opencontainers.image.version"], "Version label mismatch"
    print("Verified immutable ROCm image, architecture, version, and entrypoint.")


if __name__ == "__main__":
    main()
