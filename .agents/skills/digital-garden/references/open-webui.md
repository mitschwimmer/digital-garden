# Retire Open WebUI

Open WebUI is withdrawn from the declared application fleet. Its NixOS
configuration, seed output, deployment target and edge route are removed.
Identity retains an explicit `present = false` OAuth client tombstone because
`autoRemove = false` does not delete omitted clients. Walter, inference, the
shared `ai` project and `ai-users` group remain in use.

`systems/open-webui` is now a retirement root. Its existing provider lock,
resource addresses and protected volumes remain so a reviewed whole plan can
remove the old instance and seed image without abandoning data ownership.
This is an existing-installation procedure; do not apply empty state over
surviving resources or provision this root for a fresh installation.

## Preserve recovery material

Before live removal, inspect this root's local inputs, applied state and actual
remote/pool/volume inventory. Follow [recovery](recovery.md#backup) and save the
root's state, local inputs, provider lock, previous Git revision, deployment
records and retained seed/closure recovery paths privately off-host.

Stop the instance and checkpoint both `garden-open-webui-state` and
`garden-open-webui-secrets` in project `ai`. Use new snapshot names and absent
export paths. The database and matching `WEBUI_SECRET_KEY` form one recovery
set; preserve the machine age key, `systems/open-webui/secrets.yaml` and the
matching identity client ciphertext with it. The secrets volume contains a
private key: encrypt/protect off-host exports and verify them independently.
Keep the instance stopped after the checkpoint.

Ciphertext and its SOPS creation rule remain for recovery. Identity no longer
materializes `webui-client`; its unused encrypted entry stays in the shared
identity file so administrator ciphertext and the SOPS MAC remain untouched.
Remove that entry later with SOPS and the authorized key, preserving the
administrator values; do not edit encrypted YAML fields directly.

## Withdraw access and remove the guest

From the updated checkout, enter `nix develop`.

1. Deploy `systems/edge` with `python ../../operations/activate.py deploy` from
   that root. Verify `ai.archaic.work` no longer routes to Open WebUI and the
   surviving public applications still work. Remove the obsolete DNS record
   through its external owner after checking it has no other purpose.
2. Deploy `systems/identity` with the same command from its own root. Require
   successful provisioning of the `open-webui` tombstone and verify the client
   is absent. Test Walter and Immich login; retain their clients, groups and
   credentials. New WebUI login must no longer be possible.
3. Enter `systems/open-webui` with its existing state and local inputs. Archive
   and remove the obsolete `image_directory` input; no new seed is required.
   Run the [whole plan/apply procedure](infrastructure.md#review-and-apply-the-whole-plan).
   Expect deletion of only `incus_instance.webui` and `incus_image.seed`, plus
   removal of the old deployment outputs. Require **no deletion, replacement or
   modification of either retained volume**. Stop if the plan differs.
4. Verify the guest is absent, both protected volumes remain in their original
   project/pool, and a fresh plan has no changes. Record the retired revision,
   retained volume identities and private checkpoint location.

Do not use `tofu destroy`, remove state records, or change `prevent_destroy` to
complete this retirement. The application root disk is deleted with the guest;
finish the recovery checkpoint before applying. No platform or inference apply
is needed for this service removal.

## Retained data

Keep this root, its protected-volume declarations, ciphertext and identity
tombstone through their retention period. Permanent volume/key/archive deletion
requires a separate retention decision and reviewed change. Until then, restore
only from the archived compatible revision and matching recovery set on an
isolated target, following [recovery](recovery.md#restore). Reopening public
access requires a separate reviewed service configuration.
