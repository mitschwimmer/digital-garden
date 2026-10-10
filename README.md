# Digital Garden

Digital Garden is Henner's collection of building blocks for self-hosted digital
services on IncusOS. OpenTofu describes infrastructure, NixOS configures system
containers, Caddy provides HTTPS ingress, Authelia provides identity, and SOPS +
age keeps stable secrets encrypted. Services compose these pieces according to
their needs.

The current composition is an AI service: a shared Caddy/Authelia edge, private
Open WebUI with native OIDC, and direct OCI llama.cpp with AMD GPU/KFD access.
It is a working configuration to extend, rather than a general-purpose deployment
framework. Host addresses, domains and hardware choices are specific to this
installation.

## Work with the project

Humans and agents use the same project documentation:

| Goal | Start here |
|---|---|
| Understand the building blocks and their ownership | [Architecture](docs/architecture.md) |
| Change configuration or compose another service | [Contribution guide](docs/contributing.md) |
| Choose a runtime and resource namespace | [Application placement](docs/app-placement.md), [Incus projects](docs/projects.md) |
| Deploy or maintain the current composition | [Operator runbook](docs/runbook.md) |
| Manage keys, ciphertext and secret delivery | [Secrets](docs/secrets.md) |
| Check a change and record acceptance | [Validation](docs/validation.md) |
| Back up or restore an installation | [Recovery](docs/recovery.md) |
| Change inference models or presets | [OCI configuration](docs/06-oci-config.md) |

The repository's [Digital Garden skill](.agents/skills/digital-garden/SKILL.md)
helps agents select and follow these documents. Project conventions live in
`docs/`, alongside the procedures used by human contributors and operators.

Deployment requires a Nix workstation and authenticated Incus client. Host
storage, IncusOS network roles, AMD support, router rules and wildcard A/AAAA DNS
for `*.archaic.work` are manual prerequisites. See the runbook before applying
anything. CI checks whitespace; it does not establish build or live acceptance.
