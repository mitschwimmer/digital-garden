# Milestone 1: private network and guest

Prerequisite: [target/input checks](runbook.md#workstation-and-target-inputs), fresh
names/state and an existing pool. The root account is locked, SSH is disabled,
guest inbound ports are closed, and management uses authenticated Incus exec.
IPv6 is disabled until ingress. The new bridge gets an Incus-assigned IPv4 subnet
and outbound NAT/DNS. It does not isolate traffic routed from other host bridges.

## 1. Build the seed and establish new inputs

Check [starting state](runbook.md#starting-state-and-retained-resources) first.
For an existing or restored installation, preserve its inputs and seed identity
and use [recovery](recovery.md). For a new installation, build the seed and
initialize stage 1 on the workstation:

```fish
nix build .#edge-image --out-link result-edge-image
set -l GARDEN_IMAGE (readlink -f result-edge-image)
jq -n --arg remote "$GARDEN_REMOTE" --arg pool "$GARDEN_POOL" --arg image "$GARDEN_IMAGE" '{incus_remote: $remote, storage_pool: $pool, image_directory: $image, stage: 1}' > tofu/site.auto.tfvars.json
```

Keep `result-edge-image` as a GC root; do not rebuild/update the seed input for
ordinary guest maintenance. Check the seed archives exist. Run the [whole
plan/apply procedure](runbook.md#native-planapply-and-activation). First apply:
13 additions on a wholly fresh target: two projects, two project-scoped seed images, the bridge, edge,
and seven volumes; no modifications/deletions. Seven volumes are established now so
later guest removal cannot accidentally remove their state. WebUI/llama are absent.
For restored or surviving resources, review the plan against actual inventory;
addition counts alone do not establish safety.

## 2. Apply infrastructure and wait for guest readiness

Apply only the reviewed saved plan. This seed already boots the minimal NixOS
configuration; it does not contain Caddy. Set the readiness target:

```fish
set -gx GARDEN_GUEST edge
set -gx GARDEN_PROJECT default
```

Complete [guest readiness](readiness.md) before checking network/application state.

## 3. Verify initial state and networking

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

## 4. Restart and repeat the gate

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

Gate: running NixOS 26.05, no failed units, private IPv4, DNS and HTTPS work again
after restart, final plan exits 0. Record the allocated subnet locally. Confirm
unrelated workloads remain running. Exit 2 means plan changes; review them.

## Failure and resume

Use [boot diagnostics](readiness.md#failure-diagnostics) first. Then inspect `incus info`, guest `networkctl`, `resolvectl`, routes and
failed-unit journals. Check pool capacity, Incus NAT/DHCP and outbound routing.
Complete a failed apply with the same seed/state and a new whole plan. Do not
invent a subnet from a partial inventory. For rollback keep volumes; stop edge
while investigating or follow [recovery](recovery.md). A routine
`tofu destroy` is blocked by protected volumes and is not a recovery operation.
Continue to [ingress](02-caddy-ingress.md) only after the gate passes.
