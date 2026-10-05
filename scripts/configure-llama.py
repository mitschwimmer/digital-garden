#!/usr/bin/env python3
"""Select the host AMD GPU into ignored local OpenTofu inputs; do not change the host."""
import argparse
import json
from pathlib import Path
import re
import subprocess


def select(cards, requested=None):
    choices = [card["pci_address"] for card in cards if card.get("vendor_id") == "1002"]
    if requested:
        if requested not in choices:
            raise ValueError("Requested PCI address is not an available AMD GPU")
        return requested
    if len(choices) != 1:
        raise ValueError("Select one AMD GPU explicitly with --gpu-pci; candidates: " + ", ".join(choices))
    return choices[0]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("remote")
    parser.add_argument("--gpu-pci")
    args = parser.parse_args()
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_.-]*", args.remote):
        parser.error("Invalid remote alias")
    path = Path(__file__).resolve().parents[1] / "tofu/site.auto.tfvars.json"
    values = json.loads(path.read_text())
    if values["incus_remote"] != args.remote:
        parser.error("Remote must match existing local inputs")
    resources = json.loads(subprocess.run(
        ["incus", "query", args.remote + ":/1.0/resources"], check=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE).stdout)
    pci = select(resources["gpu"]["cards"], args.gpu_pci or values.get("llama_gpu_pci"))
    if not re.fullmatch(r"[0-9a-f]{4}:[0-9a-f]{2}:[0-9a-f]{2}\.[0-7]", pci):
        raise ValueError("Invalid GPU PCI address")
    values["llama_gpu_pci"] = pci
    temporary = path.with_suffix(".tmp")
    temporary.write_text(json.dumps(values, indent=2) + "\n")
    temporary.replace(path)
    print("Configured GPU in ignored local inputs. No host changes were made.")


if __name__ == "__main__":
    main()
