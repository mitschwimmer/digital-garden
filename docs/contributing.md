# Working on Digital Garden

Use this workflow for human and agent contributions: configuration changes,
upgrades, new services, documentation and reviews. Read [architecture](architecture.md)
first, then the procedure for the capability you are changing.

## Find the right source

| Change | Sources and guidance |
|---|---|
| Incus resources, mounts, limits or guest selection | `tofu/`; [projects](projects.md), [runbook](runbook.md) |
| Guest packages, services, firewall or application settings | `nix/hosts/`, `nix/modules/`, `flake.nix`; [activation](activation.md) |
| Public routes or authentication policy | Caddy/Authelia modules and consuming application; [ingress](02-caddy-ingress.md), [identity](03-authelia.md) |
| Keys, recipients or secret consumers | `.sops.yaml`, `secrets/`, consumer Nix configuration; [secrets](secrets.md) |
| Inference image, models or launch settings | `llama/`, `tofu/llama.tf`; [OCI configuration](06-oci-config.md) |
| Dependency upgrade or upstream exception | `flake.nix`, `flake.lock`, `tofu/.terraform.lock.hcl`, image/model locks, `nix/patches/`; [validation](validation.md) |

Make changes in a branch from the maintained revision. Identify the intended
behavior, affected dependencies, existing state to preserve and acceptance
checks before editing. For a documentation-only change, inspect the relevant
source; do not manufacture host operations or runtime acceptance.

## Compose a new service

1. Describe the service's purpose, callers, state, secret interfaces, hardware
   needs and upgrade/rollback behavior. Choose [placement](app-placement.md)
   and a [project](projects.md) from those needs.
2. Declare infrastructure in `tofu/`: explicit project, private NIC, image,
   resource limits, persistent data volumes and required devices. Use stable
   resource identities. Reuse shared networking; grant LAN/GPU access only where
   required. Specify how the service is selected without making unrelated
   capabilities prerequisites.
3. For NixOS, add a host composition and a flake configuration, reusing or
   extracting the relevant modules. Keep its seed import project-local. For OCI,
   pin the upstream image and use supported launch/configuration interfaces;
   define delivery-before-start and update/restart behavior.
4. Add [secret delivery](secrets.md#secret-delivery-for-a-new-service) if needed.
   Keep machine identities and mutable state on persistent mounts. Declare
   readiness and mount prerequisites so services cannot write irreplaceable
   state into a disposable root.
5. If public access is needed, add the Caddy hostname/backend and document DNS,
   routing and IPv4/IPv6 exposure. For OIDC, configure issuer/client/callback,
   scopes and role policy on both sides; encrypt matching client credentials.
   The current `oidc-client.nix` describes one WebUI client and `edge-auth.nix`
   builds a single-client list. Extend that composition while preserving the
   existing client; it is not yet a generic client registry.
6. Document deployment, health, allowed/denied access, restart persistence,
   failure resume, rollback and data restoration. Link the service from the
   README and runbook; update the architecture map if it adds a reusable block.
7. Run the relevant [validation](validation.md). Review the complete OpenTofu
   plan before live application and repeat affected dependency gates. A new
   independent service need not recheck unrelated accepted services.

For example, another NixOS web application can reuse the private seed/network,
Caddy ingress and Authelia, while declaring its own guest, data volume and secret
consumer. It need not use the llama workload. Treat Open WebUI as a concrete
example: replace its names, paths, roles and application settings rather than
copying its AI-specific policy wholesale.

## Keep changes maintainable

Keep infrastructure identity and persistent-data changes separately reviewable.
Preserve existing ciphertext and keys unless rotation is the intended change.
Pin dependencies and record why an upstream patch exists and when it can be
removed. Verify changed version-sensitive interfaces using official documentation
or the pinned upstream source.

Prefer native configuration and commands over bespoke scripts or new control
planes. Explain architectural exceptions before implementing them. Do not move
a large program into a Nix string or documentation block to hide its cost.

Update implementation and its shared operating instructions together. Put a
project convention here or in the relevant `docs/` page, and link it from the
agent skill when needed. Avoid separate human and agent copies of the same rule.

## Write an operating procedure

For a new or changed capability, include:

- Goal, prerequisites, starting state, source files and local inputs.
- Commands in the established fish workstation environment, with the execution
  location and expected infrastructure changes; review the whole saved plan.
- Build/transfer/activation steps where needed, followed by bounded readiness
  checks and observable acceptance results.
- A retry path that preserves accepted resources, data and keys; rollback and
  recovery with matching backups where application state changes.
- The gate before dependent work and which earlier gates need rechecking.

Use the maintained checkout, not historical branches or remembered chat steps.
Keep placeholders in the input step. Run commands separately and stop live
application at a failed gate; complete the documentation even if live validation
is unavailable. See [runbook](runbook.md) and [readiness](readiness.md).

## Deliver a contribution

Describe the resulting behavior, affected blocks, operational/data impact and
checks performed. Distinguish static review, native validation, builds, plans and
live acceptance. Mark unavailable checks precisely; do not infer a healthy
service from merge, CI or a no-change plan. Keep private inventory, state, plans,
keys and secret-bearing logs outside Git. Record live acceptance privately with
revision, date, environment, check and result.
