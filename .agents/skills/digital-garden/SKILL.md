---
name: digital-garden
description: Work on mitschwimmer/digital-garden, Henner's building blocks for self-hosted services on IncusOS with OpenTofu, NixOS, Caddy, Authelia, SOPS and direct OCI workloads. Use for repository changes, new service composition, upgrades, documentation, reviews, deployment and recovery in this project.
---

# Digital Garden

Use the same project documentation as human contributors. Read
[the project map](../../../README.md), [architecture](../../../docs/architecture.md)
and [contribution workflow](../../../docs/contributing.md) before choosing a change.
Treat the current AI service as one composition of the building blocks. Inspect
actual source and local inputs rather than assuming the whole stack must be
bootstrapped for every task.

## Select task references

| Task | Read |
|---|---|
| Add or restructure a service | [Placement](../../../docs/app-placement.md), [projects](../../../docs/projects.md), and the contribution guide's composition workflow |
| Deploy, maintain or resume | [Runbook](../../../docs/runbook.md), then only the affected capability procedures |
| Change NixOS guest configuration | [Activation](../../../docs/activation.md), [readiness](../../../docs/readiness.md) |
| Change ingress or identity | [Ingress](../../../docs/02-caddy-ingress.md), [Authelia](../../../docs/03-authelia.md), and the consuming application's procedure |
| Handle secrets or restore data | [Secrets](../../../docs/secrets.md), [recovery](../../../docs/recovery.md) |
| Change OCI inference or models | [Inference](../../../docs/05-inference.md), [OCI configuration](../../../docs/06-oci-config.md) |
| Validate or upgrade | [Validation](../../../docs/validation.md), affected lockfiles and [patch notes](../../../nix/patches/README.md) |

## Execute the requested scope

1. Identify the affected blocks, dependencies and state to preserve from the
   shared docs and source. Verify changed version-sensitive interfaces against
   official documentation or pinned upstream source.
2. Follow the contribution workflow and put project decisions and procedures
   into the shared docs alongside the implementation. Keep this skill as
   navigation; avoid parallel architecture rules or duplicated shell commands.
3. Run checks appropriate to the change. For live operation, inspect actual
   inventory and use the runbook's plan, activation and acceptance procedures;
   stop dependent application at a failed gate.
4. Report the concrete changes, validation performed and remaining operator
   gates. Distinguish static inspection, builds, plans and live acceptance.

For reviews and documentation work, inspect and edit the repository without
changing live services. Obtain authorization before live deployment or destructive
replacement when it is outside the requested scope. Preserve existing identities
and data during retries and recovery as described in the shared procedures.
