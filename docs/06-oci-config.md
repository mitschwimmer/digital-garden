# Direct OCI configuration ownership

OpenTofu owns image digest, entrypoint, public environment, volume mounts,
devices/limits, running state and ordinary public config-file delivery. The pinned
Incus provider's native `incus_storage_volume.file` puts `llama/models.ini` at
`/models.ini` before a dependent OCI instance starts. At runtime the volume is
mounted read-only at `/etc/llama`. llama.cpp owns writable downloads/cache.

There is no Nix configuration bundle, launch script, external upload controller,
`ignore_changes` on config files/running state, derived image or publication
pipeline. Public config may appear in OpenTofu state. Secret plaintext may not;
secret-heavy workloads use NixOS/sops-nix instead.

On updates, stop before applying mounted config-file changes, then let the reviewed
whole plan restore declared running/autostart state after config delivery. Reboot
and partial-failure behavior, acceptance and rollback are covered in
[milestone 5](05-inference.md). Stop live application at a failed gate.
