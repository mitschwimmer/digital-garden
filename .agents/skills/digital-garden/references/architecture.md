# Own and operate each system independently

This revision is for a fresh IncusOS installation. There is no migration from
`tofu/`, the shared edge seed, or Authelia. Do not apply these roots with old
state or to surviving resources without an explicit recovery design.

| Operation root | Project / instance | Owns |
|---|---|---|
| `platform/` | default bridge; ai, identity, inference projects | Shared network and namespaces |
| `systems/edge/` | default / edge | Caddy, LAN attachment, certificate state |
| `systems/identity/` | identity / identity | Kanidm, directory, ACME and machine key |
| `systems/open-webui/` | ai / open-webui | WebUI, application state and machine key |
| `systems/inference/` | inference / garden-llama | Direct OCI GPU workload, presets and cache |

Each root has its own local inputs, OpenTofu state, provider lock and saved plans.
NixOS roots also have a `target.json`, unique seed and `.operations/` deployment
records. Never copy mutable operation files between roots. Shared Nix source,
flake pins and native procedures are reusable; deployment state is not shared.
Leaf roots look up the existing bridge by name; they do not read platform state.
Provision platform first. The common bridge is a trusted backend network, not a
traffic isolation boundary; namespaces alone do not isolate network access.

OpenTofu owns Incus infrastructure and OCI lifecycle. NixOS owns all guest service
configuration. Caddy only terminates HTTPS and routes requests. Kanidm owns
identity and provides OIDC. Applications must implement native OIDC and enforce
access themselves; applications needing an authentication proxy are unsupported.
The private machine-to-machine inference API is not a published user application.

SOPS owns managed credential ciphertext; sops-nix delivers narrow runtime files.
Applications own mutable state on dedicated protected volumes. Each guest has
its own disposable root; no Nix store or writable volume is shared across guests.
The seed is only for creation; closure deployment updates an existing guest.

The deployment entry point is a deliberately small exception to the preference
for native commands: it binds root, applied target, Incus metadata and closure
identity before changing the profile. Separate shell variables cannot enforce
that relationship. It calls native Nix/Incus commands and generates no service
configuration. It locks operations within a checkout; coordinate across operators.
See [deployment](deployment.md) for its limits and rollback.
