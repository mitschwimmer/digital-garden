# Inspect the platform and establish local inputs

- [Establish workstation and target inputs](#establish-workstation-and-target-inputs)
- [Starting state and retained resources](#starting-state-and-retained-resources)
- [Select infrastructure and services explicitly](#select-infrastructure-and-services-explicitly)
- [Migrate an existing selector once](#migrate-an-existing-selector-once)

Use this reference when provisioning, reconciling, troubleshooting or restoring
infrastructure. Inspect the intended target before choosing inputs or state.
Run commands from the repository root; keep local inventory and credentials
private. Follow [infrastructure reconciliation](infrastructure.md) for changes.

## Establish workstation and target inputs

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

Inspect before assigning LAN/GPU values; defer inputs until the service needs them
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

For a new installation, establish which managed resources are absent. Keep IncusOS-managed pools and unrelated workloads outside
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

## Select infrastructure and services explicitly

`tofu/services.tf` defines independent boolean inputs, all defaulting to false:

| Input | Effect when true | Required inputs |
|---|---|---|
| `enable_edge_lan` | Attach edge's LAN NIC | Inspected `edge_lan_parent` and stable `edge_lan_mac` |
| `enable_webui` | Create the Open WebUI guest | Existing immutable seed and application secret preparation before activation |
| `enable_inference` | Create the private llama.cpp guest | Inspected `llama_gpu_pci`, host KFD/ROCm support and capacity |

The shared edge guest, bridge, application projects, NixOS seed imports and all
seven persistent volumes exist independently of these settings. Disabling a
service removes its disposable guest, retaining its volumes; disabling edge LAN
detaches its NIC. These are reviewed lifecycle changes, never troubleshooting
resets. Resource addresses stay unchanged when migrating existing inputs.

NixOS closure activation still determines guest services. Enabling WebUI does
not enable inference; enabling inference does not create WebUI or attach the
edge LAN NIC. A service's dependencies and reachability remain explicit.

Reserve capacity for a 32 GiB OCI root, 24 GiB WebUI root, 8 GiB edge root,
64 GiB inference cache quota and backups. Quotas do not guarantee available
storage. Refer to [projects](projects.md) for namespace and volume ownership.

## Migrate an existing selector once

The removed `stage` input is retained only as a rejecting compatibility guard.
Supplying a non-null value fails validation instead of silently selecting the
new false defaults. Preserve current inventory, state, seed path, keys and data;
back up ignored local inputs before converting them.

| Previous value | `enable_edge_lan` | `enable_webui` | `enable_inference` |
|---|---|---|---|
| 1 | false | false | false |
| 2 or 3 | true | false | false |
| 4 | true | true | false |
| 5 | true | true | true |

For the ignored JSON inputs, run on the fish workstation after backup:

```fish
cp tofu/site.auto.tfvars.json "$GARDEN_BACKUP/before-service-inputs.json"
jq 'if has("stage") then if (.stage | IN(1, 2, 3, 4, 5)) then . + {enable_edge_lan: (.stage >= 2), enable_webui: (.stage >= 4), enable_inference: (.stage >= 5)} | del(.stage) else error("Invalid legacy stage; inspect the inputs") end else . end' tofu/site.auto.tfvars.json > tofu/site.auto.tfvars.json.tmp
```

Require jq success before moving the temporary file into place:

```fish
mv tofu/site.auto.tfvars.json.tmp tofu/site.auto.tfvars.json
```

For HCL inputs, use the table to replace `stage` with all three explicit booleans.
Inspect actual target/state, validate and review the whole plan. A conversion
alone must not detach LAN, add/remove guests or replace images/volumes. Stop and
reconcile any mismatch before apply. This input conversion does not change state
addresses or authorize service removal. Subsequent edits change only the intended
boolean; all other service settings remain intact.
