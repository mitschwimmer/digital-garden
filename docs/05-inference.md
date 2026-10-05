# Private GPU inference and WebUI chat

Acceptance: WebUI lists `mimo` and `qwen36`, generates an answer through the new
ROCm llama.cpp instance, and retains chat/model data across restarts. Only one model
is loaded at a time. Context initially uses 8192 tokens; vision and MTP speculation
are disabled until ordinary chat and GPU offload have been verified.

The backend is direct OCI under Incus: no Docker or additional guest kernel.
`llama/image.lock.json` pins the upstream linux/amd64 ROCm b11382 manifest digest.
The published image includes gfx1200/gfx1201 support. `llama/models.lock.json`
pins the two public GGUF files by repository revision and SHA256. Model downloads
are explicit and checksum-verified on the new protected volume; the server reads
local files and never silently updates Hugging Face `main`.

The private API has no API-key authentication; access is confined to the trusted
Incus backend network. WebUI keeps its OIDC authentication. Its `unused` API key
value is a compatibility placeholder, not a credential. Caddy exposes no llama
route, and llama receives no LAN NIC. Future untrusted/private workloads would
require a narrower API authorization boundary.

## Apply

On the workstation, in fish, from this checkout:

```fish
git fetch origin
git switch homelab/inference
nix develop --command fish
python3 scripts/configure-llama.py "$GARDEN_REMOTE"
python3 scripts/verify-llama-image.py
```

The read-only helper selects the sole AMD GPU from Incus resources and preserves
all existing seed/LAN inputs. With multiple AMD GPUs, use `--gpu-pci PCI_ADDRESS`.
It writes only ignored `tofu/site.auto.tfvars.json`; never commit host inventory.
The existing IncusOS AMD driver, firmware, and `/dev/kfd` must be available (they
were used by the former OCI setup). No host driver changes are performed here.

Stop the former `llama` instance if it is still running, to free GPU and RAM:

```fish
incus stop "$GARDEN_REMOTE:llama" --project default
tofu -chdir=tofu init
tofu -chdir=tofu validate
tofu -chdir=tofu plan -out=inference.tfplan
```

Expected: **3 additions, 0 changes, 0 deletions** (new router plus cache/config
volumes). The former instance and volumes are outside this state and remain intact.
Keep the existing seed image path. Stop if edge/WebUI is replaced or any existing
data is removed. Ensure the existing pool has room for the ROCm image/root and
about 21 GB of selected models; cache quota is 64 GiB, root limit 32 GiB.

```fish
tofu -chdir=tofu apply inference.tfplan
incus exec "$GARDEN_REMOTE:garden-llama" --project default -- /app/llama-server --list-devices
python3 scripts/download-models.py "$GARDEN_REMOTE"
python3 scripts/check-inference.py "$GARDEN_REMOTE"
bash scripts/deploy-webui.sh "$GARDEN_REMOTE"
```

`--list-devices` must list the AMD GPU. The new name is `garden-llama`; do not
modify the former instance's mappings. Downloads verify the locked SHA256 before
atomic rename and retain existing matching files. To begin with just the smaller
model, use `download-models.py REMOTE --model mimo`; download `qwen36` later before
selecting it. No private Hugging Face token is needed for these public models.

The smoke test makes a real private chat request from the WebUI guest and must
return generated text. GPU availability alone does not prove offload: inspect
`incus console "$GARDEN_REMOTE:garden-llama" --project default --show-log` after
the request and confirm ROCm initialization and layers offloaded to the GPU.

## Verify

```fish
incus exec "$GARDEN_REMOTE:open-webui" --project default -- curl --fail http://garden-llama.garden.internal:8080/v1/models
python3 scripts/check-inference.py "$GARDEN_REMOTE" --model qwen36
```

Sign in at `https://ai.archaic.work`, select each model, and send a short prompt.
The larger model should replace the loaded smaller one, rather than loading both
into GPU memory. If it does not fit, reduce context/offload settings explicitly;
do not enable a spoofed GPU architecture override or privileged mode.

Restart the new router and verify a cached model still answers without download:

```fish
incus restart "$GARDEN_REMOTE:garden-llama" --project default
python3 scripts/check-inference.py "$GARDEN_REMOTE"
incus restart "$GARDEN_REMOTE:open-webui" --project default
```

Reopen WebUI and confirm the chat remains. If a preset is edited later, apply its
config volume update and restart `garden-llama` to reread it. Model changes require
a reviewed lock/preset update and checksum-verified download; the pin helper never
overwrites an existing lock. No new secrets are introduced in this iteration.

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

Restart the old instance only if it was running before this iteration. All new
volumes remain protected, and old resources/data remain intact. Do not unset the
GPU input and apply or run `tofu destroy`: protected volumes intentionally prevent
that deletion. The rollback disables new-instance autostart; a future reviewed OpenTofu apply
restores its declared autostart setting when you resume this deployment.

## Next iteration

Implement backups and perform a restore test before deleting obsolete resources.

Sources: [upstream image digest](https://github.com/ggml-org/llama.cpp/pkgs/container/llama.cpp/1333460587?tag=server-rocm-b11382),
[pinned server interface](https://github.com/ggml-org/llama.cpp/blob/b11382/tools/server/README.md),
[ROCm image build](https://github.com/ggml-org/llama.cpp/blob/b11382/.devops/rocm.Dockerfile),
and [Incus GPU devices](https://linuxcontainers.org/incus/docs/main/reference/devices_gpu/).
