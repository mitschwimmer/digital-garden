# Validation without a second automation layer

Place validation at the relevant operator milestone. Use the strongest available non-destructive native checks and record their scope.

| Layer | Checks |
|---|---|
| OpenTofu | Formatting, initialized provider schema validation, reviewed saved plan |
| Nix | Formatting/evaluation and builds of affected guest closures or artifacts |
| Applications | Native configuration validators where supported |
| Secrets | Recipient metadata and controlled recovery/decryption without plaintext output |
| Runtime | Listeners, mounts, permissions, devices, service health, external HTTPS and restart |
| Identity | Allowed/denied roles, first/sole user, missing/unrelated claims and intended second factor |
| Recovery | Restore selected data and stable identity, then repeat acceptance |

Verify computed values and unknowns on a first-create plan; do not assume an existing-host no-change plan covers a fresh host. Inspect provider schemas before relying on resource syntax.

For NixOS guests, check the affected complete closure, not only individual configuration fragments. Check a seed image when its definition changes or a fresh build depends on it. A mocked plan does not prove host behavior.

For GPU inference, device enumeration alone is insufficient: require successful generated output and evidence that computation is offloaded. For authentication, successful login alone is insufficient: exercise denial and role assignment, including bootstrap-user behavior.

Prefer manual/native checks to custom test runners. Use tool-native HCL/Nix checks only when they protect a meaningful invariant; do not add tests that merely mirror implementation strings. If an upstream patch is required, justify its maintenance cost, pin its source, document its removal condition and verify the affected behavior.

## CI policy

CI is optional. Do not add scripts, custom fixture generators, source-extracting test programs or image publishing solely to make CI comprehensive. Keep any CI commands native and directly reusable from the runbook.

Separate static/configuration checks, builds, plans and live acceptance. A successful lightweight workflow must not imply unperformed build or runtime validation. Record unavailable checks precisely and leave their operator gates pending.

Do not require repeated expensive checks after a revision passes unless changes, failures or unresolved concerns justify them.
