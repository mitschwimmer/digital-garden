# Milestone 1: private network and guest

Prerequisite: [target/input checks](runbook.md#workstation-and-target-inputs), fresh
names/state and an existing pool. The root account is locked, SSH is disabled,
guest inbound ports are closed, and management uses authenticated Incus exec.
IPv6 is disabled until ingress. The new bridge gets an Incus-assigned IPv4 subnet
and outbound NAT/DNS. It does not isolate traffic routed from other host bridges.

Build the minimal seed and establish ignored local inputs on the workstation:

```fish
nix build .#edge-image --out-link result-edge-image
set -l GARDEN_IMAGE (readlink -f result-edge-image)
jq -n --arg remote "$GARDEN_REMOTE" --arg pool "$GARDEN_POOL" --arg image "$GARDEN_IMAGE" '{incus_remote: $remote, storage_pool: $pool, image_directory: $image, stage: 1}' > tofu/site.auto.tfvars.json
```

Keep `result-edge-image` as a GC root; do not rebuild/update the seed input for
ordinary guest maintenance. Check the seed archives exist. Run the [whole
plan/apply procedure](runbook.md#native-planapply-and-activation). First apply:
10 additions, no modifications/deletions. Seven volumes are established now so
later guest removal cannot accidentally remove their state. WebUI/llama are absent.

```fish
incus info "$GARDEN_REMOTE:edge" --project default
incus network show "$GARDEN_REMOTE:gardenbr0" --project default
incus exec "$GARDEN_REMOTE:edge" --project default -- cat /etc/os-release
incus exec "$GARDEN_REMOTE:edge" --project default -- systemctl is-system-running --wait
incus exec "$GARDEN_REMOTE:edge" --project default -- systemctl --failed
incus exec "$GARDEN_REMOTE:edge" --project default -- ip -4 address show eth0
incus exec "$GARDEN_REMOTE:edge" --project default -- getent hosts cache.nixos.org
incus exec "$GARDEN_REMOTE:edge" --project default -- curl -I --fail --max-time 30 https://cache.nixos.org
incus restart "$GARDEN_REMOTE:edge" --project default
incus exec "$GARDEN_REMOTE:edge" --project default -- systemctl is-system-running --wait
tofu -chdir=tofu plan -detailed-exitcode
```

Gate: running NixOS 26.05, no failed units, private IPv4, DNS and HTTPS work again
after restart, final plan exits 0. Record the allocated subnet locally. Confirm
unrelated workloads remain running. Exit 2 means plan changes; review them.

Failure/resume: inspect `incus info`, guest `networkctl`, `resolvectl`, routes and
failed-unit journals. Check pool capacity, Incus NAT/DHCP and outbound routing.
Complete a failed apply with the same seed/state and a new whole plan. Do not
invent a subnet from a partial inventory. For rollback keep volumes; stop edge
while investigating or follow [explicit reset/recovery](recovery.md). A routine
`tofu destroy` is blocked by protected volumes and is not a recovery operation.
Continue to [ingress](02-caddy-ingress.md) only after the gate passes.
