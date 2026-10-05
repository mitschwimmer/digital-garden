# Private GPU inference and WebUI model switching

Acceptance: Open WebUI advertises `mimo` and `qwen36` before either is downloaded.
Selecting a model and sending a chat makes llama.cpp download it if needed, load
it on the AMD GPU, and answer. Switching MiMo -> Qwen -> MiMo requires no script,
restart, or OpenTofu apply. Only one model is loaded at a time. Chats and model
cache survive restarts.

## Ownership

- OpenTofu owns the private OCI instance, GPU/KFD mappings, limits, and protected
  cache volume. It stores no presets and pushes no application files.
- `llama/Dockerfile` packages `llama/models.ini` and router defaults into a thin
  image layer on the immutable upstream ROCm b11382 amd64 image. ROCm is not rebuilt.
- The accepted configured image digest is pinned in ignored local infrastructure
  inputs, like the workstation-built edge seed image path. The image workflow
  verifies its actual catalog without downloading GGUFs, then publishes accepted
  same-repository push builds to GHCR. Docker is a CI build tool only; Incus runs
  the resulting OCI application directly.
- llama.cpp owns lazy downloads, temporary download files, ETag handling, and its
  persistent cache. Presets use immutable Hugging Face revision URLs and
  checksum-named local files. The model lock records upstream SHA256/size for
  verification; llama.cpp's ordinary URL downloader does not independently enforce
  that recorded SHA256. There is no Python download/configuration step.
- NixOS declares WebUI's private API URL, native `llama.cpp` provider, and a two-hour
  request timeout for cold downloads. Python only verifies runtime behavior here;
  the optional GPU helper discovers local infrastructure inputs.

Initial contexts are 8192 tokens, one model at a time, text-only, without MTP.
The private API has no API-key authentication and is confined to the trusted
Incus backend network. WebUI retains native OIDC. No new secrets are introduced.

## Apply

On the workstation in fish, from the repository:

```fish
git fetch origin
git switch homelab/inference
git pull --ff-only
nix develop --command fish
python3 scripts/configure-llama.py "$GARDEN_REMOTE"
```

The helper queries Incus resources and selects the sole AMD GPU, preserving all
existing local seed/LAN inputs. With multiple AMD GPUs, use `--gpu-pci PCI_ADDRESS`.
It writes ignored `tofu/site.auto.tfvars.json`; do not commit host inventory.
The existing IncusOS AMD driver/firmware and `/dev/kfd` must remain available.

**One-time registry prerequisite:** after the first image workflow succeeds, set
[the digital-garden-llama package](https://github.com/users/mitschwimmer/packages/container/package/digital-garden-llama)
to public in its package settings. New GHCR packages are private by default. This
allows anonymous Incus pulls without putting registry credentials into Tofu state.
After the accepted push workflow succeeds, copy its printed SHA256 digest and pin
it in ignored local inputs. This is artifact selection, not service configuration.
From the workstation:

```fish
set LLAMA_DIGEST sha256:PASTE_ACCEPTED_IMAGE_DIGEST
set LLAMA_IMAGE "ghcr.io/mitschwimmer/digital-garden-llama@$LLAMA_DIGEST"
skopeo inspect "docker://$LLAMA_IMAGE"
jq --arg digest "$LLAMA_DIGEST" '.llama_image_digest = $digest' tofu/site.auto.tfvars.json > tofu/site.auto.tfvars.json.tmp
mv tofu/site.auto.tfvars.json.tmp tofu/site.auto.tfvars.json
```

Stop the former `llama` only if still running to free GPU/RAM; record that fact for
rollback. Its instance and data remain outside the new state:

```fish
incus stop "$GARDEN_REMOTE:llama" --project default
tofu -chdir=tofu init
tofu -chdir=tofu validate
tofu -chdir=tofu plan -out=inference.tfplan
```

Expected before applying the former version of this PR: **2 additions, 0 changes,
0 deletions** (router plus cache). Keep the existing seed image path. Stop if an
existing guest is replaced or data removed. Pool space must cover the ROCm root
and up to about 21 GB of models; root limit is 32 GiB, cache quota 64 GiB.

If you already applied the former three-resource version, the explicit `removed`
block forgets its config-volume state while leaving the physical volume intact.
The new image requires replacement of **only garden-llama**; the provider declares
image changes as replacements. Expect **one instance replacement**, the retained
cache unchanged, and the config volume forgotten without destruction. Stop the
router and snapshot its cache volume before applying that reviewed plan. Keep the
former config volume and manually downloaded files for rollback; do not delete
anything in this iteration. No edge/WebUI/old-llama replacement is expected.

```fish
tofu -chdir=tofu apply inference.tfplan
incus exec "$GARDEN_REMOTE:garden-llama" --project default -- /app/llama-server --list-devices
bash scripts/deploy-webui.sh "$GARDEN_REMOTE"
```

`--list-devices` must list the AMD GPU. No models need to be downloaded yet.

## Verify

```fish
incus exec "$GARDEN_REMOTE:open-webui" --project default -- curl --fail http://garden-llama.garden.internal:8080/models
```

Both aliases should initially be `unloaded`. First verify the actual browser flow
at `https://ai.archaic.work`: select MiMo, send a short prompt, select Qwen, send a
prompt, then switch back to MiMo and send another. Both models should already be
selectable before downloading. First use waits for its download/load; cached swaps
only need model loading. The native provider enables WebUI's model status and
admin model-management integration. Downloading arbitrary extra models through
admin controls is runtime state; the two declared presets remain image-owned.

Verify the backend contract independently from the WebUI guest:

```fish
python3 scripts/check-inference.py "$GARDEN_REMOTE" --swap
incus console "$GARDEN_REMOTE:garden-llama" --project default --show-log
```

The smoke test requests MiMo -> Qwen -> MiMo and checks that exactly the selected
model is loaded after each answer. It verifies the backend, not browser/OIDC
behavior. Logs must show ROCm initialization and GPU layers offloaded; device
availability alone does not prove offload. No privileged mode or architecture
spoof is required. If Qwen does not fit, reduce context/offload settings explicitly.

For an optional integrity check after lazy download, obtain the expected model
paths/checksums from `llama/models.ini` and `llama/models.lock.json` and compare
`sha256sum` in the router. No download helper is required.

```fish
incus restart "$GARDEN_REMOTE:garden-llama" --project default
python3 scripts/check-inference.py "$GARDEN_REMOTE"
incus restart "$GARDEN_REMOTE:open-webui" --project default
```

Confirm a cached model still answers and the WebUI chat remains. Subsequent preset
changes require an image build, review of the printed immutable reference, and an
explicit update of the pinned infrastructure image digest. Pin the accepted image; never deploy a mutable tag.

## Roll back

Use the previous WebUI system path printed by `deploy-webui.sh`:

```fish
set PREVIOUS_WEBUI /nix/store/PASTE_PREVIOUS_WEBUI_SYSTEM
incus exec "$GARDEN_REMOTE:open-webui" --project default -- nix-env --profile /nix/var/nix/profiles/system --set "$PREVIOUS_WEBUI"
incus exec "$GARDEN_REMOTE:open-webui" --project default -- "$PREVIOUS_WEBUI/bin/switch-to-configuration" switch
incus stop "$GARDEN_REMOTE:garden-llama" --project default
incus config set "$GARDEN_REMOTE:garden-llama" --project default boot.autostart=false
incus start "$GARDEN_REMOTE:llama" --project default
```

Restart old llama only if it was running before this iteration. All data volumes
remain intact. Do not unset the GPU input and apply or run `tofu destroy`; protected
cache storage intentionally prevents deletion. A future reviewed apply restores
autostart when resuming. If you previously tested the first version of PR #9,
keep its orphaned config volume and recorded image identity for recovery.

## Next iteration

Backups and a restore test before obsolete-resource cleanup.

Sources: [pinned server interface](https://github.com/ggml-org/llama.cpp/blob/b11382/tools/server/README.md),
[router preset handling](https://github.com/ggml-org/llama.cpp/blob/b11382/tools/server/server-models.cpp),
[WebUI provider integration](https://github.com/open-webui/open-webui/blob/v0.11.4/backend/open_webui/routers/openai.py),
[WebUI timeout controls](https://github.com/open-webui/open-webui/blob/v0.11.4/backend/open_webui/env.py),
and [GHCR package visibility](https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry).
