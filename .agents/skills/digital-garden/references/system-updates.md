# Update NixOS system software

Guests use this repository's pinned closures. An unchanged rebuild fetches no
new packages; do not upgrade channels or install packages inside guests. IncusOS
owns the kernel and has a separate update lifecycle. OCI updates use
[OCI configuration](oci-configuration.md).

1. Record revision, locks and each affected running closure. Preserve deployment
   records/GC roots and [matching data backups](recovery.md). Review release notes
   and migrations, especially Kanidm/WebUI.
2. Select a reviewed nixpkgs commit and edit `inputs.nixpkgs.url`. It pins an exact
   revision; lock regeneration alone cannot advance it. Change sops-nix only
   intentionally; its nixpkgs follows the shared pin. From the repository root:

   ```fish
   nix flake update nixpkgs
   # Only after intentionally changing inputs.sops-nix.url:
   nix flake update sops-nix
   git diff -- flake.nix flake.lock
   ```

3. Inventory consumers: edge, identity, WebUI, seeds and workstation tools.
   Review module/package interfaces, Kanidm's versioned client/secret-provisioning
   variant and the separate WebUI pin in `nix/packages/open-webui.nix`. nixpkgs
   updates do not advance that application pin. Retain `system.stateVersion`
   unless separately reviewing state compatibility; it is not the installed version.
4. Run the shared-input checks in [validation](validation.md), including affected
   closures with real staged ciphertext. Re-enter `nix develop --command fish`
   so tools match the pins. Commit reviewed changes before live rollout.
5. Choose a dependency-aware order/window; [deploy](deployment.md) and verify one
   root at a time. Stop on failure. Preserve deployed seed archives and
   `image_directory`: software updates must not replace guests. Rebuilding seeds
   for future creation is separate from updating existing guests.
6. Record each deployed revision, closure and affected service acceptance.
   Keep recovery closures/backups until accepted.

On failure use the affected attempt's [rollback](deployment.md#resume-and-rollback).
Check migration compatibility before older code opens upgraded data; restore a
matching backup when required. Leave unaffected roots alone. A Git revert does
not change running guests.

Source: [Nix flake update](https://nix.dev/manual/nix/2.28/command-ref/new-cli/nix3-flake-update).

Immich has its own `inputs.nixpkgs-immich.url` and lock node. Update that exact
revision with `nix flake update nixpkgs-immich`, then validate/build only the
Immich guest and seed (plus integration consumers if their source changes).
The shared pin does not advance Immich. Read [Immich](immich.md) for client
compatibility, database migrations and matching media/database rollback.
