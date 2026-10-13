---
name: digital-garden
description: Develop, review and operate mitschwimmer/digital-garden, self-hosted services on IncusOS with OpenTofu, NixOS, Caddy, Kanidm, SOPS and direct OCI. Use for this repository's source, documentation, service composition, deployment, upgrades, access, secrets, diagnostics and recovery.
---

# Work on Digital Garden

Use this shared human/agent handbook. Paths are relative to the repository root.
Start with the requested result and affected source; load only the route below
and the sections needed for that action. Links are navigation, not a reading
checklist. Follow an operational prerequisite when performing the dependent step;
do not load bootstrap, deployment or recovery procedures for a source-only task.

## Scope the work

For source changes or reviews, inspect the affected files and their owning
reference. Use a branch for changes and update operating documentation alongside
implementation. Check changed version-sensitive interfaces against official
documentation or pinned upstream source.

For live operations, inspect current inventory and state, identify keys/data to
preserve, and confirm the requested live change is authorized. Read
[platform inputs](references/platform.md) before targeting a host. Run commands
in `nix develop --command fish`; build on the workstation, never IncusOS.
Select one operation root per operation; never copy mutable state, inputs or
plans between roots. Review destructive replacement separately.

## Route the task

| Task | Start with | Load additionally when needed |
|---|---|---|
| Documentation or review | Affected source and its owning reference below | No live procedures unless reviewing them |
| Ownership, dependencies or placement | [Architecture](references/architecture.md), [placement](references/app-placement.md) | [Projects](references/projects.md) for resource/mount identities |
| Compose or extend a service | [Composition](references/composition.md) | Only the blocks the service uses |
| Provision or change Incus resources | [Infrastructure](references/infrastructure.md), affected root's HCL | [Seeds](references/nixos-guests.md) for creation; [readiness](references/readiness.md) for NixOS boot |
| Change a NixOS service | `systems/<name>/configuration.nix` and its service reference | [Deployment](references/deployment.md) for live rollout |
| Update NixOS pins/packages | [System updates](references/system-updates.md), `flake.nix`, `flake.lock` | Affected package/service references |
| Add, change or remove people | [Users](references/users.md), `systems/identity/directory.nix` | Enrollment section for new credentials |
| Change HTTPS or OIDC | [Ingress](references/ingress.md) or [identity](references/identity.md) | Both only when changing their integration |
| Change OCI presets/image/launch | [OCI configuration](references/oci-configuration.md), `systems/inference/` | [Inference](references/inference.md#check-the-result) for runtime acceptance |
| Secrets/recipients/rotation | Relevant section of [secrets](references/secrets.md) | Fresh encryption/key installation only for bootstrap |
| Diagnose or roll back | Affected service's diagnostics; deployment or OCI rollback section | Readiness for boot failures; recovery for data restoration |
| Back up, restore or retire | [Recovery](references/recovery.md) or [retirement](references/retirement.md) | Only affected service checks |

Service references: [Caddy](references/ingress.md), [Kanidm](references/identity.md),
[Open WebUI](references/open-webui.md), [llama.cpp](references/inference.md).
Read the [identity ADR](references/adr_identity_provider.md) only for provider-design decisions.

## Keep ownership explicit

OpenTofu owns Incus resources and OCI lifecycle; NixOS owns guest services;
SOPS/age and sops-nix own managed-secret encryption/delivery; applications own
mutable state on protected volumes. Keep plaintext out of Git, the Nix store,
OpenTofu inputs/state and logs. Preserve seed identity, keys and retained data.

Keep Caddy Nix-configured, without admin API, saved-config resume or auth proxy.
Keep Kanidm directory/clients in `services.kanidm.provision`. Published user apps
require native OIDC; declare trusted callers and IPv4/IPv6 exposure explicitly.
Prefer native HCL/Nix/upstream tools. Justify new helpers/control planes by their
unmet requirement and maintenance cost; do not hide programs in Nix strings.
Pin dependencies and give upstream patches explicit removal conditions.

## Finish

Select checks by changed layer from [validation](references/validation.md);
stop dependent operations on failure. Report passed and unavailable checks,
separating source/build/plan results from live acceptance. Record live results
privately with revision, date and environment. Maintain each procedure once in
its owning reference; a green CI or successful deployment does not prove health.
