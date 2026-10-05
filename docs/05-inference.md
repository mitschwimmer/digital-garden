# Private GPU inference and WebUI model switching

Acceptance: WebUI advertises `mimo` and `qwen36` before download. Selecting one and
sending a chat makes llama.cpp download it if needed and load it on the AMD GPU.
MiMo -> Qwen -> MiMo needs no script, restart, or infrastructure apply; only one
model is loaded at a time. Chats and downloaded models persist across restarts.

Use the [OCI configuration-volume pattern](06-oci-config.md): the unmodified
upstream ROCm b11382 amd64 image is pinned in `llama/image.lock.json`. Nix builds
`llama/models.ini` and `llama/start.sh`; Bash deploys the artifact to a read-only
configuration volume. OpenTofu creates volumes/mounts and the private instance,
but neither stores nor pushes application configuration. There is no custom image
build, image publication, registry prerequisite, or Python model installation.

llama.cpp owns lazy downloads and cache. Presets use immutable Hugging Face revision
URLs and checksum-named local files. `models.lock.json` records source SHA256/size;
the ordinary URL downloader does not independently enforce that recorded SHA256.
Contexts initially use 8192 tokens, text-only, without MTP. WebUI uses its native
llama.cpp provider and a two-hour cold-download request timeout. The private API
has no API-key authentication; only trusted Incus backends can access it. WebUI
retains OIDC. No new secrets are introduced.

## Apply

From the repository on the NixOS workstation, in fish:

```fish
git fetch origin
git switch homelab/inference
git pull --ff-only
nix develop --command fish
python3 scripts/configure-llama.py "$GARDEN_REMOTE"
bash scripts/verify-workstation.sh
```

CI runs only quick syntax/static checks. The workstation verification performs
full Nix builds and OpenTofu/configuration checks once, before applying; deployment
reuses the same build outputs. Model/GPU/browser acceptance runs on the host.

The optional GPU helper discovers local infrastructure inputs; with multiple AMD
GPUs, specify `--gpu-pci PCI_ADDRESS`. It preserves existing seed/LAN settings and
writes only ignored `tofu/site.auto.tfvars.json`. Keep the existing seed image path.
The existing IncusOS AMD driver, firmware, and `/dev/kfd` must remain available.

If former `llama` is running, stop it to free GPU/RAM and record that for rollback.
If you already tested an earlier PR revision, stop `garden-llama` before the apply
that changes its OCI launch settings. No old instance or data is deleted:

```fish
incus stop "$GARDEN_REMOTE:llama" --project default
tofu -chdir=tofu init
tofu -chdir=tofu validate
tofu -chdir=tofu plan -out=inference.tfplan
```

For a fresh deployment expect **3 additions, 0 changes, 0 deletions**: router,
cache, and config volume. The router is initially **stopped**. Pool space must
cover the ROCm root and up to about 21 GB of models; root limit 32 GiB, cache quota
64 GiB. If the first revision was already applied, expect existing volumes retained
and an instance/config update, not an edge/WebUI replacement or data deletion.
The config volume ignores externally managed file contents, retaining any file
uploaded by an earlier Tofu revision. The Nix deployment saves prior files before
installing the new configuration.
If a derived-image revision was actually applied, returning to the upstream image
requires replacement of only garden-llama, with both volumes retained. Review any
such replacement separately; no old llama or other guest should be replaced.

```fish
tofu -chdir=tofu apply inference.tfplan
bash scripts/deploy-llama.sh "$GARDEN_REMOTE"
incus exec "$GARDEN_REMOTE:garden-llama" --project default -- env LD_LIBRARY_PATH=/app /app/llama-server --list-devices
bash scripts/deploy-webui.sh "$GARDEN_REMOTE"
```

The deploy script builds the Nix artifact, backs up prior files in an ignored local
rollback directory, transfers via Incus custom-volume file operations, verifies
bytes, then starts the official image and checks health/catalog. Failure restores
a complete prior configuration; otherwise the router stays stopped for inspection.
`--list-devices` must list the AMD GPU. The explicit library path is needed for this separate Incus exec process; the upstream service starts in its image working directory. No model download is required during prep.
On the first deployment, a missing prior config file and a brief connection-refused
health retry are expected; the final health/catalog checks must succeed.

## Verify

```fish
incus exec "$GARDEN_REMOTE:open-webui" --project default -- curl --fail http://garden-llama.garden.internal:8080/models
```

On first deployment both aliases should be `unloaded`. In the browser at
`https://ai.archaic.work`, select MiMo and chat, select Qwen and chat, then select
MiMo and chat again. Both should be selectable before downloading. First use
waits for download/load; cached swaps only load the selected model. Native provider
support supplies model status and admin model-management integration.

Check the backend independently from the WebUI guest:

```fish
python3 scripts/check-inference.py "$GARDEN_REMOTE" --swap
incus console "$GARDEN_REMOTE:garden-llama" --project default --show-log
```

The smoke test checks real generated text and exactly the selected model loaded
after each request. It tests the backend contract, not browser/OIDC behavior.
Logs must show ROCm initialization and layers offloaded to GPU. Device availability
alone is insufficient. If Qwen does not fit, reduce context/offload explicitly;
do not enable privileged mode or spoof the architecture.

For an optional integrity check after lazy download, compare `sha256sum` for the
paths in `llama/models.ini` with the fingerprints in `llama/models.lock.json`.

```fish
incus restart "$GARDEN_REMOTE:garden-llama" --project default
python3 scripts/check-inference.py "$GARDEN_REMOTE"
incus restart "$GARDEN_REMOTE:open-webui" --project default
```

Confirm cached inference works and the chat remains. A subsequent config change
uses `bash scripts/deploy-llama.sh "$GARDEN_REMOTE"`; no image build or Tofu file
push is needed. Only infrastructure/image changes require an infrastructure plan.

## Roll back

For a configuration-only update with the complete backup path printed by deploy:

```fish
set PREVIOUS_CONFIG /ABSOLUTE/PATH/PRINTED_BY_DEPLOY
set GARDEN_POOL (jq -r '.storage_pool // "local"' tofu/site.auto.tfvars.json)
incus stop "$GARDEN_REMOTE:garden-llama" --project default
incus storage volume file push "$PREVIOUS_CONFIG/models.ini" "$GARDEN_REMOTE:$GARDEN_POOL" garden-llama-config/models.ini --uid 0 --gid 0 --mode 0444 --project default
incus storage volume file push "$PREVIOUS_CONFIG/start.sh" "$GARDEN_REMOTE:$GARDEN_POOL" garden-llama-config/start.sh --uid 0 --gid 0 --mode 0444 --project default
incus start "$GARDEN_REMOTE:garden-llama" --project default
```

For rollback of the whole iteration, restore the previous WebUI system printed
by its deployment and reactivate the old llama only if previously running:

```fish
set PREVIOUS_WEBUI /nix/store/PASTE_PREVIOUS_WEBUI_SYSTEM
incus exec "$GARDEN_REMOTE:open-webui" --project default -- nix-env --profile /nix/var/nix/profiles/system --set "$PREVIOUS_WEBUI"
incus exec "$GARDEN_REMOTE:open-webui" --project default -- "$PREVIOUS_WEBUI/bin/switch-to-configuration" switch
incus stop "$GARDEN_REMOTE:garden-llama" --project default
incus config set "$GARDEN_REMOTE:garden-llama" --project default boot.autostart=false
incus start "$GARDEN_REMOTE:llama" --project default
```

All volumes remain intact/protected. Do not unset GPU input and apply or run
`tofu destroy`. A reviewed apply restores declared autostart when resuming.

## Next iteration

Backups and a restore test before obsolete-resource cleanup.

Sources: [pinned llama server](https://github.com/ggml-org/llama.cpp/blob/b11382/tools/server/README.md),
[WebUI native provider](https://github.com/open-webui/open-webui/blob/v0.11.4/backend/open_webui/routers/openai.py),
and [Incus custom-volume file transfer](https://linuxcontainers.org/incus/docs/main/reference/manpages/incus/storage/volume/file/push/).
