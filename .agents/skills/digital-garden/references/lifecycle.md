# Operate a service through its lifecycle

Use only the stage needed for the requested result. Read the affected service's
reference for concrete inputs, dependencies, credentials, migration constraints
and acceptance. Use source for current resource identities and pins as described
in [architecture](architecture.md). Do not execute live steps for source-only work.

- [Setup](#setup)
- [Update config](#update-config)
- [Update software components](#update-software-components)
- [Backup](#backup)
- [Restore](#restore)
- [Decommission](#decommission)

## Setup

1. Define the [service contract](composition.md); choose runtime, callers,
   dependency order and persistence. Add one service reference containing only
   its specific requirements and exceptions.
2. Declare its root, project, resources and persistent mounts. Register NixOS
   configurations/seeds in `flake.nix`; add affected checks to CI. Change shared
   platform, ingress or identity source only where the service integrates.
3. Validate changed layers. For live setup, inspect [platform inputs](platform.md)
   and existing inventory. Reconcile platform dependencies before the leaf root.
4. For NixOS, build its unique [seed](nixos-guests.md), review/apply its
   [infrastructure](infrastructure.md), check [readiness](readiness.md), install
   its own [machine key](secrets.md#install-each-machine-key) if needed, and
   [deploy](deployment.md). For OCI, deliver declared config before startup via
   its root's whole plan; use its runtime-specific acceptance, not NixOS switching.
5. Follow the service's bootstrap/access order. Edge must precede identity's ACME
   issuance, and identity must precede dependent OIDC login. Complete first-admin
   setup privately before opening application access where required.
6. Verify actual service work, allowed/denied access and restart persistence.
   Establish an off-host checkpoint and prove independent restoration before
   relying on the service's backups.

## Update config

1. Inspect the owning source, contract and affected integrations. Change declared
   config, not guest files or UI settings that compete with Nix/OpenTofu.
2. Identify changed state, access and secrets; take a matching checkpoint before
   risky live changes. Preserve machine keys and unchanged credential values.
3. Validate only changed layers and their consumers. Reconcile infrastructure
   only if HCL/inputs/devices change. A NixOS service/directory config change alone
   uses deployment, without a seed rebuild or infrastructure apply.
4. Roll out in dependency order. OCI mounted-file updates must stop the workload
   before file delivery and let a reviewed whole plan restart it. Follow the
   workload's update procedure for exact ordering.
5. Test affected behavior and callers, including denial/revocation for access
   changes. If acceptance fails, stop dependents and use the service's rollback
   path; closure/config rollback alone does not undo mutable application state.

## Update software components

Use [system updates](system-updates.md) to identify the actual pin/package/image
owner and all consumers. Review application, database, extension, client and
host-kernel compatibility independently. Preserve a matching data checkpoint and
previous declarations/closures. Validate and roll out one affected root at a time;
keep recovery material until service-specific acceptance passes. Do not change
creation seeds or `system.stateVersion` to upgrade existing software.

## Backup

Use [recovery: backup](recovery.md#backup) for a consistent off-host checkpoint.
Include all state/key volumes and the service's declared consistency group, not
just a database dump. Record source/pins and restore prerequisites. Treat on-host
snapshots, protected volumes and automatic local dumps as inputs to backup,
never as proof of recovery.

## Restore

Use [recovery: restore](recovery.md#restore). Inspect survivors, reconcile owning
state and select compatible software before starting it against restored data.
Restore keys, ciphertext and coupled data together. Use an isolated target and
test actual restored content, access and persistence before reopening traffic.
Follow [data rollback](recovery.md#data-rollback) when an upgrade changed schemas.

## Decommission

Use [retirement](retirement.md) to withdraw integrations, revoke access, retain
recovery material and remove only owned resources. Distinguish disabling service
access from authorization to delete data. Shared dependencies outlive consumers.
