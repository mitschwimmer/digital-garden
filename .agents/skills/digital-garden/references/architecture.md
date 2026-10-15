# Own and operate each system independently

This revision targets a fresh IncusOS installation. There is no migration from
`tofu/`, the old shared seed or Authelia. Do not apply these roots with old state
or over surviving resources without an explicit recovery design.

## Concepts and authoritative sources

| Concept | Meaning | Discover current declarations |
|---|---|---|
| Service | A capability with callers, dependencies and lifecycle requirements; may contain several software components | Its `references/<system>.md` and owning system source |
| Operation root | Independent OpenTofu ownership/state boundary | `platform/` and `systems/*/` containing `main.tf` |
| Platform | Shared backend bridge and project namespaces | `platform/main.tf` |
| System | Guest owned by one leaf root, with its own runtime and persistent volumes | `systems/<name>/main.tf` |
| Deployment identity | Binding of root, guest and NixOS closure; distinct from application login identity | Root's `target.json`, `target.tf` and applied `deployment` output |
| Component | Independently versioned application, database, extension, image or supporting package | `flake.nix`, `flake.lock`, package expressions and root-local locks |
| Persistent state | Application data, signing/encryption identity and machine keys that must survive root replacement | Root's HCL devices/volumes, target mounts and service consistency requirements |
| Integration | Route, OIDC client, caller policy or other dependency spanning owners | Owning ingress/identity/caller configuration |

Inspect these declarations instead of maintaining service lists or storage tables
in shared references. `flake.nix` declares NixOS systems, seed outputs and input
selection. Applied state/inventory establish what actually exists; source alone
does not prove a deployment. Service references explain semantics absent from
source, especially consistency, bootstrap, migration and acceptance constraints.

Each root has its own local inputs, OpenTofu state, provider lock and saved plans.
NixOS roots also have `target.json`, a unique seed and `.operations/` deployment
records. Never copy mutable operation files between roots. Shared Nix source,
flake pins and procedures are reusable; deployment state is not shared. Leaf
roots look up the existing bridge by name; they do not read platform state.
Provision platform first. Namespaces do not isolate traffic on the trusted bridge.

OpenTofu owns Incus resources and OCI lifecycle. NixOS owns guest configuration.
Caddy terminates HTTPS/routes requests; Kanidm owns identity/OIDC. Published user
applications implement native OIDC and enforce access themselves. Review any
exception explicitly in its service reference, including exposure and compensating
controls; an existing exception is not a default for new services. Private backend
APIs require explicitly trusted callers and must not be published.

SOPS owns managed ciphertext; sops-nix delivers narrow runtime files. Applications
own mutable state on protected volumes. Each guest has its own disposable root;
no Nix store or writable volume is shared across guests. Seeds are for creation;
closure deployment updates existing NixOS guests.

The deployment entry point is a small exception to the preference for native
commands: it binds root, applied target, metadata and closure identity before
changing the profile. It calls native Nix/Incus commands and generates no service
configuration. It locks within one checkout; coordinate across operators. See
[deployment](deployment.md) for limits and rollback.
