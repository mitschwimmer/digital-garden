# OCI configuration pattern

Use the application's official OCI image, pinned to an immutable digest. Keep
application configuration in Git and build its deployment artifact with Nix.
Create separate Incus volumes for configuration and mutable application data.
Mount configuration read-only; give the application only the writable state/cache
volumes it needs. Keep secrets out of ordinary configuration artifacts.

Ownership:

- OpenTofu: image identity, volumes, mounts, instance/device/limit settings, and
  the OCI launch entrypoint. It does not store or transfer application file contents.
- Nix: the configuration artifact, including an optional POSIX launch script when
  runtime options must be supplied independently of the upstream entrypoint.
- Deployment script: build the artifact, back up prior configuration, stop the
  service, upload through authenticated Incus volume file operations, verify the
  transferred bytes, and activate/check it. Restore the previous files on failure.
- Application: mutable runtime state such as model downloads, indexes, and databases.
- Python checks: configuration and runtime verification, not service installation.

A fresh OCI instance is created stopped so missing configuration cannot break its
first boot. After uploading, the deployment script starts it. `ignore_changes` on
`running` prevents a later infrastructure apply from stopping an activated service;
Incus boot autostart remains enabled. Instance image upgrades require an explicit
replacement plan; mounted state/config volumes remain separate and protected.

For llama.cpp, `nix build .#llama-config` produces `models.ini` and `start.sh`;
`deploy-llama.sh` pushes them to `garden-llama-config`. The upstream ROCm image
mounts that volume at `/etc/llama` read-only and the cache at `/var/cache/llama`
read-write. `oci.entrypoint` connects the official binary to the mounted launch
script; no application configuration values or file contents pass through Tofu.

Incus supports [custom-volume file transfers](https://linuxcontainers.org/incus/docs/main/reference/manpages/incus/storage/volume/file/push/),
so configuration can be installed before a container is started. This pattern
needs neither a derived image nor a registry publication workflow.
