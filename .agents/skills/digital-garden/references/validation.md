# Validate the changed layers

- [Select checks](#select-checks)
- [Native commands](#native-commands)
- [Live acceptance](#live-acceptance)

## Select checks

Run checks for the changed layer and consumers of shared inputs. Documentation
changes need whitespace and local link/anchor checks, plus source inspection for
changed claims/commands. They do not require infrastructure initialization,
closure builds or a live host. CI may run its broader suite independently.

| Change | Required source/build checks | Live checks when deploying |
|---|---|---|
| `operations/activate.py` or its tests | Python regression suite | Deployment guard cases below |
| HCL, targets, provider pins | Tofu format/schema validation in affected roots | Reviewed whole saved plan; devices/mounts/connectivity |
| One guest's Nix configuration | Format changed Nix; evaluate/build that guest | Its service acceptance |
| `directory.nix` | Format; evaluate Kanidm provisioning; build identity | Reconciliation and user/access checks in [users](users.md) |
| Edge/Caddy routes | Format; native Caddy validator; edge closure | [Ingress checks](ingress.md#check-the-result) |
| OCI presets/models/image/launch | Affected-root provider validation; inspect preset/lock consistency and pinned upstream interface | [Inference checks](inference.md#check-the-result) for affected models/callers |
| SOPS inputs/recipients | Operator decryption to `/dev/null`; affected consumer closure | Consumer decryption and integration acceptance |
| Shared Nix modules or flake inputs | Format; flake checks; affected seeds/closures and module-option evaluation | Affected consumers, one root at a time |

Changes spanning rows require their union. A shared pin reaches all three NixOS
guests, seeds and workstation tools; a local directory edit does not. Stop on a
failed prerequisite. Record unavailable tools, ciphertext, keys or host access.

## Native commands

Run from the repository root in the fish development shell. Select the commands
and actual paths/names from the table; placeholders below are not literal inputs.

Whitespace for every change:

```fish
git diff --check
```

Deployment code/tests:

```fish
python -m unittest discover -s tests -v
```

Nix formatting and an affected guest build (replace NAME and changed paths):

```fish
nixfmt --check CHANGED_NIX_FILES
nix build .#nixosConfigurations.NAME.config.system.build.toplevel --no-link
```

Module-option evaluation for changed identity/WebUI interfaces:

```fish
nix eval .#nixosConfigurations.identity.config.services.kanidm.provision --json > /dev/null
nix eval .#nixosConfigurations.identity.config.services.kanidm.server.settings --json > /dev/null
nix eval .#nixosConfigurations.identity.config.systemd.services.kanidm.unitConfig --json > /dev/null
nix eval .#nixosConfigurations.open-webui.config.services.open-webui.environment --json > /dev/null
```

Provider schema validation in each affected root (replace ROOT):

```fish
tofu -chdir=ROOT fmt -check -diff
tofu -chdir=ROOT init -backend=false -input=false -lockfile=readonly
tofu -chdir=ROOT validate
```

Edge routing uses the native validator:

```fish
nix build .#checks.x86_64-linux.caddy-config --no-link
```

Shared-input checks; build each affected guest as above, and each affected seed
using `nix build .#NAME-image --no-link`:

```fish
nix flake check --no-build
```

Full identity/WebUI builds require real staged SOPS ciphertext. Do not invent
secrets to pass checks or change deployed `image_directory` inputs for validation.
Seed/edge checks need no credentials. Source validation, builds and plans do not
substitute for live acceptance.

## Live acceptance

Read this section for deployment-code changes or installation/architecture
acceptance; ordinary service changes use only their affected service checks.

The regression suite mocks native commands: it proves guard/control flow, not
Incus behavior. On a disposable host, require rejection of a WebUI closure from
edge before profile mutation; also reject missing metadata and wrong seed input.
Then deploy correct closures and verify their services.

For a first installation or changes to cross-root ownership/isolation, review
first-create plans per root and update one while verifying other roots' resources
and generations remain unchanged. For affected integrations test edge without
identity, certificate bootstrap/renewal, directory/client reconciliation, OIDC
allowed/denied roles and Caddy's closed admin port. Route changes require NixOS
deployment. Restart affected guests and verify persistence. Recovery changes
require an independent restore.

CI checks whitespace, deployment regressions, provider schemas, identity/WebUI
module options, seeds, edge and Caddy validation. Record exact passed and pending
source/build/live checks in the PR; keep live acceptance records private with
revision, date, environment and observed results.
