# Immich encrypted offsite backup concept

Status: proposed; backup automation and cloud storage are not yet configured.

## Scope and accepted loss

Back up the whole `/var/lib/immich` directory nightly with Restic to a private
S3-compatible bucket. Immich's automatic database dumps in `backups/` provide
the database backup; do not copy the running PostgreSQL data directory.
Include originals, profiles, thumbnails, transcodes and completed dumps.
External libraries, if added later, need their own backup paths.

This is a pragmatic backup for a quiet instance: losing one or two days of
changes is acceptable. The dump and live media copy are not an atomic checkpoint.
Uploads after the dump may be absent from the restored database; deletions or
moves during the interval may leave database references to missing files.
The consistent volume checkpoint in [Immich](immich.md#backup-restore-and-rollback)
remains the procedure before upgrades.

## Nightly operation

NixOS owns a systemd timer and Restic job inside the Immich guest; IncusOS needs
no new software. Before implementation, verify the actual automatic dump
schedule, timezone and retention. Run the offsite job after the dump normally
finishes, without stopping Immich.

Require the media mount and a completed, non-empty database dump no older than
24 hours. Check compressed dump integrity before upload and fail visibly if
these prerequisites are missing. Schedule separation alone is not proof that
a dump succeeded. Treat Restic read errors or partial backups as failures.

Record the source revision and Immich/PostgreSQL versions with each backup.
Start with 14 daily, 8 weekly and 12 monthly snapshots. Run retention/pruning
separately from backup, with credentials held outside the guest. Alert on job
failure or no successful offsite backup within 48 hours. Check repository
integrity regularly, including rotating reads of stored data.

## Encryption and destination

Restic encrypts contents and filenames locally before upload. Use a dedicated
bucket and bucket-scoped credentials; Backblaze B2 via S3 is a candidate,
with the provider and region still to be selected. Keep the repository in
immediately readable storage. Let Restic manage snapshot retention; do not
expire current repository objects through bucket lifecycle rules.

Enable versioning where supported and prevent the guest credentials from
permanently deleting historical versions or changing bucket policy. Validate
permissions against backup and lock cleanup; deny-all deletion can break
Restic. Keep administrative/pruning credentials off the guest. Define
historical-version cleanup separately. Object Lock is optional and requires
testing with Restic before adoption.

Manage the Restic password and upload credentials through SOPS/sops-nix.
Plaintext must stay out of Git, the Nix store and logs.

## Recovery requirements and acceptance

Preserve the repository and relevant revision, encrypted application/backup
secrets, an independently accessible SOPS operator recovery key, and cloud
account recovery access. Verify that the operator key decrypts all required
ciphertext, including the Restic password and both OAuth consumers' secrets.
Replacement S3 access keys can be issued through the cloud account.

For a rebuilt Immich guest, a new machine age key can be provisioned and the
existing secret values re-encrypted for it; the original guest key is not
required when operator decryption works. These inputs cover Immich recovery,
not full Digital Garden recovery: Kanidm accounts, passkeys and signing state,
and private infrastructure state/inputs need the separate
[recovery plan](recovery.md). OIDC login depends on a working identity service.

Before relying on the backup, restore media and a completed database dump to
an isolated target with matching application/database versions and extensions.
Verify albums, metadata, originals, video playback and OIDC login. Repeat
periodically and after material backup changes. No live backup or restore has
been validated by this concept document.

Sources: [Immich backup and restore](https://docs.immich.app/administration/backup-and-restore/),
[Restic S3 setup](https://restic.readthedocs.io/en/stable/030_preparing_a_new_repo.html),
[Restic retention](https://restic.readthedocs.io/en/stable/060_forget.html).
