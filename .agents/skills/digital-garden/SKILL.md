---
name: digital-garden
description: Work on mitschwimmer/digital-garden, Henner's building blocks for self-hosted services on IncusOS with OpenTofu, NixOS, Caddy, Authelia, SOPS and direct OCI workloads. Use for repository changes, new service composition, upgrades, documentation, reviews, deployment and recovery in this project.
---

# Work on Digital Garden

Use this handbook for human and agent work alike. Compose digital services from
the project's building blocks; follow the same ownership, change and acceptance
contracts when reviewing, extending or operating them. Read
[architecture](references/architecture.md) to understand the current composition.
Load only the detailed references needed for the task. Interpret source paths
relative to the repository root and run workstation command blocks there,
inside the documented fish development shell.

## Start every task

1. Inspect the maintained checkout and relevant source. Identify whether the task
   is review, documentation, configuration, extension, deployment or recovery.
2. State the intended behavior, affected building blocks and dependencies,
   existing identities/data to preserve, and observable acceptance checks.
3. Read the task's references below. Verify changed version-sensitive interfaces
   against official documentation or pinned upstream source.
4. Make repository changes in a branch. Complete implementation and operating
   instructions together. Apply live changes only within the requested scope;
   treat destructive replacement or data loss as an explicit separate decision.

For reviews and documentation changes, inspect the source and validate the
result without inventing deployment steps or runtime acceptance.

## Select task references

| Change | Sources and guidance |
|---|---|
| Incus resources, mounts, limits or guest selection | `tofu/`; [projects](references/projects.md), [runbook](references/deployment.md) |
| Guest packages, services, firewall or application settings | `nix/hosts/`, `nix/modules/`, `flake.nix`; [activation](references/activation.md) |
| Public routes or authentication policy | Caddy/Authelia modules and consuming application; [ingress](references/ingress.md), [identity](references/identity.md) |
| Accept the current service capabilities | [Private guest](references/private-guest.md), [ingress](references/ingress.md), [identity](references/identity.md), [WebUI](references/open-webui.md), [inference](references/inference.md) |
| Boot readiness or NixOS activation | [Readiness](references/readiness.md), [activation](references/activation.md) |
| Backups, host loss or data restoration | [Recovery](references/recovery.md) |
| Keys, recipients or secret consumers | `.sops.yaml`, `secrets/`, consumer Nix configuration; [secrets](references/secrets.md) |
| Inference image, models or launch settings | `llama/`, `tofu/llama.tf`; [OCI configuration](references/oci-configuration.md) |
| Dependency upgrade or upstream exception | `flake.nix`, `flake.lock`, `tofu/.terraform.lock.hcl`, image/model locks, `nix/patches/`; [validation](references/validation.md) |

## Compose a new service

1. Describe the service's purpose, callers, state, secret interfaces, hardware
   needs and upgrade/rollback behavior. Choose [placement](references/app-placement.md)
   and a [project](references/projects.md) from those needs.
2. Declare infrastructure in `tofu/`: explicit project, private NIC, image,
   resource limits, persistent data volumes and required devices. Use stable
   resource identities. Reuse shared networking; grant LAN/GPU access only where
   required. Specify how the service is selected without making unrelated
   capabilities prerequisites.
3. For NixOS, add a host composition and a flake configuration, reusing or
   extracting the relevant modules. Keep its seed import project-local. For OCI,
   pin the upstream image and use supported launch/configuration interfaces;
   define delivery-before-start and update/restart behavior.
4. Add [secret delivery](references/secrets.md#secret-delivery-for-a-new-service) if needed.
   Keep machine identities and mutable state on persistent mounts. Declare
   readiness and mount prerequisites so services cannot write irreplaceable
   state into a disposable root.
5. If public access is needed, add the Caddy hostname/backend and document DNS,
   routing and IPv4/IPv6 exposure. For OIDC, configure issuer/client/callback,
   scopes and role policy on both sides; encrypt matching client credentials.
   The current `oidc-client.nix` describes one WebUI client and `edge-auth.nix`
   builds a single-client list. Extend that composition while preserving the
   existing client; it is not yet a generic client registry.
6. Document deployment, health, allowed/denied access, restart persistence,
   failure resume, rollback and data restoration. Link the service from the
   README and runbook; update the architecture map if it adds a reusable block.
7. Run the relevant [validation](references/validation.md). Review the complete OpenTofu
   plan before live application and repeat affected dependency gates. A new
   independent service need not recheck unrelated accepted services.

For example, another NixOS web application can reuse the private seed/network,
Caddy ingress and Authelia, while declaring its own guest, data volume and secret
consumer. It need not use the llama workload. Treat Open WebUI as a concrete
example: replace its names, paths, roles and application settings rather than
copying its AI-specific policy wholesale.

## Preserve the project conventions

Keep infrastructure identity and persistent-data changes separately reviewable.
Preserve existing ciphertext and keys unless rotation is the intended change.
Pin dependencies and record why an upstream patch exists and when it can be
removed. Verify changed version-sensitive interfaces using official documentation
or the pinned upstream source.

Prefer native configuration and commands over bespoke scripts or new control
planes. Explain architectural exceptions before implementing them. Do not move
a large program into a Nix string or documentation block to hide its cost.

Keep one authoritative owner per setting: OpenTofu for Incus and OCI lifecycle,
NixOS for guest services, SOPS + age for stable managed secrets, sops-nix for
runtime secret delivery, and applications for mutable state on explicit volumes.
Follow the [ownership contract](references/architecture.md#ownership).
Keep seed identity separate from guest configuration and backups separate from
protected volumes. Keep backend callers and public exposure explicit.

Put detailed decisions and commands in the relevant reference and link them
here. Keep this handbook and its references authoritative for both humans and
agents; do not add a parallel contribution guide or agent-only runbook.

## Document a capability contract

Write procedures in this order. Use imperative headings and observable results.

| Section | Required content |
|---|---|
| Contract | Goal, dependencies, starting state, declarative sources, execution location, inputs and expected infrastructure effects |
| Execute | Ordered native build, plan/apply, transfer and activation steps; stop conditions before dependent commands |
| Verify | Bounded readiness, service/access checks, allowed/denied roles and restart persistence where applicable |
| Resume and rollback | Diagnosis, safe retry with retained state/keys, previous generation/configuration and matching data restoration |
| Acceptance gate | Conditions that must pass before the capability or a dependent capability is accepted |

For reference pages that define policy rather than execution, use imperative
rules, decision tables and links to the applicable capability contract. Keep
commands in procedures, and keep reusable rules in their owning reference.

Use the maintained checkout, not historical branches or remembered chat steps.
Keep placeholders in the input step. Run commands separately and stop live
application at a failed gate; complete the documentation even if live validation
is unavailable. See [runbook](references/deployment.md) and [readiness](references/readiness.md).

## Validate and finish

Describe the resulting behavior, affected blocks, operational/data impact and
checks performed. Distinguish static review, native validation, builds, plans and
live acceptance. Mark unavailable checks precisely; do not infer a healthy
service from merge, CI or a no-change plan. Keep private inventory, state, plans,
keys and secret-bearing logs outside Git. Record live acceptance privately with
revision, date, environment, check and result.
