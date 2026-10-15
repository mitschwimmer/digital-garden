# Operate Open WebUI

- [Service and acceptance](#service-and-acceptance)
- [OIDC contract](#oidc-contract)
- [Secret contract](#secret-contract)
- [Checkpoint and data rollback example](#checkpoint-and-data-rollback-example)

## Service and acceptance

`systems/open-webui/` owns the NixOS application, ai/open-webui instance, seed,
state and machine key. It uses the [pinned package backport](../../../../nix/packages/README.md).
It depends on Kanidm for native OIDC, edge for public HTTPS and the private
inference endpoint for chat. Configuration comes from Nix on every startup;
ENABLE_PERSISTENT_CONFIG is false. No local password login or proxy-header auth.

For initial creation, provision this root and prepare its [secrets](secrets.md).
For configuration rollout, run
[deployment](deployment.md) from systems/open-webui. Identity must have the matching
client secret and directory declarations. Check `/var/lib/open-webui` and
`/var/lib/garden-secrets` are real mounts before deploying. UID/GID 990 belongs
to the application; root reads the 0400 environment file through systemd.

The OIDC webui_roles claim maps ai-users to user and admins to admin; unmatched users
remain pending/denied. The issuer scope map denies unrelated users. Upstream
first/sole-user admin promotion still exists: the operator must log in first
with the intended admins account, then verify ordinary-user and denied-user
behavior. Do not let an ordinary user initialize an empty database.

```fish
incus exec YOUR_REMOTE:open-webui --project ai -- systemctl is-active open-webui
incus exec YOUR_REMOTE:open-webui --project ai -- curl --fail --connect-timeout 5 --max-time 30 http://127.0.0.1:8080/health
```

Require browser login via https://ai.archaic.work, correct user/admin roles,
denial of a person without allowed membership, and successful generated chat.
Test missing/unrelated role claims as well as successful authentication.
Check inference from this actual caller, then restart and verify login, chat data
and secret-key persistence. Configuration/API catalog success alone is not chat.

On failure inspect WebUI journal, discovery/JWKS TLS, callback, scope/claim mapping,
matching client secrets and inference reachability. Never re-enable local login
or disable TLS to bypass an OIDC failure. Roll back configuration with matching
application data when a schema migration occurred.

## OIDC contract

WebUI uses client open-webui, callback https://ai.archaic.work/oauth/oidc/callback,
PKCE S256, client_secret_basic and discovery at
https://auth.archaic.work/oauth2/openid/open-webui/.well-known/openid-configuration.
The scope map grants openid/profile/email only to ai-users/admins. The custom
webui_roles claim returns those names as an array; WebUI reads that claim for
role management. Do not request the built-in groups scope: Kanidm fills groups
with UUIDs and SPNs, overwriting a custom claim of the same name. Applications
never infer permissions merely from a successful login. Keep TLS verification
and PKCE enabled.

For coordinated claim changes, deploy identity first, then WebUI using
[deployment](deployment.md), and test fresh login after both deployments.
Kanidm's consent screen lists selected personal-information fields, not every
scope or custom claim; an email-only prompt does not prove roles are missing.

## Secret contract

Encrypt `environment` in `systems/open-webui/secrets.yaml` as an EnvironmentFile
with `WEBUI_SECRET_KEY` and `OAUTH_CLIENT_SECRET`, each followed by a newline.
Generate independent random values; the raw OAuth client value must also be
encrypted as `webui-client` for identity. Preserve `WEBUI_SECRET_KEY` with its
database during backup/restore. Root reads the runtime file through systemd.
Use [shared secret delivery](secrets.md); bootstrap identity before WebUI login.

## Checkpoint and data rollback example

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
runtime state so older code cannot open the newer database during deployment:

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
