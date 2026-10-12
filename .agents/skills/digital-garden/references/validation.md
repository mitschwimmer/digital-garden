# Validate the changed layers

Distinguish source validation, closure builds, reviewed infrastructure plans and
live acceptance. None substitutes for the next. Run native tools in the repository
fish development shell; build outside IncusOS.

```fish
git diff --check
python -m unittest discover -s tests -v
nixfmt --check flake.nix nix/modules/*.nix nix/packages/*.nix systems/*/*.nix
for root in platform systems/edge systems/identity systems/open-webui systems/inference
    tofu -chdir=$root fmt -check -diff
    tofu -chdir=$root init -backend=false -input=false -lockfile=readonly
    tofu -chdir=$root validate
end
nix flake check --no-build
nix build .#checks.x86_64-linux.caddy-config --no-link
nix build .#edge-image .#identity-image .#open-webui-image --no-link
nix build .#nixosConfigurations.edge.config.system.build.toplevel .#nixosConfigurations.identity.config.system.build.toplevel .#nixosConfigurations.open-webui.config.system.build.toplevel --no-link
```

Stop on failures. Full identity/WebUI closure builds require real staged SOPS
ciphertext; do not create fake secrets just to make them pass. Seed and edge
checks do not require credentials. Validation builds must not change deployed
image_directory inputs. Capture unavailable tools, keys or host access precisely.

The activation regression suite exercises identity mismatches, failed mounts,
failed transfers and command ordering using mocked native commands. It proves
control-flow guards, not Incus behavior. On a disposable host check a real WebUI
closure from the edge root and require rejection before any profile update.
Then deploy each correct closure and verify its services. Repeat with a missing
metadata value and wrong seed input; both must fail closed.

Validate a first-create plan separately for each root, then update one root and
verify others' infrastructure and generations remain unchanged. Test edge without
identity running, identity certificate bootstrap/renewal, declarative membership
and client reconciliation, and OIDC allowed/denied roles. Confirm Caddy admin port
is closed and route changes require NixOS activation. Restart all affected guests
and test persistent state. Exercise an independent restore.

CI runs whitespace, activation regression tests, provider schema validation,
identity/WebUI module-option evaluation, and builds seeds, edge and the native
Caddy validator. Full secret-consuming closures still need real ciphertext. Record exact passed checks
and pending native/build/live checks in the PR. A green CI does not prove a
healthy deployment. Keep live acceptance records private with revision, date,
environment and observed results.
