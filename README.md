# Digital Garden

Henner's new IncusOS homelab, recreated incrementally from fresh desired state.

Start with [the private NixOS edge bootstrap](docs/01-edge-bootstrap.md).
The current branch includes the inventory tool and the first deployable configuration.
It has not been applied to the homelab.

## Architecture

- OpenTofu owns Incus infrastructure and instance devices.
- NixOS owns guest services and configuration.
- Suitable single applications run directly as Incus OCI containers.
- SOPS + age owns stable managed secrets; sops-nix delivers guest secrets at runtime.
  Plaintext secrets never pass through OpenTofu.
- Caddy and Authelia will share a NixOS edge container; prefer native application OIDC.
- Open WebUI will run in a NixOS container; llama.cpp will run privately as an OCI container with AMD GPU access.
- Persistent application state lives on explicit volumes. Caddy owns its ACME state.
- Manual wildcard A/AAAA DNS for *.archaic.work remains outside automation.

The former mitschwimmer/homelab repository is reference material.
No old state or data is imported. Old services stay available during bootstrap;
their eventual cleanup is separate from new infrastructure provisioning.

## Read-only inventory

From an authenticated Incus client workstation:

```sh
incus remote list
bash scripts/inventory.sh YOUR_REMOTE
incus network show YOUR_REMOTE:YOUR_BRIDGE
```

Review output before sharing it in the conversation. Do not commit raw inventory to this public repository.

## Useful requirements from the old configuration

Auth, Grafana, Prometheus, llama.cpp, Open WebUI and a shared Pi service were present.
llama.cpp used a model router, persistent cache, AMD GPU access and /dev/kfd.
Open WebUI's example hostname was ai.archaic.work.
The former example base domain was mitschwimmer.de; the new baseline uses archaic.work.

See the bootstrap document for validation, exact apply commands, verification and rollback.
