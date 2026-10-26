---
name: digital-garden
description: Develop, review and operate mitschwimmer/digital-garden, self-hosted services on IncusOS with OpenTofu, NixOS, Caddy, Kanidm, SOPS and direct OCI. Use for service setup, configuration changes, software updates, backup, restore, decommissioning, access and diagnostics in this repository.
---

# Work on Digital Garden

Use this shared human/agent handbook. Paths are relative to the repository root.
Start with the requested result and affected source. Load only the relevant
lifecycle stage, technical procedure and service-specific details; links are
navigation, not a reading checklist. Source-only work requires no live bootstrap,
backup or deployment.

## Scope the work

Use a branch for source changes. Inspect the affected source and its owning
reference; check changed version-sensitive interfaces against official docs or
pinned upstream source. Read [architecture](references/architecture.md) for
ownership and inventory discovery, and [composition](references/composition.md)
when adding a service or changing its contract.

Use [the service lifecycle](references/lifecycle.md) for **setup, update config,
update software components, backup, restore and decommissioning**. Find a service's
reference by its system name under `references/`; edge uses `ingress.md`, identity
uses `identity.md`, and the OCI inference workload uses `inference.md` plus
`oci-configuration.md`. Inspect source if a reference does not yet exist.
Do not maintain a second service inventory in this file.

For live operations, inspect current inventory/state and keys/data to preserve;
confirm the requested live change is authorized. Read
[platform inputs](references/platform.md) before targeting a host. Run commands
in `nix develop`; build on the workstation, never IncusOS.
Select one operation root per operation; never copy mutable state, inputs or
plans between roots. Review destructive replacement separately.

## Load technical procedures as needed

| Concern | Owning reference |
|---|---|
| Runtime and isolation | [Placement](references/app-placement.md) |
| Projects, volumes and mount identities | [Projects](references/projects.md) |
| Incus plan/apply | [Infrastructure](references/infrastructure.md) |
| NixOS creation and boot | [Seeds](references/nixos-guests.md), [readiness](references/readiness.md) |
| NixOS rollout and closure rollback | [Deployment](references/deployment.md) |
| Pins, packages and compatibility | [System updates](references/system-updates.md) |
| HTTPS and OIDC integration | [Ingress](references/ingress.md), [identity](references/identity.md) |
| People, roles and enrollment | [Users](references/users.md) |
| Encryption, delivery and rotation | [Secrets](references/secrets.md) |
| Checkpoints and data restoration | [Recovery](references/recovery.md) |
| Resource and data removal | [Retirement](references/retirement.md) |
| Checks for any change | [Validation](references/validation.md) |

For diagnostics, read the affected service's acceptance/diagnostics section; use
readiness for boot failures, deployment for closure rollback, and recovery for
data restoration. Read the [identity ADR](references/adr_identity_provider.md)
only for provider-design decisions.

## Keep ownership explicit

OpenTofu owns Incus resources and OCI lifecycle; NixOS owns guest services;
SOPS/age and sops-nix own managed-secret encryption/delivery; applications own
mutable state on protected volumes. Keep plaintext out of Git, the Nix store,
OpenTofu inputs/state and logs. Preserve seed identity, keys and retained data.

Keep Caddy Nix-configured, without admin API, saved-config resume or auth proxy.
Keep Kanidm directory/clients in `services.kanidm.provision`. Require native OIDC
for published user apps unless a service reference explicitly documents a reviewed
exception and its compensating controls. Declare trusted callers and IPv4/IPv6
exposure. Prefer native HCL/Nix/upstream tools. Justify helpers/control planes by
their unmet requirement and maintenance cost; do not hide programs in Nix strings.
Pin dependencies and give upstream patches explicit removal conditions.
Prefer defaults and concise commands; specify options only when they change
required behavior.

## Finish

Select checks by changed layer from validation; stop dependent operations on
failure. Report passed and unavailable checks, separating source/build/plan
results from live acceptance. Record live results privately with revision, date
and environment. Maintain each procedure once: shared rules in technical/lifecycle
references, service-specific interfaces and exceptions in the owning service
reference, inventory in source. Update shared guidance only when a shared concept
changes. A green CI or successful deployment does not prove health.
