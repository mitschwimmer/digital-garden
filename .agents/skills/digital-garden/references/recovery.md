# Back up and recover each operation root

Preserve the source revision, each root's state/local inputs/provider lock, seed
archive and GC root, deployment records, SOPS policy/ciphertext, operator and
machine age keys, and application state. Backups must survive loss of IncusOS;
prevent_destroy and on-host Kanidm online backups are not off-host recovery.
Keep credentials private and encrypt backup storage. Never print plaintext.

Quiesce the affected service for a consistent application-volume snapshot/export,
or use its native online backup mechanism and verify it independently. Keep
Kanidm data/signing identity, WebUI data/WEBUI_SECRET_KEY, and machine keys with
their matching ciphertext. Caddy and identity ACME state have distinct owners.
Record the exact volume/project and revision in the checkpoint.

On recovery inspect survivors first. Restore matching root state when available;
otherwise use the pinned provider's supported imports for surviving resources.
Do not apply empty state over live resources. Incus image imports need special
care: the pinned image resource has no importer, so review an explicit image
recreation plan using the retained seed archive rather than inventing an import.
Do not regenerate application secrets to repair missing recipient keys.

Restore platform before dependent roots. Restore each guest's own volumes and
machine key, then activate its declared configuration using the identity guard.
Bring up edge before identity's certificate issuance; bring up identity before
WebUI login acceptance. Verify actual restored data, allowed/denied login,
trusted TLS and restart persistence on an isolated recovery target. An archive
listing alone is not restoration evidence.

For NixOS rollback use [activation](activation.md); database migrations may need
matching data restoration. For OCI rollback restore the pinned declaration and
review a new plan. Reconcile source against accepted running state afterward.

## WebUI checkpoint and data rollback example

In systems/open-webui read the applied remote and pool from its local inputs;
replace YOUR_REMOTE and YOUR_POOL below with those inspected values. Choose an
unused snapshot name and an absent export path in a secured off-host directory.
Stop the instance so neither its database nor machine key changes during backup:

```fish
incus stop YOUR_REMOTE:open-webui --project ai
incus storage volume snapshot create YOUR_REMOTE:YOUR_POOL garden-open-webui-state before-update --project ai
incus storage volume snapshot create YOUR_REMOTE:YOUR_POOL garden-open-webui-secrets before-update --project ai
incus storage volume export YOUR_REMOTE:YOUR_POOL garden-open-webui-state /SECURE/CHECKPOINT/webui-state.tar.gz --project ai
incus storage volume export YOUR_REMOTE:YOUR_POOL garden-open-webui-secrets /SECURE/CHECKPOINT/webui-secrets.tar.gz --project ai
incus start YOUR_REMOTE:open-webui --project ai
```

Check every exit status. Encrypt/protect exports: the secrets volume contains a
private key. Save root state, inputs, ciphertext and revision alongside them.
Snapshots remain on-host; exports must be independently recoverable off-host.
For other systems use their actual volume names and project, never WebUI's.

If an incompatible upgrade requires data rollback, first stop WebUI and mask it in
runtime state so older code cannot open the newer database during activation:

```fish
incus exec YOUR_REMOTE:open-webui --project ai -- systemctl stop open-webui
incus exec YOUR_REMOTE:open-webui --project ai -- systemctl mask --runtime open-webui
python ../../operations/activate.py rollback .operations/FAILED-ATTEMPT/deployment.json
```

The guarded rollback must select the old profile, but will fail service acceptance
because the service is masked. Verify the profile matches that record's previous
closure before continuing. Then stop the instance, restore the matching snapshot,
and start the old generation; reboot clears the runtime mask:

```fish
incus stop YOUR_REMOTE:open-webui --project ai
incus storage volume snapshot restore YOUR_REMOTE:YOUR_POOL garden-open-webui-state before-update --project ai
incus start YOUR_REMOTE:open-webui --project ai
```

Before the final start, verify rollback actually selected the old generation;
if profile selection failed, stop and repair it rather than starting newer code
against restored data. Restore secret state/ciphertext only when that checkpoint
requires it; never rotate WEBUI_SECRET_KEY while restoring its database.
Repeat readiness, authentication and actual data checks before reopening traffic.
An offline restore of an export uses `incus storage volume import` into an absent
volume on an isolated recovery target; reconcile/import it into that root's state
before attaching a guest. Never overwrite a surviving volume blindly.

Source: [Incus custom-volume backup](https://linuxcontainers.org/incus/docs/main/howto/storage_backup_volume/).
