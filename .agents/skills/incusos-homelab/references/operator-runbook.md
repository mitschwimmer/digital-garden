# Operator runbook and milestone contract

## Current runbook

Maintain one current runbook entry point, for example docs/runbook.md, linked from the project README. Split capability procedures into linked documents when useful. Make current instructions work from the maintained branch at a recorded revision. Keep historical iteration reports separate.

State the execution environment, pinned tools, authenticated target, selected project/pool, local input locations, and required manual host/router/DNS setup. Give commands in the operator's established shell; keep placeholders confined to a clearly identified input step.

Support these workflows explicitly:

| Workflow | Preserve | Establish or restore |
|---|---|---|
| Fresh installation | Existing unrelated infrastructure | New state, identities, volumes, guests and configuration |
| Rebuild after host reset | Stable secrets and backed-up application data | State strategy, host prerequisites, machine identities, volumes, guests and configuration |
| Maintenance | Infrastructure identity and unrelated capabilities | One reviewed configuration/version change and its acceptance |
| Extension | Accepted earlier milestones | New capability and its dependencies |

Do not rerun initialization against existing ciphertext. Do not promise to restore databases or model caches from Git.

## Capability milestones

Prefer this baseline sequence; adapt to the actual repository and requested capability:

| Milestone | Gate before continuing |
|---|---|
| Private network and minimal guest | Boot, DNS, outbound HTTPS and restart work |
| Caddy ingress | External trusted HTTPS, intended IPv4/IPv6 reachability and persistent ACME state |
| Authelia | SMTP, login, TOTP and persistent identity work |
| Open WebUI with native OIDC | Intended roles allowed, unrelated/missing groups denied, application state retained |
| GPU inference | Generated text actually uses GPU; model switching and cache persistence work |
| Recovery | Selected backups, stable secrets and application data successfully restore |

Attach prerequisites to each milestone. A new independent application need not repeat unrelated acceptance; recheck affected dependencies after maintenance.

Align HCL and Nix modules with meaningful capabilities and keep their dependency interfaces small. Document a native, cumulative way to reach each milestone from the current revision. Do not use routine OpenTofu targeting or chronological Git checkouts as the architecture.

If stage selection is used, show how advancing preserves earlier resources. Treat selecting an earlier stage or disabling a stateful capability as a removal plan requiring separate review, not a troubleshooting reset. Keep stable resource identities and persistent storage independent of disposable guests.

## Required procedure per milestone

1. State the goal, prerequisites and expected starting state.
2. Identify relevant declarative modules and local inputs.
3. Give native formatting/evaluation/build/configuration checks and explain their limits.
4. Give exact plan/apply/activation commands in execution order and say where each runs.
5. State expected additions, updates, replacements and deletions for the documented starting state. Review the full actual plan before applying.
6. Give acceptance commands and browser/external checks with observable successful results.
7. Provide troubleshooting and a safe retry/resume path for partially completed work.
8. Give rollback or recovery instructions, identifying retained identities, volumes and backups.
9. State the continuation gate and the next dependent milestone.

Never advance after a failed gate. Separate configuration validation from live acceptance. Treat missing hardware, keys, public routing or credentials as precise prerequisites, not TODOs hidden behind an apparently complete milestone.

## Acceptance evidence

Record revision, milestone, check, result (passed, failed, or pending), execution environment and date. Use a concise operator checklist or local record; committing private inventory/logs is unnecessary.

Invalidate or qualify evidence when the relevant configuration changes. A merge alone does not mark a gate passed. A guest activation may change services without changing OpenTofu's infrastructure plan.

## Recovery and rollback

Document saved-plan review, previous NixOS generation/configuration, and application-data restoration separately. System rollback does not reverse database migrations. Back up irreplaceable data before detaching, replacing, reformatting or deleting storage.

Avoid changing infrastructure identity and persistent-data layout together when separable. Keep cleanup of old resources a distinct explicit deletion list. After rollback, explain declared-versus-running differences and what must be reconciled before resuming.

Deliver the complete runbook for the requested scope even when runtime acceptance remains pending. Wait for operator results only when actively guiding live buildup.
