# Provide private GPU inference

- [Contract](#contract)
- [Execute](#execute)
- [Verify](#verify)
- [Resume and rollback](#resume-and-rollback)
- [Acceptance gate](#acceptance-gate)

## Contract

| Field | Requirement |
|---|---|
| Goal | Provide generated text with verified GPU offload and persistent model cache. |
| Prerequisites | [WebUI](open-webui.md) accepted for this composition; inspected AMD PCI/KFD support, compatible ROCm, capacity and model access. |
| Sources | `tofu/llama.tf`, `llama/image.lock.json`, `llama/models.ini`, `llama/models.lock.json`. |
| Execution and inputs | Workstation, trusted backend and browser; stage 5 and inspected GPU PCI address. |
| Expected infrastructure effects | One OCI guest addition; no new volumes or earlier guest replacement/deletion. |

Inspect IncusOS driver/firmware, `/dev/kfd` and available GPU/RAM capacity
before creating the guest.

The OCI guest, cache and configuration volumes belong to project `inference`.
Open WebUI callers run in `ai`; both use the shared bridge in `default`.

`tofu/llama.tf` uses the upstream digest in `llama/image.lock.json`, explicit
unprivileged GPU/KFD mappings, UID/GID 1000, one private NIC, 32 GiB root and a
64 GiB protected cache. OpenTofu delivers `llama/models.ini` into the read-only
configuration volume **before** starting the instance, and owns running/autostart
state. There is no delayed upload/activation window or derived image. Launch
arguments and LLAMA_CACHE are ordinary public OpenTofu attributes.

Only trusted host/backend clients may route to port 8080; the API has no API-key
access control. Do not publish/forward it. Host administrators and routable guests
can call it; gardenbr0 is not an authorization boundary. Verify intended caller
reachability and lack of public routing rather than assuming address privacy.

## Execute

### 1. Set inspected inputs on the workstation

```fish
jq --arg pci "$GARDEN_GPU_PCI" '.stage = 5 | .llama_gpu_pci = $pci' tofu/site.auto.tfvars.json > tofu/site.auto.tfvars.json.tmp
mv tofu/site.auto.tfvars.json.tmp tofu/site.auto.tfvars.json
```

### 2. Apply the OCI workload

Run [native plan/apply](deployment.md#native-planapply-and-activation): one OCI guest
addition, no volume addition or earlier guest replacement/deletion. Provider
schema validation is mandatory. Its file content is public and may enter state;
never use this path for secrets. Initial apply must finish public file delivery
before instance creation through the disk dependency. If delivery fails, do not
start the service manually; repair it and reapply the whole plan. This workload
starts directly through OpenTofu; it does **not** use NixOS activation or the
systemd readiness loop.

## Verify

### 3. Verify API readiness before requesting models

```fish
incus info "$GARDEN_REMOTE:garden-llama" --project inference
incus exec "$GARDEN_REMOTE:garden-llama" --project inference -- env LD_LIBRARY_PATH=/app /app/llama-server --list-devices
incus exec "$GARDEN_REMOTE:open-webui" --project ai -- curl --fail --retry 15 --retry-connrefused --retry-delay 2 --connect-timeout 5 --max-time 10 --retry-max-time 90 http://garden-llama.garden.internal:8080/health
incus exec "$GARDEN_REMOTE:open-webui" --project ai -- curl --connect-timeout 5 --max-time 30 --fail http://garden-llama.garden.internal:8080/v1/models
```

Stop unless health succeeds within the retry budget and the catalog is available.
A running OCI process or device enumeration alone does not pass the gate.

### 4. Verify model output, GPU use and persistence

Both aliases `mimo` and `qwen36` must appear even before downloads. Send native
API requests from the trusted WebUI guest, one model at a time:

```fish
incus exec "$GARDEN_REMOTE:open-webui" --project ai -- curl --fail --max-time 7200 -H 'Content-Type: application/json' -d '{"model":"mimo","messages":[{"role":"user","content":"Say hello in one sentence."}],"max_tokens":64}' http://garden-llama.garden.internal:8080/v1/chat/completions
incus exec "$GARDEN_REMOTE:open-webui" --project ai -- curl --fail --max-time 7200 -H 'Content-Type: application/json' -d '{"model":"qwen36","messages":[{"role":"user","content":"Say hello in one sentence."}],"max_tokens":64}' http://garden-llama.garden.internal:8080/v1/chat/completions
incus exec "$GARDEN_REMOTE:open-webui" --project ai -- curl --fail --max-time 7200 -H 'Content-Type: application/json' -d '{"model":"mimo","messages":[{"role":"user","content":"Say hello again."}],"max_tokens":64}' http://garden-llama.garden.internal:8080/v1/chat/completions
incus exec "$GARDEN_REMOTE:open-webui" --project ai -- curl --connect-timeout 5 --max-time 30 --fail http://garden-llama.garden.internal:8080/models
incus console "$GARDEN_REMOTE:garden-llama" --project inference --show-log
```

Gate: responses contain actual generated text; logs show ROCm and layers
**offloaded**, not merely enumerated devices. Catalog status shows only the
selected model loaded (models-max 1). In WebUI select MiMo -> Qwen -> MiMo and
chat; switching needs no infrastructure apply/restart. First download/load may
be slow. Cold model requests may take up to the documented 7200-second timeout;
do not treat this as the short API readiness check. Cached models and chat state
must survive restarting both guests. Wait for WebUI via [guest readiness](readiness.md)
in `ai`, and repeat the bounded inference health check above before requests. Repeat
an API request and browser chat after restart and ensure no full re-download.

The immutable source URLs and expected SHA256/size are recorded in
`llama/models.lock.json`; checksum-named cache paths alone do not verify bytes.
After download, verify each file with `sha256sum` inside llama and compare against
the lock. Also check file sizes with `stat -c %s`. This can be expensive once;
record verified results and repeat after changing bytes, not every restart.

## Resume and rollback

Inspect container log, GPU devices/permissions, memory and cache
capacity, outbound Hugging Face DNS/TLS, selected model status and WebUI backend
URL. If Qwen cannot fit, review an explicit context/offload change. Do not enable
privileged mode or bypass checks with an architecture override. A failed initial
apply resumes with the same state/volumes and whole plan.

Before an update, save the current Git revision, image/launch settings, state,
and public presets outside the checkout. Stop the OCI guest before modifying a
mounted config volume. With the new declared configuration present, the whole
plan will include the public file update and the detected `running=false` drift;
OpenTofu returns running to true after the config dependency is updated:

```fish
incus stop "$GARDEN_REMOTE:garden-llama" --project inference
```

Run the whole plan/apply and repeat health/catalog/generated-text acceptance. If
an apply fails after a partial config update, keep it stopped until the declared
configuration is complete; do not manually re-enable it with half-written files.
For a longer repair, disable boot.autostart manually while stopped and record the
drift. The next reviewed apply must restore declared running/autostart settings.
An image upgrade can replace only this guest, with volumes retained; review it
separately from persistent-data changes.

Rollback: restore the previously recorded public preset/image/launch declarations,
stop the guest, review/apply a new whole plan, and repeat inference checks. Retain
cache and identities. Never lower stage or unset PCI to troubleshoot.
After rollback reconcile repository versus running state before continuation.

## Acceptance gate

Accept this capability only after every [verification](#verify), including
restart persistence, passes. Record revision, date, environment and results
privately. Continue to [backup and restore](recovery.md) only after acceptance.

Sources: [pinned llama server](https://github.com/ggml-org/llama.cpp/blob/b11382/tools/server/README.md),
[pinned provider files](https://github.com/lxc/terraform-provider-incus/blob/v1.2.0/docs/resources/storage_volume.md),
[Incus instance options](https://linuxcontainers.org/incus/docs/main/reference/instance_options/).
