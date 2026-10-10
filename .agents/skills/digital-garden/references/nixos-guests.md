# Provision NixOS guests from an immutable seed

## Scope and inputs

| Field | Requirement |
|---|---|
| Goal | Provide a restart-safe private guest, DNS and outbound HTTPS. |
| Prerequisites | [Deployment inputs](platform.md#establish-workstation-and-target-inputs), unused managed names/state and an existing pool. |
| Sources | `tofu/main.tf`, `tofu/projects.tf`, `tofu/open-webui.tf`, `tofu/llama.tf`, `nix/hosts/edge-bootstrap.nix`, `flake.nix`. |
| Execution and inputs | Workstation; new local inputs, immutable seed path, selected remote and pool. |
| Expected infrastructure effects | Shared bridge, edge guest, application projects, seed imports and persistent volumes on a new target; inspect the actual plan. |

Keep the root account locked, disable SSH and guest inbound ports, and manage
through authenticated Incus exec.
IPv6 is disabled until ingress. The new bridge gets an Incus-assigned IPv4 subnet
and outbound NAT/DNS. It does not isolate traffic routed from other host bridges.

## Apply the change

### 1. Build the seed and establish new inputs

Check [starting state](platform.md#starting-state-and-retained-resources) first.
For an existing or restored installation, preserve its inputs and seed identity
and use [recovery](recovery.md). For a new installation, build the seed and
initialize local inputs on the workstation:

```fish
nix build .#edge-image --out-link result-edge-image
set -l GARDEN_IMAGE (readlink -f result-edge-image)
jq -n --arg remote "$GARDEN_REMOTE" --arg pool "$GARDEN_POOL" --arg image "$GARDEN_IMAGE" '{incus_remote: $remote, storage_pool: $pool, image_directory: $image, stage: 1}' > tofu/site.auto.tfvars.json
```

Keep `result-edge-image` as a GC root; do not rebuild/update the seed input for
ordinary guest maintenance. Check the seed archives exist. Run the [whole
plan/apply procedure](infrastructure.md#review-and-apply-the-whole-plan). First apply:
13 additions on a wholly fresh target: two projects, two project-scoped seed images, the bridge, edge,
and seven volumes; no modifications/deletions. Seven volumes are established now so
later guest removal cannot accidentally remove their state. WebUI/llama are absent.
For restored or surviving resources, review the plan against actual inventory;
addition counts alone do not establish safety.

### 2. Apply infrastructure and wait for guest readiness

Apply only the reviewed saved plan. This seed already boots the minimal NixOS
configuration; it does not contain Caddy. Set the readiness target:

```fish
set -gx GARDEN_GUEST edge
set -gx GARDEN_PROJECT default
```

Complete [guest readiness](readiness.md) before checking network/application state.

## Check the result

### 3. Verify initial state and networking

```fish
incus project show "$GARDEN_REMOTE:ai"
incus project show "$GARDEN_REMOTE:inference"
incus info "$GARDEN_REMOTE:edge" --project default
incus network show "$GARDEN_REMOTE:gardenbr0" --project default
incus exec "$GARDEN_REMOTE:edge" --project default -- cat /etc/os-release
incus exec "$GARDEN_REMOTE:edge" --project default -- ip -4 address show eth0
incus exec "$GARDEN_REMOTE:edge" --project default -- getent hosts cache.nixos.org
incus exec "$GARDEN_REMOTE:edge" --project default -- curl -I --fail --max-time 30 https://cache.nixos.org
```

Expect NixOS 26.05, project-local images/volumes, an IPv4 address on eth0,
DNS answers and HTTP 200 from the Nix cache. Stop at the first failed command.

### 4. Restart and repeat the checks

```fish
incus restart "$GARDEN_REMOTE:edge" --project default
```

Repeat [guest readiness](readiness.md), then repeat **all three** network checks:

```fish
incus exec "$GARDEN_REMOTE:edge" --project default -T -- ip -4 address show eth0
incus exec "$GARDEN_REMOTE:edge" --project default -T -- getent hosts cache.nixos.org
incus exec "$GARDEN_REMOTE:edge" --project default -T -- curl -I --fail --max-time 30 https://cache.nixos.org
tofu -chdir=tofu plan -detailed-exitcode
echo $status
```

Require running NixOS 26.05, no failed units, private IPv4, DNS and HTTPS work again
after restart, final plan exits 0. Record the allocated subnet locally. Confirm
unrelated workloads remain running. Exit 2 means plan changes; review them.

## Resume and rollback

Use [boot diagnostics](readiness.md#resume-and-rollback) first. Then inspect `incus info`, guest `networkctl`, `resolvectl`, routes and
failed-unit journals. Check pool capacity, Incus NAT/DHCP and outbound routing.
Complete a failed apply with the same seed/state and a new whole plan. Do not
invent a subnet from a partial inventory. For rollback keep volumes; stop edge
while investigating or follow [recovery](recovery.md). A routine
`tofu destroy` is blocked by protected volumes and is not a recovery operation.
