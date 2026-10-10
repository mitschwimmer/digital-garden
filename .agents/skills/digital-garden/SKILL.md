---
name: digital-garden
description: Work on mitschwimmer/digital-garden, Henner's building blocks for self-hosted services on IncusOS with OpenTofu, NixOS, Caddy, Authelia, SOPS and direct OCI workloads. Use for composing services, provisioning and reconciling infrastructure, configuration changes, upgrades, identity and secret management, troubleshooting, backup and recovery, documentation and reviews in this project.
---

# Work on Digital Garden

Use this handbook for human and agent work alike. Select a lifecycle workflow,
identify the building blocks it touches and read only the relevant references.
Workflows describe recurring activities; building blocks describe what services
compose and who owns it. Start from the current installation and requested change.

Interpret source paths relative to the repository root. Run workstation commands
there in the documented fish development shell. Inspect [platform inputs](references/platform.md)
before operating on a target; build on the workstation, never on IncusOS.

## Start every task

1. Inspect the maintained checkout, relevant source and actual state where
   available. State the desired result, affected services and dependencies.
2. Identify resource identities, keys and data to preserve. Distinguish repository
   work from authorized live changes; review destructive replacement separately.
3. Choose a workflow below. Verify changed version-sensitive interfaces against
   official documentation or pinned upstream source.
4. Make changes in a branch and update their owning references. For documentation
   and reviews, verify against source without inventing live operations.

## Select building blocks

Read [architecture](references/architecture.md) for ownership and the current
composition. Use these references for each block's interfaces and operation:

| Building block | Source and reference |
|---|---|
| Resource namespaces and private networking | `tofu/main.tf`, `tofu/projects.tf`; [projects](references/projects.md), [platform inputs](references/platform.md) |
| NixOS seed and guest configuration | `flake.nix`, `nix/hosts/`, `nix/modules/`; [guest provisioning](references/nixos-guests.md), [activation](references/activation.md), [readiness](references/readiness.md) |
| HTTPS ingress | `nix/modules/edge-ingress.nix`, route additions in `edge-auth.nix`; [Caddy](references/ingress.md) |
| Identity and authorization | `nix/modules/edge-auth.nix`, `nix/modules/oidc-client.nix`; [Authelia](references/identity.md) |
| Encrypted identities and runtime secrets | `.sops.yaml`, `secrets/`, consumer Nix configuration; [secret delivery](references/secrets.md) |
| Persistent application state | Volume resources in `tofu/`; [backup and restoration](references/recovery.md) |
| Direct OCI runtime and public configuration | `tofu/llama.tf`, `llama/`; [inference](references/inference.md), [OCI configuration](references/oci-configuration.md) |

Open WebUI is a [service composition](references/open-webui.md) using several
blocks. Reuse its patterns deliberately; replace application-specific names,
paths and policy. Choose [application placement](references/app-placement.md)
from packaging, secret interfaces, state, isolation and hardware requirements.

## Preserve ownership

Give each setting one owner: OpenTofu for Incus resources and OCI lifecycle,
NixOS for guest services, SOPS + age for stable managed secrets, sops-nix for
runtime secret delivery, and applications for mutable state on explicit volumes.
Keep plaintext secrets out of Git, Nix store paths, OpenTofu inputs/state and logs.
Keep seed identity separate from guest updates and protected volumes separate
from backups. Declare trusted callers and public IPv4/IPv6 exposure explicitly.

Prefer HCL, Nix, upstream configuration and native commands. Before adding a
helper or control plane, explain the unmet requirement, alternatives and
maintenance cost. Do not hide a bespoke program in a Nix string or procedure.
Pin dependencies and review upstream patches with explicit removal conditions.

## Workflows

### Compose or extend a service

1. Define purpose, callers, dependencies, state, secrets, hardware and rollback
   behavior. Choose a runtime and project using the block references.
2. Declare infrastructure, private connectivity, resource limits, persistent
   mounts and service selection. Make dependencies explicit; avoid coupling
   unrelated services through today's numeric resource selector.
3. Compose NixOS modules and a flake configuration, or pin an upstream OCI image
   and define supported configuration delivery before startup. Require necessary
   mounts before services can write state.
4. Add ingress, OIDC and secret delivery where needed. Configure both sides of
   integrations and verify allowed/denied access. The current OIDC composition
   contains one WebUI client; extend it while preserving that client.
5. Document the new service's interfaces, operation and recovery. Reconcile
   infrastructure and configure services using the workflows below, then verify
   the resulting behavior and affected dependencies.

### Provision or reconcile infrastructure

Inspect [platform inputs](references/platform.md), inventory and matching state.
Build a missing seed using [guest provisioning](references/nixos-guests.md);
import surviving resources through [recovery](references/recovery.md).
Follow [infrastructure reconciliation](references/infrastructure.md) to review
and apply a whole saved plan. Compare actual changes to declared intent, not
remembered resource counts. Verify affected devices, mounts and connectivity.
NixOS services require separate activation; a successful apply is not service health.

### Configure or upgrade a service

Preserve current resource selection, immutable seed identity and unrelated
services. Back up affected application data before upgrades or storage changes.
Edit the authoritative source and relevant pins; build/validate the affected
configuration. Use [NixOS activation](references/activation.md) for guest services
or [OCI configuration](references/oci-configuration.md) for direct containers.
Apply infrastructure changes only when required. Verify health, authorization,
caller reachability and persistence for the changed service and dependencies.
NixOS rollback does not reverse database migrations.

### Publish a service or change access

Use [ingress](references/ingress.md) for hostname/backend routing, certificates,
manual DNS and IPv4/IPv6 exposure. Use [identity](references/identity.md) for
issuer/client/callback, scopes and role policy; prefer native OIDC, with
forward-auth where a suitable native integration is unavailable. Keep backend
and management endpoints private. Test denied access and role assignment as
well as successful login, and retain working operator access.

### Manage secrets and identities

Follow [secrets](references/secrets.md). Choose reuse, recipient replacement or
intentional rotation explicitly. Persist machine keys independently of disposable
roots; preserve secret values when changing recipients. Coordinate credentials
on both integration endpoints and verify consumer decryption without printing
plaintext. Confirm secured recovery-key backups and application compatibility.

### Diagnose, resume or roll back

Inspect actual state, mounts, runtime configuration, service logs and dependency
reachability. Use [bounded readiness](references/readiness.md) for NixOS boot,
then the affected block/service diagnostics. Stop dependent operations when a
required check fails. Repair declared state and repeat the failed operation;
retain data, keys and seed identity. Do not reset selection, erase state records
or replace storage to repair a service. Use previous closures/configuration and
matching data backups for rollback, then reconcile declared and running state.

### Back up or restore

Use [recovery](references/recovery.md) to preserve matching source, local inputs,
state, seed archives, keys and application data outside the host. Inspect what
survived before choosing state or imports. Restore identities with their data,
reconcile missing infrastructure and configure restored services. Verify an
independent restore and repeat affected service checks; archive inspection alone
is not restoration evidence.

## Validate and finish

Use [validation](references/validation.md) for appropriate native checks. Record
what was inspected, validated, built, planned, applied and verified live. Mark
unavailable checks precisely. A merge, green CI or no-change plan does not prove
a healthy service. Keep acceptance records private with revision, date,
environment and observed results; recheck relevant behavior after changes.

Keep this handbook organized by workflows and building blocks. In a reference,
state relevant inputs and dependencies, ordered actions, expected results and
failure/rollback behavior. Link reusable rules and commands from their owner;
keep one shared set of lifecycle instructions for humans and agents. Complete implementation and its operating documentation together.
