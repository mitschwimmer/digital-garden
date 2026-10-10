# Choose application placement

Choose the lightest runtime that keeps configuration, secrets, upgrades,
hardware access and isolation understandable. Inspect these inputs for each
service before selecting a runtime:

- Upstream packaging and pinning options.
- Mutable state, backup and upgrade/rollback behavior.
- Secret interfaces and delivery requirements.
- Hardware, kernel and device requirements.
- Network exposure, trusted callers and identity integration.

## Select the runtime

| Choose | When | Current example |
|---|---|---|
| Direct Incus OCI | A good upstream image packages one application; arguments/public configuration and supported secret files suffice; shared-host-kernel isolation is acceptable | llama.cpp with explicit AMD GPU/KFD mapping |
| NixOS system container | Native modules, several cooperating services, sops-nix, environment-file secrets or reproducible guest rollback simplify ownership | Caddy/Authelia edge; Open WebUI |
| VM | A separate kernel, guest-owned drivers, incompatible container constraints or a stronger isolation boundary is required | Select only for a concrete service requirement |

If options remain comparable, prefer direct OCI, then a NixOS system container,
then a VM. Let secret/configuration maintainability and isolation requirements
change that choice. Re-evaluate per service rather than copying the previous
application's placement.

## Preserve runtime interfaces

Pin accepted OCI images by digest and declare mutable data/models on explicit
persistent volumes. Run OCI directly through Incus. Verify generated output and
actual offload when hardware acceleration is required.

For NixOS, compose packages and services in native modules; supply runtime secret
files through sops-nix and maintain a separate immutable seed identity. Document
closure activation and application-aware rollback.

Declare project scope, callers, state, keys, readiness and restore requirements
using the [shared composition workflow](../SKILL.md#compose-a-new-service),
[project rules](projects.md) and [secret delivery](secrets.md#secret-delivery-for-a-new-service).
