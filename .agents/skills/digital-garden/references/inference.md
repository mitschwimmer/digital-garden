# Provide private GPU inference

- [Scope and inputs](#scope-and-inputs)
- [Apply the change](#apply-the-change)
- [Check the result](#check-the-result)
- [Resume and rollback](#resume-and-rollback)

## Scope and inputs

| Field | Requirement |
|---|---|
| Goal | Provide generated text with verified GPU offload and persistent model cache. |
| Prerequisites | Private networking and a trusted API caller; inspected AMD PCI/KFD support, compatible ROCm, capacity and model access. |
| Sources | `systems/inference/main.tf`, `systems/inference/image.lock.json`, `systems/inference/models.ini`, `systems/inference/models.lock.json`. |
| Execution and inputs | Workstation, trusted backend and browser; inspected GPU PCI address in systems/inference. |
| Expected infrastructure effects | This root owns its OCI guest and two volumes; no other root changes. |

The pinned image is `server-rocm-b11706` (linux/amd64), built with ROCm 7.2.1.
Inspect IncusOS driver/firmware, `/dev/kfd` and available GPU/RAM capacity
before creating or upgrading the guest. Newer source releases may precede
publication of their ROCm images; use a verified published image digest.

The OCI guest, cache and configuration volumes belong to project `inference`.
The checks below use the configured WebUI guest as a trusted caller; another
trusted caller may exercise the same endpoints. Operate inference independently from its own root; see [platform inputs](platform.md).
Open WebUI callers run in `ai`; both use the shared bridge in `default`.

`systems/inference/main.tf` uses the upstream digest in `systems/inference/image.lock.json`, explicit
unprivileged GPU/KFD mappings, UID/GID 1000, one private NIC, 32 GiB root and a
64 GiB protected cache. OpenTofu delivers `systems/inference/models.ini` into the read-only
configuration volume **before** starting the instance, and owns running/autostart
state. There is no delayed upload/deployment window or derived image. Launch
arguments and LLAMA_CACHE are ordinary public OpenTofu attributes.

Only trusted host/backend clients may route to port 8080; the API has no API-key
access control. Do not publish/forward it. Host administrators and routable guests
can call it; gardenbr0 is not an authorization boundary. Verify intended caller
reachability and lack of public routing rather than assuming address privacy.

## Apply the change

### 1. Set inspected inputs on the workstation

In systems/inference, set the remote and PCI from this root's reviewed local
inputs (not another task's shell variables):

```fish
set -l GARDEN_REMOTE (jq -r .incus_remote site.auto.tfvars.json)
set -l GARDEN_GPU_PCI (jq -r .llama_gpu_pci site.auto.tfvars.json)
```

Both values must match the inspected host inventory.

```fish
jq --arg pci "$GARDEN_GPU_PCI" '.llama_gpu_pci = $pci' site.auto.tfvars.json > site.auto.tfvars.json.tmp
mv site.auto.tfvars.json.tmp site.auto.tfvars.json
```

### 2. Apply the OCI workload

Run [native plan/apply](infrastructure.md#review-and-apply-the-whole-plan): the initial plan creates this root's guest and volumes; no other system changes. Provider
schema validation is mandatory. Its file content is public and may enter state;
never use this path for secrets. Initial apply must finish public file delivery
before instance creation through the disk dependency. If delivery fails, do not
start the service manually; repair it and reapply the whole plan. This workload
starts directly through OpenTofu; it does **not** use NixOS deployment or the
systemd readiness loop.

## Check the result

### 3. Verify API readiness before requesting models

```fish
incus info "$GARDEN_REMOTE:garden-llama" --project inference
incus exec "$GARDEN_REMOTE:garden-llama" --project inference -- env LD_LIBRARY_PATH=/app /app/llama-server --list-devices
incus exec "$GARDEN_REMOTE:open-webui" --project ai -- curl --fail --retry 15 --retry-connrefused --retry-delay 2 --connect-timeout 5 --max-time 10 --retry-max-time 90 http://garden-llama.garden.internal:8080/health
incus exec "$GARDEN_REMOTE:open-webui" --project ai -- curl --connect-timeout 5 --max-time 30 --fail http://garden-llama.garden.internal:8080/v1/models
```

Stop unless health succeeds within the retry budget and the catalog is available.
A running OCI process or device enumeration alone does not pass the check.

### 4. Verify model output, GPU use and persistence

Require the aliases declared in `models.ini` even before downloads. The current
profiles are `qwen38` and `qwen38-chat`; both share one GGUF, and the chat profile
also uses a projector. Send native
API requests from the trusted WebUI guest, one model at a time:

```fish
incus exec "$GARDEN_REMOTE:open-webui" --project ai -- curl --fail --max-time 7200 -H 'Content-Type: application/json' -d '{"model":"qwen38","messages":[{"role":"user","content":"Say hello in one sentence."}],"max_tokens":64}' http://garden-llama.garden.internal:8080/v1/chat/completions
incus exec "$GARDEN_REMOTE:open-webui" --project ai -- curl --fail --max-time 7200 -H 'Content-Type: application/json' -d '{"model":"qwen38-chat","messages":[{"role":"user","content":"Say hello in one sentence."}],"max_tokens":64}' http://garden-llama.garden.internal:8080/v1/chat/completions
incus exec "$GARDEN_REMOTE:open-webui" --project ai -- curl --fail --max-time 7200 -H 'Content-Type: application/json' -d '{"model":"qwen38","messages":[{"role":"user","content":"Say hello again."}],"max_tokens":64}' http://garden-llama.garden.internal:8080/v1/chat/completions
incus exec "$GARDEN_REMOTE:open-webui" --project ai -- curl --connect-timeout 5 --max-time 30 --fail http://garden-llama.garden.internal:8080/models
incus console "$GARDEN_REMOTE:garden-llama" --project inference --show-log
```

Require responses contain actual generated text; logs show ROCm and layers
**offloaded**, not merely enumerated devices. Catalog status shows only the
selected model loaded (models-max 1). When WebUI is enabled, select coding -> chat -> coding and
chat; switching needs no infrastructure apply/restart. First download/load may
be slow. Cold model requests may take up to the documented 7200-second timeout;
do not treat this as the short API readiness check. Cached models must survive restarting inference. If WebUI is enabled, its chat
state and client integration must also survive restarting both guests. Wait for WebUI via [guest readiness](readiness.md)
in `ai`, and repeat the bounded inference health check above before requests. Repeat
an API request and, when enabled, browser chat after restart and ensure no full re-download.

Before deployment, reconcile `models.ini` with `models.lock.json`: every model
and projector needs an immutable revision and expected SHA256/size. Stop if URLs
use mutable revisions or the lock describes former models; cache names alone
do not verify bytes.
After download, verify each file with `sha256sum` inside llama and compare against
the lock. Also check file sizes with `stat -c %s`. This can be expensive once;
record verified results and repeat after changing bytes, not every restart.

## Resume and rollback

Inspect container log, GPU devices/permissions, memory and cache
capacity, outbound Hugging Face DNS/TLS, selected model status and WebUI backend
URL. If Qwen cannot fit, review an explicit context/offload change. Do not enable
privileged mode or bypass checks with an architecture override. A failed initial
apply resumes with the same state/volumes and whole plan.

For updates and rollback use [OCI configuration](oci-configuration.md#apply-the-change),
which owns stopping, config delivery and whole-plan restart. Retain state, cache
and identities; never disable inference or unset PCI to troubleshoot. For a
longer repair, disable boot.autostart manually while stopped and record the drift;
the next reviewed apply must restore declared running/autostart. Review image
upgrades separately: only the guest may be replaced, with volumes retained.

Sources: [pinned llama server](https://github.com/ggml-org/llama.cpp/blob/b11706/tools/server/README.md),
[pinned provider files](https://github.com/lxc/terraform-provider-incus/blob/v1.2.1/docs/resources/storage_volume.md),
[Incus instance options](https://linuxcontainers.org/incus/docs/main/reference/instance_options/).
