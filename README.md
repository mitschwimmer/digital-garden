# Digital Garden

Henner's IncusOS homelab: OpenTofu infrastructure, NixOS guests, Caddy ingress,
Authelia identity, private Open WebUI with native OIDC, and direct OCI llama.cpp
with AMD GPU/KFD access. Stable secrets use SOPS + age; mutable application state
and machine identities have separate protected volumes.

Start at the [current operator runbook](docs/runbook.md). It covers a fresh
installation, cumulative acceptance gates, maintenance, interrupted deployment,
and recovery from host loss. All procedures use this checkout, without historical
branches or repository deployment scripts. No migration of the previous install
is required. Existing names must be cleared or recovered deliberately before a
fresh state is applied; unrelated infrastructure must remain untouched.

Manual wildcard A/AAAA DNS for `*.archaic.work`, router rules, IncusOS LAN roles,
storage pools and host GPU support remain operator prerequisites. Backend callers
are trusted explicitly; a private bridge alone is not isolation.

The [versioned homelab skill](.agents/skills/incusos-homelab/SKILL.md) is the
architecture contract. OpenTofu also delivers ordinary non-secret OCI presets;
NixOS and sops-nix own guest configuration and secret delivery. No plaintext secret
belongs in the Nix store or OpenTofu inputs/state.

[Validation evidence](docs/validation.md) distinguishes static inspection from
builds, host plans and live acceptance. The refactor has not been applied to the
host. CI checks whitespace only; operator builds and runtime gates are mandatory.
