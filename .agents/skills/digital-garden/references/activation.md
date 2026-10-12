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
