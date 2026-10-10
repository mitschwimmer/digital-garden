# Maintain direct OCI configuration

- [Contract](#contract)
- [Execute](#execute)
- [Verify](#verify)
- [Resume and rollback](#resume-and-rollback)
- [Acceptance gate](#acceptance-gate)

## Contract

| Field | Requirement |
|---|---|
| Goal | Change public presets, image or launch settings with declared ownership and safe restart. |
| Prerequisites | [Inference](inference.md) accepted; retain stage 5, GPU input, state and configuration backups. |
| Sources | `llama/models.ini`, image/model locks and `tofu/llama.tf`. |
| Execution and inputs | Fish workstation from repository root; changed declared files and reviewed whole plan. |
| Expected infrastructure effects | Preset-only change updates config file and running state; review image/launch changes separately. |

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
[milestone 5](inference.md). Stop live application at a failed gate.

## Execute

Run in fish from the repository root after milestone 5 is accepted. Keep local
inputs at stage 5 with the inspected GPU PCI address. This OCI workload needs no
NixOS build or activation.

### 1. Edit the source

Edit [llama/models.ini](../../../../llama/models.ini), not the file inside the guest.
`[*]` contains shared defaults; `[mimo]` and `[qwen36]` identify model aliases
and override those defaults. For example, to reduce only Qwen's context, add
`ctx-size = 4096` to its existing `[qwen36]` section. Keep `version = 1`
and avoid duplicate sections or keys.

| Change | Files to edit |
|---|---|
| Context, sampling or GPU-layer settings for a model | `llama/models.ini` |
| Add, remove or replace a model | `llama/models.ini` and `llama/models.lock.json` |
| Router concurrency (`--models-max`), entrypoint, memory or cache-volume limits | `tofu/llama.tf` |
| Server image/version | `llama/image.lock.json`; review as a separate upgrade |

For a new model, use an immutable download revision, a distinct cache path under
`/var/cache/llama`, and record its expected SHA256 and size in the lock. The lock
is an acceptance record, not an automatic checksum verifier. After download,
check the bytes as described in [milestone 5](inference.md). Retain aliases used
by clients, or update their selections and acceptance checks when renaming them.
Higher context/concurrency can require more RAM/VRAM; review available capacity.

### 2. Stop, review and apply

Record the previous Git revision and diff privately before editing/deploying, and
save state using the [runbook checkpoint procedure](deployment.md#starting-state-and-retained-resources).
Use a new protected backup directory per checkpoint. Stop the guest before
changing its mounted configuration:

```fish
incus stop "$GARDEN_REMOTE:garden-llama" --project inference
```

Require success, then run the [whole plan/apply procedure](deployment.md#native-planapply-and-activation).
For a preset-only edit, expect the config volume's file content to update and the
stopped instance's running state to return to true. No guest replacement, volume
deletion or changes to edge/WebUI are expected. Apply only the reviewed saved
plan. OpenTofu delivers the file before starting the dependent guest.

Do not push files manually, edit the guest's read-only mount, or use a targeted
apply. If delivery/apply fails, keep the guest stopped and repair the declared
configuration before retrying.

## Verify

### 3. Verify and keep the change

```fish
incus exec "$GARDEN_REMOTE:open-webui" --project ai -- curl --fail --retry 15 --retry-connrefused --retry-delay 2 --connect-timeout 5 --max-time 10 --retry-max-time 90 http://garden-llama.garden.internal:8080/health
incus exec "$GARDEN_REMOTE:open-webui" --project ai -- curl --fail --connect-timeout 5 --max-time 30 http://garden-llama.garden.internal:8080/v1/models
incus console "$GARDEN_REMOTE:garden-llama" --project inference --show-log
```

Run each check separately. Require successful health, the intended aliases and no
preset/load errors. Repeat milestone 5's generated-text/GPU checks for each
affected model, then test it in WebUI. New models may download on their first
request. After restarting llama, repeat health and generation and confirm the
cache persists. Record the accepted revision and commit the public changes.

## Resume and rollback

If apply fails, keep the guest stopped and repair the declared configuration
before retrying the whole plan.

To roll back, restore the previous declared presets (and matching lock/launch
settings if changed), stop llama, review/apply a new whole plan, and repeat the
checks. Keep both config/cache volumes; changing a preset does not require
deleting cached models or application identities.

## Acceptance gate

Accept only after the [verification](#verify) passes for every affected model
and after restart. Record the revision and results; retain config/cache volumes.

Preset syntax: [pinned llama.cpp router documentation](https://github.com/ggml-org/llama.cpp/blob/b11382/tools/server/README.md).
