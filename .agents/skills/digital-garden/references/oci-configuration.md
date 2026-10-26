# Maintain direct OCI configuration

- [Scope and inputs](#scope-and-inputs)
- [Apply the change](#apply-the-change)
- [Check the result](#check-the-result)
- [Resume and rollback](#resume-and-rollback)

## Scope and inputs

| Field | Requirement |
|---|---|
| Goal | Change public presets, image or launch settings with declared ownership and safe restart. |
| Prerequisites | A working inference service; retain inference selection, GPU input, state and configuration backups. |
| Sources | `systems/inference/models.ini`, image/model locks and `systems/inference/main.tf`. |
| Execution and inputs | workstation from repository root; changed declared files and reviewed whole plan. |
| Expected infrastructure effects | Preset-only change updates config file and running state; review image/launch changes separately. |

OpenTofu owns image digest, entrypoint, public environment, volume mounts,
devices/limits, running state and ordinary public config-file delivery. The pinned
Incus provider's native `incus_storage_volume.file` puts `systems/inference/models.ini` at
`/models.ini` before a dependent OCI instance starts. At runtime the volume is
mounted read-only at `/etc/llama`. llama.cpp owns writable downloads/cache.

There is no Nix configuration bundle, launch script, external upload controller,
`ignore_changes` on config files/running state, derived image or publication
pipeline. Public config may appear in OpenTofu state. Secret plaintext may not;
secret-heavy workloads use NixOS/sops-nix instead. Single runtime secret files
use the separate [secret-delivery contract](secrets.md#secret-delivery-for-a-new-service)
and their owning service reference; this public preset procedure cannot deliver them.

On updates, stop before applying mounted config-file changes, then let the reviewed
whole plan restore running/autostart after delivery. Use
[inference acceptance](inference.md#check-the-result) after restart; stop on failure.

## Apply the change

Run from the repository root against an existing inference service. Keep root-local
inputs with the inspected GPU PCI address. This OCI workload needs no
NixOS build or deployment.

### 1. Edit the source

Edit [systems/inference/models.ini](../../../../systems/inference/models.ini), not the file inside the guest.
`[*]` contains shared defaults; `[qwen38]` and `[qwen38-chat]` identify model aliases
and override those defaults. For example, to reduce the coding profile context, set
`ctx-size = 4096` to its existing `[qwen38]` section. Keep `version = 1`
and avoid duplicate sections or keys.

| Change | Files to edit |
|---|---|
| Context, sampling or GPU-layer settings for a model | `systems/inference/models.ini` |
| Add, remove or replace a model | `systems/inference/models.ini` and `systems/inference/models.lock.json` |
| Router concurrency (`--models-max`), entrypoint, memory or cache-volume limits | `systems/inference/main.tf` |
| Server image/version | `systems/inference/image.lock.json`; review as a separate upgrade |

Before deployment, require each model/artifact URL, cache path and lock entry to
agree; a lock for former aliases does not verify current presets. For a new
model, use an immutable download revision, a distinct cache path under
`/var/cache/llama`, and record its expected SHA256 and size in the lock. The lock
is an acceptance record, not an automatic checksum verifier. After download,
check the bytes as described in [inference service](inference.md). Retain aliases used
by clients, or update their selections and acceptance checks when renaming them.
Higher context/concurrency can require more RAM/VRAM; review available capacity.

### 2. Stop, review and apply

From systems/inference, load its applied remote for the diagnostic commands:

```bash
GARDEN_REMOTE="$(jq -r .incus_remote site.auto.tfvars.json)"
```

Compare it with this root's state and inspected host before proceeding.

Record the previous Git revision and diff privately before editing/deploying, and
save state using the [state backup procedure](platform.md#starting-state-and-retained-resources).
Use a new protected backup directory per checkpoint. Stop the guest before
changing its mounted configuration:

```bash
incus stop "$GARDEN_REMOTE:garden-llama" --project inference
```

Require success, then run the [whole plan/apply procedure](infrastructure.md#review-and-apply-the-whole-plan).
For a preset-only edit, expect the config volume's file content to update and the
stopped instance's running state to return to true. No guest replacement, volume
deletion or changes to edge/WebUI are expected. Apply only the reviewed saved
plan. OpenTofu delivers the file before starting the dependent guest.

Do not push files manually, edit the guest's read-only mount, or use a targeted
apply. If delivery/apply fails, keep the guest stopped and repair the declared
configuration before retrying.

## Check the result

### 3. Verify and keep the change

```bash
incus exec "$GARDEN_REMOTE:open-webui" --project ai -- curl --fail --retry 15 --retry-connrefused --retry-delay 2 --connect-timeout 5 --max-time 10 --retry-max-time 90 http://garden-llama.garden.internal:8080/health
incus exec "$GARDEN_REMOTE:open-webui" --project ai -- curl --fail --connect-timeout 5 --max-time 30 http://garden-llama.garden.internal:8080/v1/models
incus console "$GARDEN_REMOTE:garden-llama" --project inference --show-log
```

Run each check separately. Require successful health, the intended aliases and no
preset/load errors. Repeat the inference service’s generated-text/GPU checks for each
affected model, then test it in WebUI. New models may download on their first
request. After restarting llama, repeat health and generation and confirm the
cache persists. Record the accepted revision and commit the public changes.

## Resume and rollback

If apply fails, keep the guest stopped and repair the declared configuration
before retrying the whole plan.

To roll back, restore the previous declared presets (and matching lock/launch
settings if changed), stop llama, review/apply a new whole plan, and repeat the
checks. Reconcile source with accepted running state. Retain config/cache volumes
and application identities.

Preset syntax: [pinned llama.cpp router documentation](https://github.com/ggml-org/llama.cpp/blob/b11706/tools/server/README.md).
