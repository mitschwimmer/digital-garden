# Application Placement Rules

Choose the lightest runtime that keeps configuration, secrets, upgrades, and hardware access understandable.

## Direct OCI application container

Prefer when all/most are true:
- Upstream publishes a good OCI image.
- It is essentially one packaged application.
- Incus can run the image directly without Docker/Podman.
- Configuration is simple and maps cleanly to files, arguments, or non-secret environment values.
- Secret requirements can be supplied cleanly without putting plaintext into OpenTofu state.
- Shared-host-kernel isolation is acceptable.

Pin an accepted image by digest. Give mutable data/models explicit persistent volumes.

Current example: `llama.cpp`, including the already-proven AMD GPU mapping under IncusOS.

## NixOS system container

Prefer when one or more are true:
- The workload is better described as a machine/role rather than a single image.
- NixOS has a useful native module.
- Several configuration files/services must move together.
- sops-nix integration materially simplifies secret handling.
- The application mainly accepts environment-variable secrets and NixOS `EnvironmentFile`/systemd credential wiring is cleaner than OCI injection.
- Strong rollback/reproducibility of the guest userspace is valuable.

Current examples:
- `edge`: Caddy + Authelia.
- `open-webui`: Open WebUI with sops-nix managed environment-file secrets.

## VM

Use only when a separate kernel or stronger isolation is justified, for example:
- kernel/module requirements incompatible with IncusOS containers,
- device passthrough requiring guest ownership of drivers,
- untrusted workload needing a stronger boundary,
- software incompatible with container constraints.

Do not choose a VM merely because it is familiar.

## Re-evaluate per application

Do not blindly repeat the previous app's placement. For each new service, explicitly check:
1. upstream packaging quality,
2. state/persistence model,
3. secret interfaces,
4. hardware requirements,
5. network exposure,
6. identity integration,
7. upgrade/rollback behavior.

If two options remain comparable, prefer direct OCI over a NixOS system container, and a system container over a VM, unless secret/configuration maintainability points the other way.
