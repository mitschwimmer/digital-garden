# Iteration 1: boot a private NixOS edge

Goal: boot the repository-built NixOS edge container on a new backend bridge without taking over public ingress.
Acceptance: edge is running, has a gardenbr0 IPv4 lease, resolves DNS, reaches HTTPS, and survives a restart.

## Prerequisites

Use a Linux x86_64 workstation with Nix (flakes enabled), Python 3, and authenticated Incus client configuration.
Nix builds run on the workstation or its configured Linux builder, not on IncusOS.
Select your actual remote alias and an existing storage pool locally.
The raw host inventory and host-specific values are not recorded in this public repository.

## Changes and ownership

- flake.nix pins NixOS 26.05 to an immutable revision and builds metadata/rootfs archives.
- nix/hosts/edge.nix configures a locked root account, no SSH, DHCP and guest firewall.
- tofu/main.tf manages only gardenbr0, the custom image and edge in the explicit default project.
- scripts/prepare-edge.sh builds the image and writes ignored local inputs; it never applies infrastructure.
- GitHub Actions builds the image and validates the provider schema without homelab access.

Existing storage pools are read-only data sources. No old resources are imported.
The guest has 2 CPUs, 1 GiB RAM and an 8 GiB root volume on the selected existing pool.
It stays unprivileged; nesting is enabled for NixOS-in-Incus compatibility.
No GPU, public NIC, proxy, port forward, Caddy or Authelia is configured yet.
The new bridge has DHCP, outbound IPv4 NAT and generated Incus firewall rules.
IPv6 is explicitly disabled for this bootstrap; public IPv6 is designed at the ingress iteration.
A separate bridge is not a firewall isolation boundary: Incus can route between bridges.
The guest firewall admits no inbound service ports, though Incus management can execute commands.

Incus chooses an unused IPv4 subnet at creation, rather than guessing a range from incomplete LAN/VPN routing information.
OpenTofu preserves the chosen subnet. Once applied, record the assigned range before adding static service addresses.

## Validation status

Locally: shell syntax and isolated prepare-script argument/failure/input-generation checks.
This environment has neither Nix nor OpenTofu installed, so evaluation, image build,
provider validation and live plan cannot be claimed here.
GitHub Actions is provided for the build/schema checks; its actual result must be checked before applying.
The commands below repeat the required checks on your workstation. Stop on any failure.
No live deployment has been performed.

The input Nixpkgs revision and provider version are pinned.
The first successful workstation/CI run creates flake.lock and tofu/.terraform.lock.hcl;
retain and commit these lockfiles after validation. Neither lockfile contains secrets.
Keep local OpenTofu state backed up and out of Git. This slice handles no managed secrets.

## Apply

From the digital-garden checkout on your workstation:

```sh
git fetch origin
git switch homelab/bootstrap-inventory
git pull --ff-only
incus remote list
```

Set the actual client alias and storage pool, then confirm the target:

```sh
export GARDEN_REMOTE=YOUR_REMOTE
export GARDEN_POOL=YOUR_POOL
incus info "$GARDEN_REMOTE:" --project default
incus list "$GARDEN_REMOTE:" --project default
incus network list "$GARDEN_REMOTE:" --project default
```

Confirm the target is your intended IncusOS host. Neither edge nor gardenbr0 may already exist.
If either exists, report it instead of deleting or importing it.

Build and validate:

```sh
bash scripts/prepare-edge.sh "$GARDEN_REMOTE" "$GARDEN_POOL"
nix develop --command tofu -chdir=tofu fmt -check
nix develop --command tofu -chdir=tofu init -input=false
nix develop --command tofu -chdir=tofu validate
nix develop --command tofu -chdir=tofu plan -out=bootstrap.tfplan
```

Expected plan on first apply: 3 additions (network, image, instance), 0 changes, 0 destroys.
The selected existing pool is read, not created. Check the complete plan before running:

```sh
nix develop --command tofu -chdir=tofu apply bootstrap.tfplan
```

Do not copy old state into tofu. Do not run destroy from the old checkout as part of this iteration.

## Verify

```sh
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
nix develop --command tofu -chdir=tofu plan -detailed-exitcode
```

Expected: NixOS 26.05, running system, zero failed units, private IPv4, successful DNS/HTTPS,
and a second plan with no changes (exit 0). Compare the old instance list to confirm old workloads remain running.
If the system is degraded, include systemctl --failed and relevant journal output.
No Internet inbound reachability is expected or tested yet.

## Roll back

Only while this checkout/state still manages these three bootstrap resources and no application data has been added:

```sh
nix develop --command tofu -chdir=tofu plan -destroy -out=rollback.tfplan
```

Inspect the plan. It must delete only edge, its managed image and gardenbr0.
Then:

```sh
nix develop --command tofu -chdir=tofu apply rollback.tfplan
```

This discards the disposable edge root volume; the old homelab and existing pools remain.
Keep the state file even after rollback. Removing the checkout or reverting Git alone does not remove infrastructure.

## Next iteration

Add Caddy and one test HTTPS hostname with persistent ACME storage.
Before that step, provide the router's IPv4 forwarding and IPv6 routing/firewall arrangement.
Cleanup of old instances and volumes will be a separate, explicit deletion list;
do not remove IncusOS-managed backups/images/logs volumes or storage pools.
