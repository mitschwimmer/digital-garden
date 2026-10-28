# Deploy a NixOS configuration

- [Deploy](#deploy)
- [Check the result](#check-the-result)
- [Resume and rollback](#resume-and-rollback)

Build on the workstation, transfer through authenticated Incus, and let
`nixos-rebuild` manage the guest's system profile and switch. Guests have no SSH
listener, so `nixos-rebuild --target-host` is not used. Pin/package changes use
[system updates](system-updates.md).

## Deploy

Before deploying, complete any required [infrastructure reconciliation](infrastructure.md)
and [readiness](readiness.md). Compare the chosen root's `target.json` with
`tofu output -json deployment`, Incus metadata and required mounts. Select the
matching flake configuration and destination explicitly; native commands do not
bind them or reject another garden system's closure. Coordinate operators.
Secret-consuming guests require their staged ciphertext and installed machine key.
Track new flake files in Git. Back up application data before upgrades or storage
changes; review schema migrations and rollback limits.

For edge, enter `nix develop` at the repository root, then run the following in
Bash. Replace YOUR_REMOTE with this root's applied remote. For another system,
use its flake name, project and instance from its own declarations.

```bash
set -euo pipefail
cd systems/edge
remote=YOUR_REMOTE
nix build ../..#nixosConfigurations.edge.config.system.build.toplevel --out-link result
closure=$(readlink -f result)
requisites=$(nix-store --query --requisites "$closure")
# Nix store paths contain no whitespace; split the requisites into arguments.
nix-store --export $requisites | incus exec "$remote:edge" --project default -T -- nix-store --import
incus exec "$remote:edge" --project default -T -- \
  "$closure/sw/bin/nixos-rebuild" switch --store-path "$closure" --no-reexec
```

Stop if build or transfer fails. `--store-path` uses the imported closure without
building in the guest; `--no-reexec` avoids evaluating a guest-local configuration
to rebuild the tool. Use the tool from the candidate closure, including when
updating an older guest. Both pinned nixpkgs inputs provide this interface.
Keep `result` until acceptance; system profile generations retain switched
closures on the guest. There are no custom attempt records, locks or GC roots.

## Check the result

Using the same destination as above:

```bash
incus exec "$remote:edge" --project default -- readlink -f /run/current-system
incus exec "$remote:edge" --project default -- readlink -f /nix/var/nix/profiles/system
incus exec "$remote:edge" --project default -- systemctl is-active caddy
incus exec "$remote:edge" --project default -- systemctl --failed --no-pager
```

Require both paths to equal the intended closure, all units listed in this root's
`target.json` to be active and no failed units. For a preview after transfer, use
`dry-activate` instead of `switch` with the same `--store-path` and `--no-reexec`.
It reports planned activation changes without selecting the system profile.
Complete the service's external access, authorization, persistence and restart
checks. Record revision, closure and observed results privately.

## Resume and rollback

Inspect journals, mounts, the running closure and the selected system profile.
Profile selection may have succeeded while switching failed. Repair the declared
prerequisite and repeat deployment, or inspect retained generations and roll back:

```bash
incus exec "$remote:edge" --project default -- nixos-rebuild list-generations
incus exec "$remote:edge" --project default -- \
  nixos-rebuild switch --rollback --no-reexec --no-flake
```

`--rollback` selects the generation preceding the selected profile, which can
differ from the previously running closure after a failed switch or `test`.
Inspect the generation before using it. To choose a specific retained generation,
resolve its `/nix/var/nix/profiles/system-N-link` to an exact store path and switch
with `--store-path` as above. A seed stops application services and is an explicit
recovery choice. Repeat the result and service checks after rollback.

NixOS rollback does not reverse database migrations; use matching
[data recovery](recovery.md) when required. Reconcile source with running state.
Retain recovery generations until acceptance; deleting generations and garbage
collection can remove rollback options. Preserve any older `.operations/` records
and `garden-*-previous` GC roots until their recovery points are no longer needed.

Sources: pinned [nixos-rebuild manual](https://github.com/NixOS/nixpkgs/blob/26f4107e47e3ad0ffd0db220469ba83b6f6d96e8/pkgs/by-name/ni/nixos-rebuild-ng/nixos-rebuild.8.scd)
and [system switch](https://github.com/NixOS/nixpkgs/blob/26f4107e47e3ad0ffd0db220469ba83b6f6d96e8/nixos/doc/manual/development/what-happens-during-a-system-switch.chapter.md).
