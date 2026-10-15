# Update software components

Guests use declared pinned software. An unchanged rebuild fetches no new packages;
do not upgrade channels or install packages inside guests. IncusOS owns the
kernel and has a separate host update lifecycle.

## Identify the version owner and consumers

Inspect `flake.nix`, `flake.lock`, package expressions and root-local image/model
locks. Follow the actual input-to-system selection rather than assuming every
guest uses the shared pin. A package override, service-specific nixpkgs input,
database major, extension and OCI image may each advance independently. Read the
owning service reference for supported versions, client compatibility, upstream
patch removal conditions and migrations. Shared pin changes reach all consumers,
including seeds and workstation tools; a separate service pin need not.

## Update and roll out

1. Record revision, locks and affected running closures/image digests. Preserve
   deployment records/GC roots and [matching data backups](recovery.md#backup).
   Review release notes and migrations for each changed component.
2. For an exact-revision flake input, edit that input's URL deliberately, then run
   `nix flake update INPUT_NAME` with its actual name. Lock regeneration alone
   cannot advance a fixed revision. Change following relationships intentionally;
   review `git diff -- flake.nix flake.lock`. For separately pinned packages or
   images, update the owning expression/lock and its integrity metadata instead.
3. Inspect affected module/package interfaces and independently versioned
   databases/extensions. Retain `system.stateVersion` unless separately reviewing
   state compatibility; it is not the installed version. A database major update
   needs its native migration procedure, not just a changed package declaration.
4. Run [validation](validation.md) for changed layers and all affected consumers,
   including seeds/closures and service-specific interface checks. Full consumer
   builds need real staged ciphertext. Re-enter `nix develop --command fish` after
   tool pin changes. Commit reviewed changes before live rollout.
5. Choose a dependency-aware rollout/window; [deploy NixOS](deployment.md) or use
   the OCI workload's stop/plan/apply procedure one root at a time. Stop on failure.
   Preserve deployed seed archives and `image_directory`: upgrading software must
   not replace a guest through its creation image. Validate seeds separately.
6. Complete service acceptance and record deployed revision/closure or digest.
   Keep recovery declarations, closures and matching backups until accepted.

For failure, use [closure rollback](deployment.md#resume-and-rollback) or the
workload's OCI rollback. Check data compatibility first and use
[data rollback](recovery.md#data-rollback) when needed. A Git revert does not
change running guests. Leave unaffected roots alone.

Source: [Nix flake update](https://nix.dev/manual/nix/2.28/command-ref/new-cli/nix3-flake-update).
