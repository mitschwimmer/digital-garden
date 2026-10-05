#!/usr/bin/env bash
# Read-only inventory. Run from an authenticated Incus client workstation.
set -euo pipefail
if [[ $# -ne 1 || ! $1 =~ ^[[:alnum:]][[:alnum:]_.-]*$ ]]; then
  echo "Usage: bash scripts/inventory.sh <incus-remote-alias>" >&2
  exit 2
fi
command -v incus >/dev/null || { echo "Install the Incus client first." >&2; exit 1; }
remote="$1:"
section() { printf '\n## %s\n' "$1"; }
section "Client version"
incus version
section "Host"
incus info "$remote"
section "Hardware and GPU"
incus info "$remote" --resources
section "Networks"
incus network list "$remote"
section "Storage pools"
incus storage list "$remote"
section "Instances in the selected client project"
incus list "$remote"
