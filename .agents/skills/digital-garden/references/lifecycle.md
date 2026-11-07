# Operate a service through its lifecycle

Use the requested stage and the affected service reference. Discover current
resources and pins from [source](architecture.md). Source-only work stops after
editing and validation.

- [Setup](#setup)
- [Update config](#update-config)
- [Update software components](#update-software-components)
- [Backup](#backup)
- [Restore](#restore)
- [Decommission](#decommission)

## Setup

1. Define the [contract](composition.md), runtime, callers and persistence in one
   service reference. Declare resources, integrations and relevant CI checks.
   Register NixOS configurations/seeds in `flake.nix`.
2. Validate changed layers. For live setup, inspect [platform inputs](platform.md)
   and existing inventory; provision platform dependencies first.
3. For NixOS, build its [seed](nixos-guests.md), reconcile
   [infrastructure](infrastructure.md), check [readiness](readiness.md), install
   its [machine key](secrets.md#install-each-machine-key) if needed, and
   [deploy](deployment.md). For OCI, follow the service's preparation/start gates.
4. Follow bootstrap order: edge before identity ACME, identity before dependent
   OIDC login, private first-admin setup before normal application access.
5. Complete service acceptance and establish a tested off-host recovery point.

## Update config

1. Edit owning source and affected integrations. Identify access, secret and data
   changes; preserve unchanged identities and checkpoint risky live changes.
2. [Validate](validation.md) changed layers and consumers. Reconcile infrastructure
   only when HCL/inputs/devices change. NixOS config alone uses closure deployment.
3. Roll out in dependency order. For OCI mounted-file updates, stop before file
   delivery and restart through a reviewed whole plan as the service specifies.
4. Test affected callers and behavior, including denial/revocation. On failure,
   stop dependents and follow the service's rollback/data-recovery constraints.

## Update software components

Follow [system updates](system-updates.md) to identify pins and consumers, review
migrations, validate and roll out. Existing-guest upgrades use closures, not
creation-image replacement or a changed `system.stateVersion`.

## Backup

Follow [recovery: backup](recovery.md#backup) with the service's consistency group.

## Restore

Follow [recovery: restore](recovery.md#restore), or
[data rollback](recovery.md#data-rollback) after incompatible migrations.

## Decommission

Follow [retirement](retirement.md) for integration withdrawal, access revocation,
retention and owned-resource removal.
