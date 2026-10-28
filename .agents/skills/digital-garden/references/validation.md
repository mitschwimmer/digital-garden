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
| Operation helpers or their tests | Python regression suite | Owning service acceptance |
| HCL, targets, provider pins | Tofu format/schema validation in affected roots | Reviewed whole saved plan; devices/mounts/connectivity |
| One guest's Nix configuration | Format changed Nix; evaluate/build that guest | Its service acceptance |
| `directory.nix` | Format; evaluate Kanidm provisioning; build identity | Reconciliation and user/access checks in [users](users.md) |
| Edge/Caddy routes | Format; native Caddy validator and affected route checks; edge closure | [Ingress checks](ingress.md#check-the-result) |
| OCI public config/artifacts/image/launch | Affected-root provider validation; inspect preset/lock consistency and pinned upstream interface | Owning service acceptance for affected behavior/callers |
| SOPS inputs/recipients | Operator decryption to `/dev/null`; affected consumer closure | Consumer decryption and integration acceptance |
| Shared Nix modules or flake inputs | Format; flake checks; affected seeds/closures and module-option evaluation | Affected consumers, one root at a time |

Changes spanning rows require their union. Follow actual imports to identify
consumers of shared modules/inputs; these can include guests, seeds and workstation
tools. A local directory edit does not affect unrelated guests. Stop on a
failed prerequisite. Discover pin consumers in `flake.nix`, including per-system
input selection and
package overrides; do not assume a shared pin reaches every guest. Read each
affected service reference for its additional interface/acceptance checks. Record
unavailable tools, ciphertext, keys or host access.

## Native commands

Run from the repository root in the development shell. Select the commands
and actual paths/names from the table; placeholders below are not literal inputs.

Whitespace for every change:

```bash
git diff --check
```

Operation helpers/tests:

```bash
python -m unittest discover -s tests -v
```

Nix formatting and an affected guest build (replace NAME and changed paths):

```bash
nixfmt --check CHANGED_NIX_FILES
nix build .#nixosConfigurations.NAME.config.system.build.toplevel --no-link
```

Module-option evaluation: inspect the affected service's public settings, runtime
secret interface and unit mount guards using `nix eval` on its exact attribute
paths. Use the service reference and CI workflow for concrete evaluations; inspect
the pinned module when adding a new interface. Avoid evaluating secret contents.

Provider schema validation in each affected root (replace ROOT):

```bash
tofu -chdir=ROOT fmt -check -diff
tofu -chdir=ROOT init -backend=false -input=false -lockfile=readonly
tofu -chdir=ROOT validate
```

Edge routing uses the native validator:

```bash
nix build .#checks.x86_64-linux.caddy-config --no-link
```

Shared-input checks; build each affected guest as above, and each affected seed
using `nix build .#NAME-image --no-link`:

```bash
nix flake check --no-build
```

Full secret-consuming guest builds require their declared real staged SOPS
ciphertext and other service prerequisites. Do not invent secrets to pass checks
or change deployed `image_directory` inputs for validation. Minimal seeds need no
application credentials. Select additional route/application checks from
`flake.nix` and the owning service reference. Source validation, builds and plans
do not substitute for live acceptance.

## Live acceptance

Read this section for deployment-procedure changes or installation/architecture
acceptance; ordinary service changes use only their affected service checks.

On a disposable guest, build and transfer its closure, run `dry-activate`, switch
with `nixos-rebuild --store-path`, inspect selected/running generations and verify
its services. Exercise rollback to a retained compatible generation and recheck.
Native deployment does not reject another garden system's closure; inspect the
configuration, destination, metadata and mounts before switching.

For a first installation or changes to cross-root ownership/isolation, review
first-create plans per root and update one while verifying other roots' resources
and generations remain unchanged. For affected integrations test edge without
identity, certificate bootstrap/renewal, directory/client reconciliation, OIDC
allowed/denied roles and Caddy's closed admin port. Route changes require NixOS
deployment. Restart affected guests and verify persistence. Recovery changes
require an independent restore.

Routine CI in `.github/workflows/validate.yml` runs formatting, Python tests,
OpenTofu validation, Nix evaluation and focused native application checks. Full
seed-image and selected system builds are available through the manual
`.github/workflows/full-build.yml` workflow instead of every PR/push. Neither
workflow builds every secret-consuming closure or proves live acceptance.
Build the affected guest using [deployment](deployment.md) before switching;
build and retain its system-specific seed before provisioning. Record exact
passed and pending source/build/live checks in the PR; keep live acceptance
records private with revision, date, environment and observed results.
