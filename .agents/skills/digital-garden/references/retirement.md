# Retire a service deliberately

Use this workflow to withdraw a service while preserving its dependents, shared
building blocks and data according to an explicit retention decision. Require
current inventory, matching state, tested backups where data must survive, and
an agreed list of resources to remove. A retirement is an intentional lifecycle
change; disabling a service is not a failure-recovery shortcut.

## Identify ownership and dependencies

List the service's project/guest, hostname/routes, OIDC clients, dedicated
credentials, encrypted consumer files, recipients, persistent volumes and
backups. Inspect actual HCL, guest configuration and callers. Identify shared
edge, network, identity, signing keys and credentials that must remain.

| Retiring | Shared or dependent pieces to preserve/reconfigure |
|---|---|
| WebUI | Keep edge, private bridge, Authelia and inference; remove only its Caddy route and OIDC client, and dedicated client credentials |
| Inference | Keep WebUI and edge; configure a replacement backend or explicitly accept unavailable chat inference before removing the guest |
| A future service | Inspect its callers, workers, database, routes and identity interfaces rather than copying the AI service's deletion list |

## Withdraw access and preserve data

1. Choose a maintenance window and inform authorized callers through the user's
   usual process. Remove the service's public Caddy route and disable/revoke its
   OIDC client or other entry points. Build and activate the complete shared
   edge role; verify unrelated public routes and identity still work.
2. Stop the service for a consistent final backup where required. Use
   [native backups](recovery.md), including matching identities, application
   data, source revision and inputs. Verify the intended restore/archive before
   destructive deletion. A recoverable retirement may retain encrypted dedicated
   secrets with tightly controlled archive access.
3. Revoke dedicated external credentials and tokens at their owning service.
   Remove dedicated runtime secrets from the retired consumer. Remove obsolete
   recipients and consumer ciphertext only when retention/recovery no longer
   needs them. Recipient removal alone does not revoke already-decrypted secrets.
   Never rotate shared signing/storage keys merely to remove a client.

For current WebUI, `edge-auth.nix` constructs a single-client template and its
validator, and both edge/WebUI configurations consume dedicated ciphertext.
Update the client list, template generation, sops declarations, validators and
assertions coherently before deleting `edge-oidc.yaml` or `open-webui.yaml`.
Shared HMAC/signing material must remain when other clients use it. Changing only
the guest boolean does not remove its routes, OIDC client or source configuration.

## Remove the disposable guest

Edit the ignored local selection for the intended guest only:

```fish
jq '.enable_webui = false' tofu/site.auto.tfvars.json > tofu/site.auto.tfvars.json.tmp
```

For inference, use `.enable_inference = false` instead. Check jq success before
moving the file into place:

```fish
mv tofu/site.auto.tfvars.json.tmp tofu/site.auto.tfvars.json
```

Then run [whole-plan review](infrastructure.md#review-and-apply-the-whole-plan).
For a guest-only retirement, require deletion of only `incus_instance.webui[0]`
or `incus_instance.llama[0]`, with all existing volumes, projects, seed imports,
network and unrelated guests retained. Stop for any extra deletion/replacement.
Apply only the reviewed saved plan.

Both application projects and their protected volumes exist independently of
guest enablement. Keep them for later restoration or reactivation. Permanent
volume/project cleanup is a separate source/configuration change with its own
exact deletion list and confirmed retention decision. `prevent_destroy` blocks
deletions while configured, but removing a resource block removes that protection.
Do not forget state records to make a destructive plan appear harmless.

## Verify and record the result

Check that withdrawn endpoints and credentials no longer grant access. Confirm
the retired guest is absent, retained volumes still exist in the correct project,
and unaffected guests, routes and identity still work. Verify reconfigured
callers and the archive's recovery access. Record the retired revision/date,
removed resource identities and retention location/policy privately.

For reactivation, review a new enablement plan, restore or reuse matching state,
keys and data, restore the deliberately retained routes/client configuration,
activate the intended guest role and verify access/persistence. Recreating a guest
does not undo credential revocation or recover deleted application data.
