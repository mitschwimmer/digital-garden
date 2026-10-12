# Establish workstation and host inputs

Use an x86_64-linux Nix workstation (or configured Linux builder), flakes, fish,
and an authenticated Incus client. Build on the workstation, never IncusOS.
From the checkout enter `nix develop --command fish`. Each operation then runs
inside exactly one root from [architecture](architecture.md).

Inspect the target before filling root-local `site.auto.tfvars.json`:

```fish
incus remote list
incus info YOUR_REMOTE: --project default
incus list YOUR_REMOTE: --all-projects
incus storage list YOUR_REMOTE:
incus network list YOUR_REMOTE: --project default
incus query YOUR_REMOTE:/os/1.0/system/network
incus query YOUR_REMOTE:/1.0/resources
```

Replace YOUR_REMOTE only with the inspected client alias. Set `incus_remote` and
`storage_pool` independently in each root. All roots for this installation must
point at the same inspected host/pool. Keep local files private and ignored.
Do not use alternate Tofu workspaces or TF_* state/CLI overrides.

| Root | Additional required inputs |
|---|---|
| platform | None |
| edge | Its immutable `image_directory`, `edge_lan_parent`, stable `edge_lan_mac` |
| identity | Its immutable `image_directory` |
| open-webui | Its immutable `image_directory` |
| inference | Inspected `llama_gpu_pci` |

LAN parent must be an IncusOS instances-role bridge; MAC must start with `02`.
Reserve its DHCP address. Inspect AMD driver/firmware, `/dev/kfd`, compatible ROCm
and capacity before applying inference. Retain image paths after creation.
There are no global service selectors: only operating a root can change its
resources. Do not use `-target` to simulate isolation inside a larger state.

## Starting state and retained resources

The fresh-install path assumes old managed resources were intentionally removed
by the operator. This repository does not wipe the host. Never reuse old state
files or reinterpret them as the new roots. Review host inventory before init.
After first deployment preserve each root's state, local inputs, seed GC root,
keys and data. Do not erase records to fix a failed service.

After initial creation, before a change in an existing root, choose a new secured off-host checkpoint:

```fish
umask 077
set -l backup /ABSOLUTE/SECURE/CHECKPOINT
mkdir -p "$backup"
tofu state pull > "$backup/state.json"
cp site.auto.tfvars.json "$backup/"
```

Check exit status, encrypt/protect the backup, and record root and revision.
See [recovery](recovery.md) for matching data and identity preservation.
