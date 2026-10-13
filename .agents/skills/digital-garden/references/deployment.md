# Deploy a NixOS configuration

- [Deploy](#deploy)
- [Check the result](#check-the-result)
- [Resume and rollback](#resume-and-rollback)

Use this for building, transferring and switching an existing guest to its
configuration. NixOS calls the final step `switch-to-configuration switch`;
activation is one part of that switch. The repository entry point remains
`operations/activate.py`. Pin/package changes use [system updates](system-updates.md).

## Deploy

Use the fish development shell and enter the intended system root:

```fish
cd systems/edge
python ../../operations/activate.py deploy
```

Before deploying, complete any required [infrastructure reconciliation](infrastructure.md)
and [readiness](readiness.md). Identity/WebUI require staged ciphertext and their
own installed machine key. Track new flake files in Git. Back up application data
before upgrades or storage changes; review schema migrations and rollback limits.

The command binds the root's applied `deployment` output to `target.json`, the
default Tofu workspace, Incus metadata and required mounts. It builds one system,
checks the closure identity, and requires successful export/import. Immediately
before profile mutation it rechecks metadata, mounts and the imported identity,
sets the system profile and runs `switch-to-configuration switch`.

Each attempt uses a private `.operations/<id>/` directory and candidate GC root.
Build/transfer failures leave the profile untouched and may produce no deployment
record. Before switching, a record captures the running closure separately from
the selected profile; the previous closure is rooted on the guest at
`/nix/var/nix/gcroots/garden-<id>-previous`.

The lock coordinates one checkout only: coordinate other operators/checkouts.
These guards prevent accidental misdeployment, not privileged host changes.
Do not bypass identity failures by changing metadata or copying output links.

## Check the result

The command checks the running closure, selected units and absence of failed
units. Complete the affected service's external access, authorization, persistence
and restart checks. Record observed results privately; the recorded Git revision
does not imply a clean worktree.

To check a locally built closure without changing the guest profile:

```fish
python ../../operations/activate.py check /nix/store/EXACT-SYSTEM-CLOSURE
```

This still requires the applied target and live metadata/mount checks. A WebUI
closure checked from edge must fail.

## Resume and rollback

Retain the failed attempt's record and inspect journals/mounts. Profile selection
may have succeeded while switching failed. Repair the declared prerequisite and
repeat deploy, or use that attempt's rollback record:

```fish
python ../../operations/activate.py rollback .operations/ATTEMPT/deployment.json
```

Rollback verifies the root, destination and previous closure identity. A foreign
previous closure is rejected: deploy the correct system instead. Returning to a
minimal seed stops application services and is an explicit recovery operation.
NixOS rollback does not reverse database migrations; use matching
[data recovery](recovery.md) when required. Reconcile source with running state.
After acceptance, prune obsolete candidate/previous-generation GC roots while
preserving the selected recovery point.

Source: [NixOS system switch](https://github.com/NixOS/nixpkgs/blob/0d9e9b832d03ac387417e16ce1febf73b2e631e1/nixos/doc/manual/development/what-happens-during-a-system-switch.chapter.md).
