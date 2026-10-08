# Validation and acceptance evidence

This refactor replaces historical branch-by-branch guides with the cumulative
[runbook](runbook.md). Earlier build/host evidence belongs to earlier revisions
and does not establish acceptance of the changed configuration.

## Native workstation checks

Run once for the affected revision in `nix develop --command fish`:

```fish
git diff --check
nixfmt --check flake.nix nix/hosts/*.nix nix/modules/*.nix
tofu -chdir=tofu fmt -check -diff
tofu -chdir=tofu init -backend=false -input=false -lockfile=readonly
tofu -chdir=tofu validate
nix flake check --no-build
nix build .#edge-image --out-link result-edge-image
nix build .#nixosConfigurations.edge-ingress.config.system.build.toplevel .#nixosConfigurations.edge.config.system.build.toplevel .#nixosConfigurations.open-webui.config.system.build.toplevel --no-link
nix build .#checks.x86_64-linux.caddy-config .#checks.x86_64-linux.authelia-config --no-link
```

Staged ciphertext is needed for the consumer builds. Never generate fixture
secrets just to force CI green. The config check uses clearly synthetic values
inside an isolated derivation, never the real decrypted values. Reuse built
closures during milestone activation; do not repeat expensive builds unchanged.
CI only checks whitespace and cannot establish schema, build, plan or live gates.

Native validation must be followed by a real first-create whole plan and plan at
each advanced stage; computed bridge addresses and instance outputs must resolve
without treating unknown first-create values as existing-host facts. Inspect
actual changes against the runbook counts. No mocked plan proves host behavior.

## Refactor evidence

Base inspected: `eb3fa85f6050bec18a6695a57a1dfab91c183579` on 2026-10-06.
Implementation evidence is recorded in the PR for its final head revision.

| Layer | Result in this execution environment |
|---|---|
| Repository ownership/runbook/reference inspection | Completed; current skill and pinned upstream interfaces reviewed |
| Whitespace, document links, JSON/YAML, Nix/HCL syntax and patch application | Passed locally; patch dry-run against pinned WebUI 0.11.4 |
| Native Nix/OpenTofu formatting/evaluation/schema validation | Pending: these binaries are absent here |
| Full seed/guest/config builds | Pending on Nix workstation |
| Real saved plans, first-create and advanced-stage applies | Pending on authenticated target |
| HTTPS, SMTP/TOTP, OIDC allow/deny, GPU output, restart persistence | Pending on host/browser/external caller |
| Independent backup restoration | Pending on isolated restore target |

Keep a local acceptance record with revision, milestone/check, passed/failed/pending,
environment and date. Do not commit private inventory/logs. A changed relevant
configuration invalidates its earlier evidence; no-change OpenTofu plans do not
prove guest activation or authentication correctness. Stop at every failed gate.

## Application-project placement evidence (2026-10-08)

This change keeps shared edge services in `default`, places WebUI in `ai` and
llama.cpp in `inference`, and updates activation, backup, restore and import scopes.
The initial fresh-install plan now expects 13 managed resource additions. This
section supersedes earlier evidence for affected project placement procedures.

| Check | Result |
|---|---|
| OpenTofu 1.9.0 `fmt -check -diff` | Passed |
| Initialization with pinned Incus provider 1.2.0 and read-only lockfile | Passed; provider signature verified |
| OpenTofu `validate` | Blocked by execution sandbox: provider Unix socket creation is not permitted; schema validation remains pending |
| Whitespace, relative document links and application-command project scopes | Passed |
| Nix guest configuration | Unchanged; existing builds remain an operator prerequisite |
| First-create/advanced-stage plans and host acceptance | Pending on authenticated IncusOS target; nothing applied |

Repeat native schema validation on the workstation, inspect the complete saved
plans against the updated milestone counts, and verify edge-to-WebUI and
WebUI-to-inference DNS/HTTP reachability across projects before accepting stages
4 and 5. Project namespaces alone do not establish network access controls.
