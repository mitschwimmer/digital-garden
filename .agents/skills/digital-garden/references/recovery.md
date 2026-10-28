# Back up and restore an operation root

- [Backup](#backup)
- [Restore](#restore)
- [Data rollback](#data-rollback)

## Backup

Inspect the owning root's HCL, applied inventory and service reference. Identify
all durable volumes, their actual project/pool, external dependencies and data/key
coupling. Use the service's consistency group: media, databases and keys may live
on different pools and must represent the same checkpoint.

Preserve source revision/locks, root state/local inputs/provider lock, seed archive
and GC root, retained system generations/closure paths, SOPS policy/ciphertext,
operator and machine age keys, and application data/signing/encryption identities.
Keep certificate state
with its owning guest. Encrypt/protect backup storage and keep it off-host so it
survives loss of IncusOS. Never print credentials. `prevent_destroy`, on-host
snapshots and automatic local database dumps are not off-host backups.

Quiesce the service for a consistent snapshot/export of the entire group, or use
its supported online backup method and verify that method independently. Without
an established online procedure, stop the whole guest, snapshot/export each
required volume to a new protected checkpoint, check every exit status and only
then restart. Use actual root/project/pool identities, not another service's
example. Save state using [platform inputs](platform.md#starting-state-and-retained-resources).
Record version, database major/extension versions and exact volume identities.
Test restoration independently before relying on the backup.

## Restore

Inspect surviving resources first. Restore matching root state where available;
otherwise use the pinned provider's supported imports for surviving resources.
Do not apply empty state over live resources. The pinned Incus image resource
has no importer: review explicit recreation using the retained seed archive,
rather than inventing an import. Import volume exports into absent volumes on
an isolated target and reconcile owning state before attachment. Never overwrite
surviving volumes blindly or regenerate secrets to repair missing recipient keys.

Restore platform before leaf roots. Restore the service's matching volume group,
keys and ciphertext before starting compatible application software. Verify mounts
and deployment identity. Bring up edge before identity certificate issuance, and
identity before dependent OIDC login. For NixOS select the matching configuration
and destination using [deployment](deployment.md); for OCI reconcile the pinned
declaration through a reviewed whole plan.

Test actual restored content and metadata, allowed/denied access, trusted TLS and
restart persistence on an isolated recovery target. An archive listing or newly
created volume is not restoration evidence. Reconcile source with accepted running
state before reopening traffic; record revision, environment and observed results
privately. Restoring an identity backup can restore previously revoked access.

## Data rollback

A NixOS closure rollback or OCI image/config rollback does not reverse database
migrations. Check the service's compatibility limits before old software opens
newer data. Record the running and selected closures and retain a pre-upgrade
checkpoint.

When incompatible data must be restored, stop and runtime-mask the service's
writers before NixOS rollback. The rollback may select the old profile
but fail acceptance because those units are masked. Select a retained generation
compatible with the checkpoint and verify the selected closure; on selection
failure stop and repair it.
Then stop the guest, restore the matching consistency group and start the old
generation (reboot clears runtime masks). Restore coupled secret state/ciphertext
only as required by that checkpoint. Repeat data, access and restart checks before
reopening traffic. Never select another system's closure.

Source: [Incus custom-volume backup](https://linuxcontainers.org/incus/docs/main/howto/storage_backup_volume/).
