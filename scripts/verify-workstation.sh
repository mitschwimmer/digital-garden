#!/usr/bin/env bash
# Run the full checks once on the workstation; deployment reuses built closures.
set -euo pipefail
cd "$(dirname "$0")/.."
if ! command -v tofu >/dev/null || ! command -v sops >/dev/null; then
  echo 'Enter the repository shell first: nix develop --command fish' >&2
  exit 2
fi
for script in scripts/*.sh; do bash -n "$script"; done
sh -n llama/start.sh
python3 -m py_compile scripts/*.py tests/*.py
GARDEN_CI_FIXTURE=1 python3 tests/test_prepare_auth.py
python3 tests/test_prepare_webui.py
python3 tests/test_configure_llama.py
python3 tests/test_llama_config.py
python3 scripts/verify-llama-image.py
python3 scripts/pin-models.py
tofu -chdir=tofu fmt -check -diff
tofu -chdir=tofu init -backend=false -input=false
tofu -chdir=tofu validate
nix build .#checks.x86_64-linux.caddy-config .#checks.x86_64-linux.authelia-config .#checks.x86_64-linux.webui-roles --no-link
nix build .#llama-config --out-link result-llama-config
nix build .#nixosConfigurations.open-webui.config.system.build.toplevel --out-link result-webui-system
# Mocked provider tests do not contact or modify the real homelab.
export TF_VAR_image_directory
TF_VAR_image_directory=$(nix build --impure --no-link --print-out-paths --expr '
  let
    flake = builtins.getFlake (toString ./.);
    pkgs = import flake.inputs.nixpkgs { system = "x86_64-linux"; };
  in pkgs.runCommand "mock-incus-image-paths" {} "mkdir -p $out; touch $out/metadata.tar.xz $out/rootfs.tar.xz"
')
tofu -chdir=tofu test
echo 'Workstation checks passed; built WebUI/config artifacts are reusable by deployment.'
