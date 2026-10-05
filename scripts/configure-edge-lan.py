#!/usr/bin/env python3
"""Set local LAN inputs without changing the homelab."""
import argparse
import json
from pathlib import Path
import re
import secrets

parser = argparse.ArgumentParser()
parser.add_argument("parent", help="IncusOS host interface connected to the LAN")
args = parser.parse_args()
if not re.fullmatch(r"[A-Za-z0-9_.-]+", args.parent):
    parser.error("Invalid interface name.")
path = Path(__file__).resolve().parents[1] / "tofu/site.auto.tfvars.json"
values = json.loads(path.read_text())
# Retain the MAC across reruns so router reservations remain valid.
mac = values.get("edge_lan_mac") or "02:" + ":".join(f"{b:02x}" for b in secrets.token_bytes(5))
if not re.fullmatch(r"02(:[0-9a-f]{2}){5}", mac):
    parser.error("Existing LAN MAC is invalid; review local inputs.")
values.update(edge_lan_parent=args.parent, edge_lan_mac=mac)
temporary = path.with_suffix(".tmp")
temporary.write_text(json.dumps(values, indent=2) + "\n")
temporary.replace(path)
print(f"Configured local LAN inputs. Reserve a new LAN IPv4 address for MAC {mac}.")
