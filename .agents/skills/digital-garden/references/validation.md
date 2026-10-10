# Validate changes and record acceptance

Choose checks for the affected building blocks. Distinguish repository review,
native validation, builds, saved plans and live acceptance; one layer cannot
establish another. A documentation-only change needs source/procedure consistency,
link, anchor, fence and whitespace checks, without live deployment.

## Check the affected layers

| Layer | Checks |
|---|---|
| OpenTofu | Formatting, initialized provider schema validation, complete reviewed saved plan |
| NixOS | Formatting/evaluation and affected complete guest closures or seed artifacts |
| Applications | Native configuration validators and any pinned patch's application/behavior |
| Secrets | Public recipient metadata and private operator/consumer decryption without plaintext output |
| Runtime | Mounts, permissions, listeners, devices, bounded health, external HTTPS and restart persistence |
| Identity | Allowed/denied roles, missing/unrelated claims, first/sole-user behavior and intended second factor |
| Recovery | Restore selected data with stable identity and repeat acceptance on an isolated target |

Verify computed addresses and unknowns with a first-create plan; a no-change
plan on an existing host does not cover that case. Guest activation may change
services without infrastructure changes. For GPU inference, require generated
text and actual offload evidence; device enumeration alone is insufficient.
For OIDC, successful login alone does not establish authorization.

## Native workstation checks

Run once for the affected revision in `nix develop --command fish`:

```fish
git diff --check
nixfmt --check flake.nix nix/hosts/*.nix nix/modules/*.nix
tofu -chdir=tofu fmt -check -diff
tofu -chdir=tofu init -backend=false -input=false -lockfile=readonly
tofu -chdir=tofu validate
nix flake check --no-build
nix build .#edge-image --out-link result-edge-image-validation
nix build .#nixosConfigurations.edge-ingress.config.system.build.toplevel .#nixosConfigurations.edge.config.system.build.toplevel .#nixosConfigurations.open-webui.config.system.build.toplevel --no-link
nix build .#checks.x86_64-linux.caddy-config .#checks.x86_64-linux.authelia-config --no-link
```

Use `result-edge-image-validation` only to validate the current seed definition.
Keep the deployed seed's `result-edge-image` GC root and `image_directory`
unchanged. Compare paths when planning an intentional seed change; never copy a
validation output into local deployment inputs as part of routine checks.

Staged ciphertext is needed for the consumer builds. Never generate fixture
secrets just to force CI green. The config check uses clearly synthetic values
inside an isolated derivation, never the real decrypted values. Reuse built
closures during guest activation; do not repeat expensive builds unchanged.
CI only checks whitespace and cannot establish schema, build, plan or live checks.

For infrastructure changes, follow native validation with a whole plan on the
actual target. Include first-create behavior when new resources are introduced; computed bridge addresses and instance outputs must resolve
without treating unknown first-create values as existing-host facts. Inspect
actual changes against inspected inventory and declared intent. No mocked plan proves host behavior.

## Test independent service selection

The plan-only suite in `tofu/tests/service-selection.tftest.hcl` uses a mocked
Incus provider to check all eight service combinations, retained application
volumes, rejection of old selectors and required LAN/GPU inputs. It makes no
live Incus calls. Supply an existing built seed directory so the real seed-input
validation also applies:

```fish
tofu -chdir=tofu test -var "image_directory=$GARDEN_IMAGE"
```

Set `GARDEN_IMAGE` from the retained deployment seed or the separate validation
output. This command does not update local deployment inputs. Mocked plans do
not establish host/provider runtime behavior; review real saved plans and verify
affected services before live application.

## Record verification

Keep a private record for the tested revision:

| Revision | Date | Environment | Service/check | Result and evidence |
|---|---|---|---|---|
| Commit SHA | ISO date | Workstation, target or caller | Exact check exercised | Passed, failed or pending; concise observed result |

A relevant configuration change invalidates or qualifies earlier evidence.
Do not infer live status from historical PR reports, merge or CI. Record
unavailable tools, target access, keys or hardware as precise pending checks.
Use the affected building-block or service reference for live checks. Stop
dependent operations at failures. An inspected backup archive is not an
independent restore test.

Use native validators rather than a second automation layer or tests that merely
repeat implementation strings. Keep CI commands directly reusable by operators.
Do not generate fixture secrets, publish images or add orchestration solely to
broaden CI. Repeat expensive successful checks only after relevant changes,
failures or unresolved concerns.
