# Current operator runbook

Use the maintained checkout for deployment and operation of the current
composition. Record `git rev-parse HEAD` in a private acceptance record. For
configuration changes and new services, start with the [contribution guide](contributing.md).
For host/data restoration, use [recovery](recovery.md).

## Workstation and target inputs

Commands use fish on an x86_64-linux Nix workstation (or configured Linux builder)
with flakes enabled. `nix develop --command fish` supplies tools from `flake.lock`;
the Incus provider is exactly 1.2.0 in `tofu/.terraform.lock.hcl`. Keep both locks.
The authenticated Incus client must reach the intended IncusOS host. Builds run
on the workstation, never on IncusOS. Do not install Nix into IncusOS.

```fish
nix develop --command fish
git rev-parse HEAD
incus version
tofu version
incus remote list
```

In this input step only, replace the placeholders with inspected values:

```fish
set -gx GARDEN_REMOTE YOUR_AUTHENTICATED_REMOTE
set -gx GARDEN_POOL YOUR_EXISTING_POOL
set -gx GARDEN_LAN_PARENT YOUR_INCUSOS_INSTANCES_BRIDGE
set -gx GARDEN_LAN_MAC YOUR_RESERVED_02_PREFIX_MAC
set -gx GARDEN_GPU_PCI YOUR_AMD_PCI_ADDRESS
set -gx GARDEN_BACKUP /ABSOLUTE/SECURE/BACKUP_DIRECTORY
set -gx SOPS_AGE_KEY_FILE "$HOME/.config/digital-garden/operator.agekey"
```

`GARDEN_BACKUP` is an absolute directory on the workstation, outside this checkout.
It is not an Incus storage pool or volume name. Use a secured directory and copy
its contents to separate off-host storage; no extra `data` volume is required.

Inspect before assigning LAN/GPU values; defer these inputs until their milestone
if unavailable. The MAC must start with `02` and use lowercase hexadecimal pairs.
Choose a new DHCP reservation; do not copy another live machine's identity.

```fish
incus info "$GARDEN_REMOTE:" --project default
incus project list "$GARDEN_REMOTE:"
incus list "$GARDEN_REMOTE:" --all-projects
incus network list "$GARDEN_REMOTE:" --project default
incus storage list "$GARDEN_REMOTE:"
incus storage volume list "$GARDEN_REMOTE:$GARDEN_POOL" --all-projects
incus query "$GARDEN_REMOTE:/os/1.0/system/network"
incus query "$GARDEN_REMOTE:/1.0/resources"
```

IncusOS exposes host interfaces as bridges; the selected LAN interface needs the
`instances` role. Inspect `incus network show` for that exact parent and the
IncusOS network configuration. Management API exposure/trusted client certificates
are separate from guest HTTP ingress. Maintain IncusOS's AMD driver/firmware and
`/dev/kfd`; PCI selection alone does not establish ROCm compatibility.

## Starting state and retained resources

A fresh installation has no managed guests, named application projects, volumes,
bridge or seed imports. Keep IncusOS-managed pools and unrelated workloads outside
this configuration's lifecycle. If managed objects already exist, inspect their
identity and state before proceeding; use [recovery](recovery.md) for imports or
restoration. Do not initialize over an existing installation.

Inspect OpenTofu's records alongside the host inventory above. A state entry does
not prove that the corresponding remote object exists:

```fish
tofu -chdir=tofu state list
```

If state is present, save it privately before changes. Use a new secured backup
directory per checkpoint:

```fish
umask 077
mkdir -p "$GARDEN_BACKUP"
chmod 0700 "$GARDEN_BACKUP"
tofu -chdir=tofu state pull > "$GARDEN_BACKUP/before-change.tfstate"
```

Compare individual `tofu state show` records with the target inventory. Preserve
valid records and the immutable `image_directory`; do not remove records to
conceal surviving resources or fix a failed service. The pinned image resource
has no importer; [image recovery](recovery.md) explains surviving seeds.
Review actual plans against the reconciled inventory, not addition counts alone.

## Operator execution rules

Run each numbered step separately and check its result before continuing. A pasted
block keeps executing after a failed command. `echo $status` reports only the
immediately preceding fish command; inspect `$pipestatus` immediately after pipes.
Treat missing mounts, failed builds/transfers/activation and failed health as stop
points. Use [bounded guest readiness](readiness.md) after creation and restart;
Incus RUNNING and a no-change infrastructure plan do not prove guest readiness.
Builds run on the workstation, infrastructure apply changes devices/volumes, and
NixOS activation installs/starts guest services. Complete all three when required.

## Project ownership

| Project | Guests and owned resources |
|---|---|
| `default` | Shared `edge` (Caddy/Authelia), its three volumes, edge seed image and `gardenbr0` |
| `ai` | `open-webui`, its two volumes and a separate import of the immutable NixOS seed |
| `inference` | `garden-llama`, its cache/config volumes and OCI image cache |

OpenTofu creates both named projects at stage 1 with local images, profiles,
volumes and buckets; networks and network zones use `default`. Existing storage
pools remain host-wide prerequisites. Project names are resource namespaces,
not automatic traffic isolation or application authentication. Keep guest names
unique on the shared bridge and verify cross-project DNS/reachability at stages
4 and 5. Existing trusted-caller policy remains in force.

Use explicit `--project` on guest/volume operations. Activation uses
`GARDEN_PROJECT`, set by each NixOS milestone. Project-local profiles are available
for future workloads; current guests keep `profiles = []` and explicit devices.
The current projects declare no restrictions or quotas. Follow the
[project guidance](projects.md) for future additions. Review identity and data
impacts explicitly when changing project ownership.

## Cumulative capabilities

| Stage | Guest activation | Gate | Expected infrastructure change from preceding accepted stage |
|---|---|---|---|
| 1 | Minimal seed | [Private guest](01-edge-bootstrap.md) | 13 additions: two projects, bridge, two seed images, edge, seven volumes |
| 2 | `edge-ingress` | [Caddy ingress](02-caddy-ingress.md) | One edge NIC update; no replacement/deletion |
| 3 | `edge` | [Authelia](03-authelia.md) | None; NixOS activation changes services |
| 4 | `open-webui` | [OIDC login](04-open-webui.md) | One WebUI guest addition |
| 5 | Keep edge/WebUI | [GPU inference](05-inference.md) | One OCI guest addition |
| Recovery | Restored matching systems/data | [Restore test](recovery.md) | Depends on surviving inventory; reviewed separately |

All seven volumes are created at stage 1, independently of guest stage selection:
`garden-caddy-state`, `garden-authelia-state`, `garden-edge-secrets`,
`garden-open-webui-state`, `garden-open-webui-secrets`, `garden-llama-cache`,
`garden-llama-config`. Cache quota is 64 GiB; reserve space for a 32 GiB OCI root,
24 GiB WebUI root, 8 GiB edge root and backups. Quotas do not guarantee capacity.
Protected volumes are not backups. Config volume contains only public presets.

Advance only after passing the preceding gate. `stage` controls guest presence
and LAN attachment, not acceptance or NixOS content. It never rewrites earlier
resource identities. Decreasing it removes guests/LAN and is an explicit removal
plan, not a retry. Do not use routine `-target` applies. Stateful volumes persist
across stages, but removing their HCL or state can bypass protection.

## Native plan/apply and activation

At each stage, edit the ignored `tofu/site.auto.tfvars.json` with the documented
`jq` command, then run this **whole plan** on the workstation:

```fish
tofu -chdir=tofu fmt -check -diff
tofu -chdir=tofu init -input=false -lockfile=readonly
tofu -chdir=tofu validate
tofu -chdir=tofu plan -out=current.tfplan
tofu -chdir=tofu show current.tfplan
```

Compare actual changes to the table and milestone. Stop for unexpected deletions,
seed/guest replacements or unrelated changes. Apply only the reviewed saved plan:

```fish
tofu -chdir=tofu apply current.tfplan
```

[Activation](activation.md) documents closure build, transfer, profile activation,
previous-generation rollback and failure resume. Changing guest services does
not require changing `image_directory`. Preserve its immutable path as a seed
identity throughout maintenance; retain a workstation GC root for it.

After each infrastructure apply, back up state outside the checkout. Do not
commit state, plans, machine keys, plaintext or raw host inventory. Secure the
backup directory (mode 0700), encrypt/off-host replicate backups, and keep the
operator age key separately backed up. [Recovery](recovery.md) gives native exports
and imports. A state backup is sensitive even though no secret plaintext is
intentionally supplied to OpenTofu.

## Maintenance, extension and resume

Keep the accepted stage and seed path. Review one pinned dependency/configuration
change, run native checks for the affected closure/configuration, back up affected
application data, plan/apply infrastructure changes and activate only affected
guests. Repeat affected acceptance gates and record the revision. An application
upgrade can migrate its database; a NixOS rollback does not reverse that migration.

After interruption, inspect `tofu state list`, the full plan, mounts, current
NixOS profile and services. Reuse existing local inputs, identities and ciphertext.
Apply a fresh reviewed plan to complete missing resources; reactivate the already
built closure if transfer/activation failed. Never reset to stage 1, regenerate
keys, replace the seed or delete storage to fix a failed service. Troubleshooting
and continuation gates are in each milestone. Extension adds a capability and its
explicit dependencies without rechecking unrelated accepted services.

Sources: [IncusOS direct attachment](https://linuxcontainers.org/incus-os/docs/main/tutorials/network-direct-attach/),
[IncusOS network roles](https://linuxcontainers.org/incus-os/docs/main/reference/system/network/),
[pinned provider volume schema](https://github.com/lxc/terraform-provider-incus/blob/v1.2.0/docs/resources/storage_volume.md).
