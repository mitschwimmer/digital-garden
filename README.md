# Digital Garden

Compose self-hosted digital services from IncusOS infrastructure, NixOS guests,
Caddy HTTPS ingress, Authelia identity, SOPS + age secrets and direct OCI
workloads. The current composition combines a shared edge, private Open WebUI
with native OIDC and llama.cpp with AMD GPU/KFD access.

## Follow the project handbook

Start with [Work on Digital Garden](.agents/skills/digital-garden/SKILL.md).
The skill is the shared handbook for humans and agents: start every task,
select the relevant references, preserve ownership, compose a capability,
validate it and record acceptance. Its references hold the detailed rules and
native operating procedures; there is one documentation contract for both audiences.

## Establish the execution environment

Use a Nix workstation and authenticated Incus client. Inspect host storage,
network roles, AMD support, router rules and manual wildcard A/AAAA DNS for
`*.archaic.work` before deployment. Host, domain and hardware settings belong to
this installation; adapt them deliberately for another target.

Treat the current configuration as a composition to extend. Its five-stage HCL
selector is cumulative; define explicit dependencies for additional services.
CI checks whitespace. Require the handbook's build, plan and live gates before
accepting a running capability.
