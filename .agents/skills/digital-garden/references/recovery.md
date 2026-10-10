# Back up and restore identities and data

- [Scope and inputs](#scope-and-inputs)
- [Apply the change: back up with native commands](#apply-the-change-back-up-with-native-commands)
- [Resume and rollback: replace a guest with storage intact](#resume-and-rollback-replace-a-guest-with-storage-intact)
- [Apply the change: restore after host loss](#apply-the-change-restore-after-host-loss)
- [Check an independent restore](#check-an-independent-restore)

## Scope and inputs

Restore matching source, inputs, infrastructure records, identities and data.
Require the tested revision, matching backups and a secure off-host backup destination;
inspect the surviving target before choosing state or importing resources.
Run native backup/restore commands from the fish workstation.
Preserve encrypted consumer files, the operator recovery key, persistent machine
keys, corresponding application data, current source/lockfiles, local inputs,
OpenTofu state and the immutable seed archives. Protected volumes are not backups.

## Apply the change: back up with native commands

On the workstation, with `GARDEN_BACKUP` pointing at a new secured backup set
outside the checkout (0700), back up state and local inputs. This is a workstation
filesystem path, not a volume inside the Incus pool. Retain a copy on storage
independent of the IncusOS host and its pools:

```fish
umask 077
mkdir -p "$GARDEN_BACKUP"
chmod 0700 "$GARDEN_BACKUP"
tofu -chdir=tofu state pull > "$GARDEN_BACKUP/terraform.tfstate"
cp tofu/site.auto.tfvars.json "$GARDEN_BACKUP/site.auto.tfvars.json"
git rev-parse HEAD > "$GARDEN_BACKUP/revision.txt"
mkdir -p "$GARDEN_BACKUP/seed"
cp result-edge-image/metadata.tar.xz result-edge-image/rootfs.tar.xz "$GARDEN_BACKUP/seed/"
```

Save the operator key separately using your encrypted key-backup process. Copy
ciphertext and public policy from the recorded revision. Ensure no apply is running
during state backup; inspect backup success/size. Off-host replicate this set.

For consistent SQLite/application state, enter a maintenance window and stop
WebUI/Authelia/Caddy before volume export. Keep Authelia's storage key and database
in the same recovery set. Caddy downtime affects public ingress. Stop inference
if exporting its optional model cache. These commands run from the workstation:

```fish
incus exec "$GARDEN_REMOTE:open-webui" --project ai -T -- env TERM=xterm systemctl stop open-webui
incus exec "$GARDEN_REMOTE:edge" --project default -T -- env TERM=xterm systemctl stop authelia-main caddy
incus storage volume export "$GARDEN_REMOTE:$GARDEN_POOL" garden-open-webui-state "$GARDEN_BACKUP/webui.tar.gz" --project ai
incus storage volume export "$GARDEN_REMOTE:$GARDEN_POOL" garden-authelia-state "$GARDEN_BACKUP/authelia.tar.gz" --project default
incus storage volume export "$GARDEN_REMOTE:$GARDEN_POOL" garden-caddy-state "$GARDEN_BACKUP/caddy.tar.gz" --project default
incus storage volume export "$GARDEN_REMOTE:$GARDEN_POOL" garden-edge-secrets "$GARDEN_BACKUP/edge-secrets.tar.gz" --project default
incus storage volume export "$GARDEN_REMOTE:$GARDEN_POOL" garden-open-webui-secrets "$GARDEN_BACKUP/webui-secrets.tar.gz" --project ai
incus exec "$GARDEN_REMOTE:edge" --project default -T -- env TERM=xterm systemctl start caddy authelia-main
incus exec "$GARDEN_REMOTE:open-webui" --project ai -T -- env TERM=xterm systemctl start open-webui
```

Check every exit status; do not resume dependent service use on a failed backup
or restart check. Repeat the identity and WebUI service/health checks after starting
them, and the bounded inference health check if inference was stopped. If restart
requires boot readiness, use [guest readiness](readiness.md) for the exact project.
Private keys are inside secret-volume exports: encrypt and restrict
them, never upload them to public Git. The public config volume is reproducible
from Git. Model cache may be exported similarly after stopping inference, or
redownloaded from pinned URLs if acceptable. Verify backup hashes, readable archive
metadata and off-host replication. Restore acceptance is mandatory below.

## Resume and rollback: replace a guest with storage intact

Keep existing inputs/state, stage, machine identities and all volumes. Back up
application state before replacing a disposable root. Build/retain the required
seed/guest closures; inspect a full plan with `-replace=incus_instance.edge` (or
`incus_instance.webui[0]` / `incus_instance.llama[0]`) only when replacement is
actually required. Save and review that plan: only the intended guest may be
replaced. Apply it, reactivate the matching NixOS generation and repeat that
service and its affected dependencies. No secrets initialization occurs.
For llama, provider-delivered config/cache precede startup automatically.

## Apply the change: restore after host loss

Restore IncusOS installation, trusted client access, correct pools and LAN roles,
AMD support, then inspect instance/network/volume inventory from [platform inspection](platform.md).
Check whether any referenced volume/image/guest exists before choosing state.
Never blindly push old state or apply it against a different host.

* If infrastructure survives, restore the matching state backup and ignored local
  inputs; review a full refreshed plan. Stop for unexpected removal/replacement.
* If the host and all managed resources are empty, start a **new** state and restore
  backed-up volumes before guest creation. Old state remains archived as evidence.
* If only some resources survive, import those exact objects into a new state using
  the pinned provider IDs below, then review the whole plan. Do not import absent
  objects. Verify original image identity when importing surviving guests.

Before any OpenTofu import, restore valid local inputs and the immutable seed
archives/path. Provider import evaluates configuration, so a missing workstation
seed path can fail even when the remote object exists.

On a new workstation, rebuild the recorded seed revision and retain its GC root.
On a completely empty host, alternatively restore archived seed files into an
immutable store directory with native Nix:

```fish
set -l GARDEN_IMAGE (nix store add-path "$GARDEN_BACKUP/seed")
ln -s "$GARDEN_IMAGE" result-edge-image
jq --arg image "$GARDEN_IMAGE" '.image_directory = $image' tofu/site.auto.tfvars.json > tofu/site.auto.tfvars.json.tmp
mv tofu/site.auto.tfvars.json.tmp tofu/site.auto.tfvars.json
```

Require both archived files, verify their backup hashes, and do not replace an
existing GC-root link without inspecting its target. This produces a new local
store path; surviving guests require a separate reviewed seed/replacement decision
or recovery of the original state/store identity. Do not silently change their
seed input. A completely empty host may choose a new seed path while retaining
restored data volumes.
Restore operator/machine keys or [update recipients](secrets.md) while preserving
secret values. Do not initialize all-new crypto for a restored database.

For an empty host, first recreate the two application projects with the declared
feature settings so volumes can be restored into their original namespaces:

```fish
for project in ai inference
    incus project create "$GARDEN_REMOTE:$project" -c features.images=true -c features.profiles=true -c features.storage.volumes=true -c features.storage.buckets=true -c features.networks=false -c features.networks.zones=false
end
```

For surviving projects, inspect `incus project show` instead of recreating them;
verify their settings match `tofu/projects.tf`. With valid local inputs and
`tofu init` complete, import these existing projects into the new state before
planning; skip imports only when the objects are already tracked:

```fish
tofu -chdir=tofu import incus_project.ai "$GARDEN_REMOTE:ai"
tofu -chdir=tofu import incus_project.inference "$GARDEN_REMOTE:inference"
```

Native imports restore volumes under their declared names and original projects;
commands below use the same selected host-wide pool:

```fish
incus storage volume import "$GARDEN_REMOTE:$GARDEN_POOL" "$GARDEN_BACKUP/webui.tar.gz" garden-open-webui-state --project ai
incus storage volume import "$GARDEN_REMOTE:$GARDEN_POOL" "$GARDEN_BACKUP/authelia.tar.gz" garden-authelia-state --project default
incus storage volume import "$GARDEN_REMOTE:$GARDEN_POOL" "$GARDEN_BACKUP/caddy.tar.gz" garden-caddy-state --project default
incus storage volume import "$GARDEN_REMOTE:$GARDEN_POOL" "$GARDEN_BACKUP/edge-secrets.tar.gz" garden-edge-secrets --project default
incus storage volume import "$GARDEN_REMOTE:$GARDEN_POOL" "$GARDEN_BACKUP/webui-secrets.tar.gz" garden-open-webui-secrets --project ai
```

An existing destination is an error, not permission to overwrite it. With local
inputs restored and `tofu init` complete, import each restored volume into state:

```fish
tofu -chdir=tofu import incus_storage_volume.webui "$GARDEN_REMOTE:ai/$GARDEN_POOL/garden-open-webui-state"
tofu -chdir=tofu import incus_storage_volume.authelia "$GARDEN_REMOTE:default/$GARDEN_POOL/garden-authelia-state"
tofu -chdir=tofu import incus_storage_volume.caddy "$GARDEN_REMOTE:default/$GARDEN_POOL/garden-caddy-state"
tofu -chdir=tofu import incus_storage_volume.edge_secrets "$GARDEN_REMOTE:default/$GARDEN_POOL/garden-edge-secrets"
tofu -chdir=tofu import incus_storage_volume.webui_secrets "$GARDEN_REMOTE:ai/$GARDEN_POOL/garden-open-webui-secrets"
```

Restore optional cache/config archives with `incus storage volume import` using
`--project inference`, then import them into state with
`incus_storage_volume.llama_cache` / `incus_storage_volume.llama_config` and IDs
`REMOTE:inference/POOL/garden-llama-cache` /
`REMOTE:inference/POOL/garden-llama-config`. If absent, let OpenTofu create them.
Public presets will be reconciled from this checkout.

For surviving bridges and guests, use these provider IDs:

| Resource | Import ID |
|---|---|
| `incus_network.private` | `REMOTE:default/gardenbr0` |
| `incus_instance.edge` | `REMOTE:default/edge,image=IMAGE_ID` |
| `incus_instance.webui[0]` | `REMOTE:ai/open-webui,image=IMAGE_ID` |
| `incus_instance.llama[0]` | `REMOTE:inference/garden-llama,image=IMAGE_ID` |

Substitute these values only from
verified inventory/state; include the original seed fingerprint (OCI digest for
llama) or the provider may replace an imported guest. Inspect the
[pinned network](https://github.com/lxc/terraform-provider-incus/blob/v1.2.0/docs/resources/network.md),
[instance](https://github.com/lxc/terraform-provider-incus/blob/v1.2.0/docs/resources/instance.md)
import docs before importing surviving objects. The pinned image resource has no
native importer: use matching backed-up state for surviving managed seed images
in `default` and `ai`.
If that state is unavailable, separately review deleting only the reproducible
seed cache image in its owning project and recreating it from exactly the
backed-up archives; do not
delete guests or volumes. Confirm the recreated fingerprint matches the guest
import identity before accepting the plan.

Choose the intended resource selection for an empty host, keeping restored
volumes and providing the required LAN/GPU inputs. Review the
full plan: only missing resources are additions, restored volumes are retained;
inspect any configuration updates. Apply missing infrastructure and activate the appropriate guest closures,
using restored keys/ciphertext/data. Verify the restored services and their
dependencies; do not run fresh secret generation.
For partially surviving infrastructure keep the existing resource selection and
reconcile only missing resources. All live checks are pending until repeated.

## Check an independent restore

Use an isolated spare host/pool and copied state/inputs with a reviewed fresh target;
do not import restored copies into production state. Restore selected irreplaceable
Authelia and WebUI data **together with their stable keys** using the above native
commands, then build/apply/activate the same revision. Use controlled DNS/routing
so recovery testing cannot take over production public names. Verify decryption,
existing TOTP/user identity, allowed/denied roles, retained chats/uploads and
application health; test restored Caddy state and optional cache as appropriate.
Record revision/date/environment/result. If a spare target is unavailable, mark
the restore test pending; inspecting an archive is not a restore test. Cleanup of the
isolated test has its own reviewed deletion list.

Sources: [Incus volume backup](https://linuxcontainers.org/incus/docs/main/howto/storage_backup_volume/),
[pinned volume import IDs](https://github.com/lxc/terraform-provider-incus/blob/v1.2.0/docs/resources/storage_volume.md).
