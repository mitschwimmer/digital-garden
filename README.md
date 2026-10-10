# Digital Garden

Compose self-hosted digital services from IncusOS infrastructure, NixOS guests,
Caddy HTTPS ingress, Authelia identity, SOPS + age secrets and direct OCI
workloads. The current composition combines a shared edge, private Open WebUI
with native OIDC and llama.cpp with AMD GPU/KFD access.

## Follow the project handbook

Start with [Work on Digital Garden](.agents/skills/digital-garden/SKILL.md).
Humans and agents share its lifecycle workflows: compose services, reconcile
infrastructure, configure and upgrade, publish and manage access, maintain
identities, troubleshoot, and back up or restore. Select the building blocks
needed for the activity and follow their referenced operating procedures.

## Establish the execution environment

Use a Nix workstation and authenticated Incus client. Inspect host storage,
network roles, AMD support, router rules and manual wildcard A/AAAA DNS for
`*.archaic.work` before live changes. Host, domain and hardware settings belong
to this installation; adapt them deliberately for another target.

CI checks whitespace. Verify the affected configuration and running behavior
using the handbook; a successful apply alone does not establish service health.
