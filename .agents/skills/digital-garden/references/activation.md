# Activate one NixOS system

Use the repository fish development shell and enter the intended system root.
The root, not ambient GARDEN_* variables, selects the system. Example:

```fish
cd systems/edge
python ../../operations/activate.py deploy
```

For identity/WebUI, prepare and stage their ciphertext first. All newly added
flake files must be Git-tracked. Complete infrastructure reconciliation and
[readiness](readiness.md) before activation; back up application state before
upgrades that may change its schema.

The entry point reads this root's applied `deployment` output, requires the
default Tofu workspace, compares it with target.json, verifies independently
provisioned Incus metadata and required mounts, then builds exactly one system.
It captures the build's JSON store path and rejects a mismatched closure before
transfer. Export and import must both succeed. Immediately before profile
mutation it rechecks metadata, mounts and the imported closure identity.

There are no separate instance/config/project flags and no reused result link.
Each build gets a private `.operations/<id>/` directory and candidate GC root.
Build/transfer failures leave the guest profile untouched and may have no record.
Before switching, a deployment record captures the running generation (the
rollback target) separately from the selected profile. The running closure is rooted on the guest
at `/nix/var/nix/gcroots/garden-<id>-previous`. The local lock stops concurrent
operations in the same checkout. Operators using different checkouts must
coordinate; this is an accidental-misdeployment guard, not access control against
a privileged host administrator or protection against concurrent host replacement.

## Check the result

The command verifies the running closure, selected units and absence of failed
units. Finish the service's external, allowed/denied login, persistence and restart
checks. Deployment success alone is not acceptance. Record revision and observed
results privately; the record's revision does not imply a clean Git worktree.

To inspect a locally built closure against this root without mutating a guest:

```fish
python ../../operations/activate.py check /nix/store/EXACT-SYSTEM-CLOSURE
```

A WebUI closure checked from edge must fail. Do not change metadata or copy output
links to bypass this failure. The automated regression suite exercises this
mismatch before profile mutation; repeat on a disposable live installation.

## Resume and rollback

After a failed switch, retain the original attempt's record even when retrying: a
partially switched system is not necessarily healthy. On failure retain the record and inspect journals/mounts. Profile selection may
have succeeded even when switching failed. Fix the declared prerequisite and
repeat deploy, or roll back using that exact attempt's record:

```fish
python ../../operations/activate.py rollback .operations/ATTEMPT/deployment.json
```

The rollback verifies root, destination and the previous closure's identity
before mutation. A previously misdeployed foreign closure is deliberately
rejected; deploy the correct system instead. A rollback to the minimal seed
stops application services and will fail service acceptance: do this only as an
explicit recovery step. NixOS rollback does not reverse database migrations;
restore matching data if needed. After acceptance remove obsolete candidate and
previous-generation GC roots deliberately, preserving the selected recovery point.

## Update system software

NixOS guests run closures built from this repository's pinned inputs. Rebuilding
without changing the pins/configuration does not fetch newer packages. There is
no guest-local channel upgrade or package installation step. The IncusOS host
owns the kernel and has a separate update lifecycle; direct OCI inference updates
use [OCI configuration](oci-configuration.md).

1. Record the current source revision, lock file and each affected guest's running
   closure. Preserve its activation record/GC roots and take matching application
   data backups as in [recovery](recovery.md). Review upstream release notes for
   compatibility and database migrations, especially Kanidm and WebUI.
2. Select a reviewed nixpkgs commit and edit `inputs.nixpkgs.url` in `flake.nix`.
   It contains an exact revision: `nix flake update nixpkgs` alone will keep that
   revision. Change the sops-nix URL only when intentionally updating it; its
   nixpkgs input follows the shared pin. From the repository root, regenerate
   the selected locks and inspect both source and lock diffs:

   ```fish
   nix flake update nixpkgs
   # Only after intentionally changing inputs.sops-nix.url:
   nix flake update sops-nix
   git diff -- flake.nix flake.lock
   ```

3. Inventory every consumer of the shared inputs: edge, identity and open-webui,
   plus seed builds and workstation tools. Review module-option/package changes,
   Kanidm's versioned client and secret-provisioning variant, and the separately
   pinned WebUI package in `nix/packages/open-webui.nix`. Updating nixpkgs does
   not automatically advance that application pin. Retain `system.stateVersion`
   unless a separately reviewed state-compatibility change requires it; it is
   not the installed NixOS version.
4. Run [validation](validation.md), including all affected system closure builds
   and integration-specific checks. Stage real encrypted inputs for consumers.
   Re-enter `nix develop -c fish` after changing pins so workstation tools match.
   Commit the reviewed source and lock changes before live rollout.
5. Choose a dependency-aware rollout order and maintenance window. Enter one
   affected system root and run the activation procedure above, verify its
   service-specific checks, then repeat for the next root. Stop the rollout on
   any failure. A shared lock update does not activate all guests automatically.
   Existing guests keep their immutable deployed seed archives and OpenTofu
   `image_directory` inputs; do not replace a guest to deliver software updates.
6. Verify external reachability, OIDC allowed/denied roles, persistent mounts and
   data, and restart behavior for affected services. Record each deployed source
   revision, running closure and acceptance result. Retain recovery closures
   and backups until the rollout is accepted.

For failure, use the affected attempt's rollback record as described above and
reconcile source/pins to the intended running version. Inspect migration support
before starting an older service against upgraded data; restore a matching backup
when required. Do not roll back unaffected roots or assume a Git revert changes
running guests. Rebuilding seeds for future provisioning is separate from
updating existing guests.

Source: [Nix flake update](https://nix.dev/manual/nix/2.28/command-ref/new-cli/nix3-flake-update).
