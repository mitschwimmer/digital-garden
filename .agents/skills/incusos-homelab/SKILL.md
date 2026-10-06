---
name: incusos-homelab
description: Build, maintain, extend, and rebuild Henner's IncusOS homelab using modular OpenTofu HCL and Nix, direct Incus OCI workloads, Caddy, Authelia, and SOPS plus age. Produce a current operator runbook with cumulative, independently verified milestones. Use for fresh or reset hosts, recovery, service additions, infrastructure changes, identity integration, upgrades, and homelab IaC reviews.
---

# IncusOS Homelab

Maintain reproducible desired state and an operator runbook that can build or restore the homelab from the current repository. Prefer OpenTofu HCL, Nix, native application configuration, and existing tool commands. Minimize repository-maintained scripts.

## Start every task

1. Inspect the current repository, relevant host facts, and runbook. Identify whether the task is fresh installation, rebuild/recovery, maintenance, extension, or review.
2. Verify version-sensitive provider schemas, IncusOS networking, NixOS modules, OCI interfaces, and authentication behavior against official documentation or pinned upstream source.
3. Identify the affected capability and its milestone dependencies. Keep infrastructure identity and persistent-data changes separately reviewable.
4. For implementation, produce actual declarative files and update the current runbook together. Make the requested scope complete and applicable.
5. Validate with available native tools. Report separately what was statically checked, built, planned, and verified on the host.

Read [architecture](references/architecture.md) for ownership and topology and [operator runbook](references/operator-runbook.md) for the milestone contract. Read [application placement](references/app-placement.md) when adding a workload, [secrets and recovery](references/secrets.md) when handling identities or credentials, and [validation](references/validation.md) when choosing checks.

## Make milestones the deployment contract

Use small vertical capabilities as persistent operator checkpoints: private guest, ingress, identity, application login, inference, and recovery. Make milestones cumulative, with explicit prerequisites and observable acceptance gates.

Small milestones govern application and troubleshooting. They do not require stopping implementation after one slice or leaving later rebuild instructions unwritten. Complete the requested configuration and runbook; stop live application at a failed gate. When guiding an operator interactively, wait for that gate's result before advancing dependent milestones.

Keep the runbook applicable to the maintained branch. Do not require deleted PR branches, remembered conversation steps, or successive historical commits. Separate historical evidence from current instructions. Document how to resume an interrupted milestone without recreating accepted resources or rotating identities.

## Preserve ownership

- OpenTofu owns Incus projects, networks, volumes, profiles, instances, limits, devices, image identity, and OCI launch settings. Permit provider-supported delivery of ordinary non-secret OCI configuration when it is the simplest coherent approach.
- NixOS owns packages, services, firewall, Caddy, Authelia, application configuration, and sops-nix delivery inside NixOS guests. Nix may generate ordinary configuration artifacts where useful.
- SOPS plus age owns the encrypted Git source of truth for stable managed secrets. Never route decrypted values through OpenTofu configuration/state or the Nix store.
- Applications own mutable databases, uploads, indexes, model downloads/cache, and Caddy ACME/certificate state. Give meaningful state explicit persistent volumes.
- Give each setting one authoritative owner. A deployment command transfers or activates desired state; it must not become another configuration generator or controller.

Keep manual wildcard A/AAAA DNS for *.archaic.work outside automation unless the user changes this decision. Keep Caddy as public HTTP/TLS ingress and Authelia as identity provider. Prefer native OIDC; use forward-auth when suitable native OIDC is unavailable.

Do not introduce Kubernetes, Vault, Consul, nested Docker/Podman, a service mesh, custom image publication, or another control plane without a concrete requirement.

## Keep the implementation small

Do not add repository-maintained Bash, Python, or other helper programs for preparation, deployment, orchestration, or validation when HCL, Nix, native configuration, or a short documented procedure suffices. Do not move a large bespoke program into an inline runbook block or Nix string to evade this rule.

Use ordinary Nix build commands, small service wrappers, and native application files where necessary. Prefer upstream OCI images pinned by digest; do not build a derived image merely to package configuration that existing tools can deliver.

Before introducing a helper, explain the unmet requirement, alternatives, maintenance cost, and why native tools or an operator procedure are insufficient. Treat it as an architectural exception. If authorization already covers that exception, proceed; otherwise present the concrete decision. Do not add scripts merely because CI or a convenient all-in-one command makes them tempting.

## Keep the baseline practical

Prefer an edge NixOS system container running Caddy and Authelia, a private Open WebUI NixOS system container with sops-nix and native OIDC, and a private direct OCI llama.cpp workload with AMD GPU/KFD mapping. Re-evaluate placement per application; these are defaults, not universal laws.

Inspect IncusOS network roles and actual bridges before designing LAN attachment. Keep backend and management endpoints private. Treat public IPv6 as real exposure and specify intended listeners and firewalls. Document which callers are trusted; a separate bridge or private address alone does not prove isolation.

## Preserve rebuildability

Pin accepted dependencies and OCI images; make upgrades explicit reviewed changes. Adapt to existing layout, using capability modules and documented dependencies rather than gratuitous reorganization.

Provide current workflows for fresh installation, recovery with existing identities/data, and changes to an existing installation. Explain key restoration or recipient updates, OpenTofu state recovery, storage restoration, and manual host/router/DNS prerequisites. Never treat protected volumes as a backup.

Record acceptance evidence tied to the tested revision without committing raw private inventory or secrets. Do not equate merge, green CI, or a no-change infrastructure plan with a verified running service.

## Finish implementation work

Summarize declarative changes, runbook milestones, manual prerequisites, observed validation, and pending operator checks. Link the current apply, acceptance, troubleshooting/resume, and recovery procedures.

Do not change live services or destructively replace resources unless the user authorized that scope. Reviews and skill-only changes need findings and validation, not invented host-apply commands.

Completion means the operator can build or restore the capability from the current repository, verify its checkpoint, and resume after failure using the documented procedure.
