# Reconcile declared infrastructure

Use this workflow for new resources, existing installations and recovery imports.
Require [inspected target inputs](platform.md), matching state and immutable seed
archives where needed. OpenTofu owns Incus resources and OCI launch/configuration;
NixOS guest services require separate [activation](activation.md).

## Inspect and prepare

1. Identify requested additions, updates and removals from source and inventory.
   Use the [resource-selection reference](platform.md#select-infrastructure-and-services-explicitly)
   for the current HCL. Keep unrelated services and retained volumes intact.
2. Preserve matching state, local inputs and seed identity. Back up affected data
   before replacement or storage changes. Import surviving resources using
   [recovery](recovery.md) rather than pretending the host is empty.
3. Build a missing NixOS seed using [guest provisioning](nixos-guests.md).
   Existing guest service changes use closure activation, not a new seed input.

## Review and apply the whole plan

After changing declared resources or ignored `tofu/site.auto.tfvars.json`, run
this **whole plan** on the workstation:

```fish
tofu -chdir=tofu fmt -check -diff
tofu -chdir=tofu init -input=false -lockfile=readonly
tofu -chdir=tofu validate
tofu -chdir=tofu plan -out=current.tfplan
tofu -chdir=tofu show current.tfplan
```

Compare actual changes to the requested resources and inspected inventory. Stop for unexpected deletions,
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

## Check the result and resume

Inspect actual mounts, device/network assignments and affected services after
apply. Use [readiness](readiness.md) for NixOS guests and the service's health,
access and persistence checks. A completed apply or no-change plan establishes
infrastructure consistency only.

After interruption, inspect state and refreshed inventory, repair declared
inputs, review a new whole plan and complete missing operations. Reuse data,
identities and seed paths. Do not remove state records, lower selection, regenerate
keys or delete storage to repair a failed service. Resume failed NixOS transfers
or activation with the already-built closure.

Record the tested revision and distinguish the plan/apply result from service
verification. See [validation](validation.md) for evidence and unavailable checks.
