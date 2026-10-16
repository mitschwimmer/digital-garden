# Define a service contract

Use [lifecycle setup](lifecycle.md#setup) to implement a new service. Record its
specific contract in one `references/<system>.md` (platform roles may use their
existing reference names). Link to shared procedures instead of copying them.
Use these questions as a completeness check, not a new metadata format or a
requirement to repeat values already declared in source.

| Concern | Record service-specific knowledge |
|---|---|
| Purpose and ownership | Capability, owning root, runtime rationale and component boundaries |
| Callers and dependencies | Trusted callers, startup/rollout order, integration owners, IPv4/IPv6 exposure, OIDC roles or reviewed access exception |
| Setup | Non-obvious host inputs, bootstrap/admin steps and prerequisites beyond the common workflow |
| Config | Owning config interfaces, runtime secret schema/ownership and coordinated changes |
| Software | Pin exceptions, independently upgraded components, supported clients, schema migrations and rollback limits |
| Backup | Durable versus disposable state, consistency group, quiescence/native backup method and key/data coupling |
| Restore | Compatible versions, restore order, irreversible constraints and actual-data acceptance |
| Decommission | Retention/revocation requirements and exceptions to shared retirement |
| Acceptance and diagnostics | Bounded health checks, useful work, allowed/denied access, restart persistence and owning logs |

Choose [placement](app-placement.md) and [project/mount ownership](projects.md).
Compose native modules for NixOS; for OCI pin an image and deliver supported
configuration before startup. Require mounts before writing state. Configure both
ends of integrations and preserve unrelated clients/data. Protected volumes and
local automatic dumps do not replace an independently tested off-host backup.

For a normal new service, edit its source and one service reference, plus actual
integration/registration points. Do not append its name to shared architecture,
placement, platform, secrets, update, validation or recovery guides. Change those
only for a new reusable rule or a correction to an existing procedure. A changed
shared contract must still be documented even if it makes the PR larger.
