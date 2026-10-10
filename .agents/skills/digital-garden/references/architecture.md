# Preserve ownership and compose building blocks

- [Select building blocks](#select-building-blocks)
- [Inspect the current composition](#inspect-the-current-composition)
- [Ownership](#ownership)
- [Preserve resource identity](#preserve-resource-identity)
- [Declare exposure and authentication](#declare-exposure-and-authentication)
- [Compose services with explicit dependencies](#compose-services-with-explicit-dependencies)

Digital Garden composes self-hosted services from declarative infrastructure,
guest configuration, ingress, identity and persistent storage. A new service
selects the pieces it needs. The current AI composition demonstrates those
interfaces; it does not require every future service to use GPU inference or
Open WebUI.

## Select building blocks

| Block | Implementation | Interface for another service |
|---|---|---|
| Resource namespaces | `tofu/projects.tf` | Choose a project by ownership, lifecycle, privileges and budget; see [projects](projects.md) |
| Private network and NixOS seed | `tofu/main.tf`, `nix/hosts/edge-bootstrap.nix`, `flake.nix` | Attach a private NIC to `gardenbr0`; import the immutable seed into each consuming project |
| HTTPS ingress | `nix/modules/edge-ingress.nix` | Add a Caddy virtual host with an explicit public hostname and reachable backend |
| Identity | `nix/modules/edge-auth.nix`, `nix/modules/oidc-client.nix` | Register an OIDC client and configure both issuer and application; specify allowed/denied roles |
| Secret delivery | `.sops.yaml`, `secrets/`, sops-nix in guest modules | Encrypt per consumer; keep its machine key persistent; supply runtime secret files |
| NixOS application guest | `tofu/open-webui.tf`, `nix/hosts/open-webui.nix`, `flake.nix` | Declare guest devices/state in HCL and services in Nix; build, transfer and activate a closure |
| Direct OCI workload | `tofu/llama.tf`, `llama/` | Pin an upstream image digest; declare launch settings, public configuration and persistent mounts |
| Persistent state and recovery | Volume resources in `tofu/`, [recovery](recovery.md) | Store mutable data outside disposable roots and restore it with its matching identities |

These are concrete source files and conventions, not generic modules with a
stable public API. `edge-bootstrap.nix` supplies the current seed defaults,
including its hostname and network policy; inspect and override those assumptions
when composing a new host. Extract a shared module when another consumer needs it, keeping
application names, paths and policy in that consumer's configuration.

## Inspect the current composition

Caddy and Authelia share the NixOS `edge` guest in `default`. Caddy routes
`auth.archaic.work` to Authelia's loopback listener and `ai.archaic.work` to Open
WebUI in project `ai`. Open WebUI authenticates through Authelia OIDC and calls
llama.cpp in `inference` through the private bridge. llama.cpp runs directly as
an Incus OCI container with explicit AMD GPU/KFD devices.

The bridge uses `garden.internal` DNS. Backend reachability must be verified
across projects. Project namespaces and private addresses alone do not enforce
traffic isolation. The inference API has no API-key access control; its callers
must be trusted and its port must not be publicly routed.

## Ownership

| Concern | Authoritative owner |
|---|---|
| Incus projects, networks, images, guests, limits, devices and volume lifecycle | OpenTofu |
| OCI entrypoint, public environment/configuration and running/autostart state | OpenTofu |
| NixOS packages, services, guest network/firewall and application configuration | NixOS |
| Stable managed credentials and cryptographic identities | SOPS + age ciphertext |
| Runtime secret files in NixOS guests | sops-nix |
| Databases, uploads, model cache and ACME state | Applications on explicit persistent volumes |
| Host pools/network roles/GPU support, router rules and wildcard DNS | Operator |

Give each setting one owner. Public ordinary OCI configuration may enter OpenTofu
state; plaintext secrets must never enter OpenTofu inputs/state, the Nix store,
Git or normal logs. See [secret delivery](secrets.md#secret-delivery-for-a-new-service).

Use HCL, Nix and upstream application configuration first. Deployment commands
transfer or activate declared state; keep them from becoming a second
configuration generator. Prefer native commands and short documented procedures
to repository orchestration scripts. Before adding a helper or control plane,
explain the unmet requirement, alternatives and maintenance cost. Use upstream
OCI images pinned by digest; publishing a derived image solely to ship ordinary
configuration adds unnecessary ownership.

## Preserve resource identity

The minimal NixOS seed creates a guest; subsequent closure activation updates
its services. Preserve `image_directory` during maintenance so a service change
does not replace its infrastructure identity. [Activation](activation.md) covers
build, transfer, activation and previous-generation rollback.

Keep persistent volumes independent of guest presence. Backups must survive
host/storage loss; `prevent_destroy` is not a backup. Review image replacement,
project moves, storage changes and secret rotation explicitly. NixOS rollback
does not reverse database migrations.

## Declare exposure and authentication

Caddy owns public HTTP/TLS ingress and persistent ACME state. Wildcard DNS for
`*.archaic.work` is manual; Caddy uses explicit hostname certificates. Inspect
IPv4 and IPv6 routing and guest firewalls, including management API exposure.
Keep backend listeners private and document trusted callers.

Authelia is the shared identity provider. Prefer native OIDC; use forward-auth
when a suitable native integration is unavailable. Public URLs, callback URIs,
client IDs, scopes and claims are ordinary configuration; encrypt client secrets
and signing/private material. Test denied access and role assignment as well as
login. The WebUI [source patch](../../../../nix/patches/README.md) handles pinned upstream
exceptions and must be re-evaluated on upgrades.

## Compose services with explicit dependencies

Model each service as a composition of infrastructure, guest configuration,
network endpoints, identity, secrets and state. Reuse only the blocks it needs.
Describe dependency interfaces rather than requiring a platform-wide task order.

The current resource selector still couples WebUI and inference. Consult
[platform inputs](platform.md#interpret-the-current-resource-selection) for its
exact effects, and [infrastructure reconciliation](infrastructure.md) before
changing selection. Treat that selector as an implementation detail when designing
new services; declare their selection and dependencies deliberately.
