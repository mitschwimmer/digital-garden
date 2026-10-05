#!/usr/bin/env bash
# Build on the workstation, then import and activate through authenticated Incus.
set -euo pipefail
if [[ $# -ne 1 || ! $1 =~ ^[[:alnum:]][[:alnum:]_.-]*$ ]]; then
  echo "Usage: bash scripts/deploy-edge.sh <incus-remote-alias>" >&2
  exit 2
fi
cd "$(dirname "$0")/.."
target="$1:edge"
[[ -f secrets/edge.yaml ]] || { echo "Run prepare-auth.py and stage encrypted configuration first." >&2; exit 1; }
git ls-files --error-unmatch secrets/edge.yaml >/dev/null
incus exec "$target" --project default -- mountpoint -q /var/lib/authelia-main
incus exec "$target" --project default -- mountpoint -q /var/lib/garden-secrets
incus exec "$target" --project default -- test -s /var/lib/garden-secrets/age.key
incus exec "$target" --project default -- mountpoint -q /var/lib/caddy
previous="$(incus exec "$target" --project default -- readlink -f /nix/var/nix/profiles/system)"
closure="$(nix build .#nixosConfigurations.edge.config.system.build.toplevel --out-link result-edge-system --print-out-paths)"
[[ "$previous" == /nix/store/* && "$closure" == /nix/store/* ]] || { echo "Invalid system path." >&2; exit 1; }
paths_file="$(mktemp)"
trap 'rm -f "$paths_file"' EXIT
nix-store --query --requisites "$closure" > "$paths_file"
mapfile -t store_paths < "$paths_file"
[[ ${#store_paths[@]} -gt 0 ]]
nix-store --export "${store_paths[@]}" |
  incus exec "$target" --project default -T -- nix-store --import >/dev/null
incus exec "$target" --project default -- nix-env --profile /nix/var/nix/profiles/system --set "$closure"
if incus exec "$target" --project default -- "$closure/bin/switch-to-configuration" switch &&
   incus exec "$target" --project default -- systemctl is-active caddy &&
   incus exec "$target" --project default -- curl --fail --max-time 15 http://127.0.0.1:8080/healthz &&
   incus exec "$target" --project default -- systemctl is-active authelia-main &&
   incus exec "$target" --project default -- curl --fail --max-time 15 http://127.0.0.1:9091/api/health; then
  printf '\nPrevious system for rollback: %s\n' "$previous"
else
  echo "Activation failed; restoring previous system $previous." >&2
  incus exec "$target" --project default -- nix-env --profile /nix/var/nix/profiles/system --set "$previous"
  incus exec "$target" --project default -- "$previous/bin/switch-to-configuration" switch
  exit 1
fi
