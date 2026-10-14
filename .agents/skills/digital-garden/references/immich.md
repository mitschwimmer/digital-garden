# Immich photo and video library

`systems/immich/` owns a NixOS container in project `photos` on measerve.
The native module runs Immich, machine learning, PostgreSQL with VectorChord,
and Redis. OpenTofu owns the guest and protected volumes; there is no nested
Docker runtime. Start with [composition](composition.md) for ownership changes.

The shared stable nixpkgs pin contains unsupported Immich 2.7.5 with known
vulnerabilities. The separate `nixpkgs-immich` input pins
`7fd4004d0511991fff3a0524856a9be09e28c5f0`, providing Immich 3.3.1 and its matching
NixOS module/dependencies only for this guest and seed. Do not permit insecure
packages or downgrade to Immich 2. Keep mobile clients compatible with the server.
Update this input deliberately through [system updates](system-updates.md).
PostgreSQL remains explicitly on major version 16; upgrading it requires its
native migration procedure, not merely changing the package declaration.

- [Placement and storage](#placement-and-storage)
- [Credentials and first deployment](#credentials-and-first-deployment)
- [Identity and acceptance](#identity-and-acceptance)
- [Backup, restore and rollback](#backup-restore-and-rollback)

## Placement and storage

| Volume / component | Existing pool | Guest path |
|---|---|---|
| Disposable root, application and machine-learning cache | `local` | `/`, `/var/cache/immich` |
| `garden-immich-state` (all media, thumbnails, transcodes and database dumps) | `data` | `/var/lib/immich` |
| `garden-immich-database` | `local` | `/var/lib/postgresql` (database in `16/`) |
| `garden-immich-secrets` | `local` | `/var/lib/garden-secrets` |

The root is limited to 24 GiB, with 4 CPU cores and 8 GiB RAM. Monitor root/cache
and both persistent pools independently. Redis queues and ML cache are disposable;
after root replacement inspect/requeue incomplete processing jobs. All original
media and application metadata remain on protected volumes. Start with CPU
processing; no GPU devices are assigned. A later acceleration change needs its
own device/access and actual-offload checks.

Inspect measerve and both existing pools using [platform inputs](platform.md).
This root defaults `storage_pool = "local"`, `media_storage_pool = "data"`; keep
its authenticated `incus_remote` and immutable `image_directory` in its own ignored
`site.auto.tfvars.json`. Do not create or adopt host pools into managed lifecycle.
Provision the new `photos` project in `platform/` before reconciling this leaf.
Use [seeds](nixos-guests.md), [infrastructure](infrastructure.md) and
[readiness](readiness.md). Mount checks in `target.json` and service units must
pass before application state is written. Immich uses guest UID/GID 990; Postgres
retains the native module's stable UID/GID. Incus maps these into the unprivileged
container. Do not chown host
volumes to those raw IDs. Systemd creates/owns state directories inside the guest.

## Credentials and first deployment

Use [secret delivery](secrets.md) from a private operator terminal and secured
workstation directory outside the checkout. Reuse identity's existing machine
key and recovery recipient. Create a distinct Immich age key; never copy another
guest's key. Add a real creation rule for `^systems/immich/secrets\.yaml$` with
the recovery recipient and new Immich public recipient to `.sops.yaml`.
The existing identity rule also covers `systems/identity/immich-secrets.yaml`.

Generate one new raw OAuth client secret. Encrypt `{ "immich-client": VALUE }`
separately to `systems/identity/immich-secrets.yaml` and
`systems/immich/secrets.yaml`, with each consumer's recipients. Use the encryption
workflow's `--filename-override` and JSON input/output YAML, refusing existing
output paths. No plaintext or placeholder ciphertext belongs in the checkout.
Verify operator decryption to `/dev/null` and stage the real ciphertext/policy.
Install only Immich's new key into its verified `/var/lib/garden-secrets` mount,
following the guarded key-transfer workflow with instance `immich`, project
`photos`. Preserve identity/WebUI credentials and their encrypted inputs.

Until identity's additional ciphertext exists, its new client is not provisioned;
existing identity/WebUI builds continue to work. Absence never removes a previously
provisioned client (`autoRemove = false`). Immich's full closure refuses to build
without both encrypted files. Seeds and module-option evaluation need no secrets.
Once prepared, build the affected identity and Immich closures, verify consumer
decryption and deploy identity first, then Immich through [deployment](deployment.md).

Immich requires first-admin registration even when password login is disabled.
Bootstrap Henner's declared email (`henner@archaic.work`) through private Incus
exec before normal browser login. In the secured secret working directory,
assemble a private `bootstrap.json` containing `name`, `email`, and a new random
`password`; do not put it in Git or arguments. From the workstation:

```fish
incus exec YOUR_REMOTE:immich --project photos -T -- curl --fail --silent --show-error --output /dev/null --header 'Content-Type: application/json' --data-binary @- http://127.0.0.1:2283/api/auth/admin-sign-up < "$secret_work/bootstrap.json"
```

Check success before proceeding and remove the temporary payload after secure
recovery handling. This is one-time setup on an empty database, never a recovery
step for an existing library. Caddy rejects the public first-admin endpoint;
password login remains disabled. Immich links the initial account by matching
the trusted Kanidm email at first OIDC login. Verify that link and admin role.

Deploy edge's route and configure `photos.archaic.work` DNS to the existing edge
ingress. Use [ingress](ingress.md) for IPv4/IPv6 and certificate policy. Only edge
publishes HTTPS; backend port 2283 is open only on the trusted private bridge.
PostgreSQL and Redis use Unix sockets, ML listens on guest localhost.

## Identity and acceptance

Client `immich` discovers Kanidm at
`https://auth.archaic.work/oauth2/openid/immich/.well-known/openid-configuration`.
It uses `client_secret_basic`, S256 PKCE, ES256 signing and scopes
`openid profile email`. Keep PKCE and verified TLS enabled; no legacy crypto.
Exact callbacks are `/auth/login`, `/user-settings`, and
`/api/oauth/mobile-redirect` under `https://photos.archaic.work`.
The HTTPS mobile override forwards to Immich's app scheme without registering
a non-HTTPS origin in Kanidm.

`directory.nix` declares `photos-users` initially containing Henner and Claudi.
Only that group and `admins` receive login scopes. The `immich_role` array grants
`user` to `photos-users`, `admin` to `admins`; Immich gives admin precedence.
Use [users](users.md) for membership changes. Group removal blocks fresh OIDC
authorization but does not revoke existing Immich sessions or API keys; revoke
those through Immich and test previously authenticated clients too.

Require active `postgresql`, `redis-immich`, `immich-server` and
`immich-machine-learning` units, all three mounts, and no failed units. Verify:

```fish
incus exec YOUR_REMOTE:immich --project photos -- curl --fail --max-time 30 http://127.0.0.1:2283/api/server/ping
curl --fail --max-time 30 -4 https://photos.archaic.work/api/server/ping
```

Test IPv6 too if AAAA is published. Require trusted TLS. Verify public first-admin
registration returns 403. Test Henner as admin, Claudi as user and an enrolled
person outside both groups as denied; verify password login is unavailable.
Test browser/mobile callbacks, logout/reauthentication, a real photo and video
upload, thumbnails, playback and ML processing. Restart the guest and repeat
login/media checks, confirming mounts and persistence. These are deployment
acceptance steps; source CI does not prove them.

For failures inspect the owning unit's journal, pool space, mount ownership,
database/extension readiness, OIDC discovery/claim maps and Caddy routing.

## Backup, restore and rollback

Immich's daily database dumps under `/var/lib/immich/backups` contain metadata,
not photos. Neither those dumps nor protected Incus volumes are off-host backups.
Use [recovery](recovery.md) for state, source, ciphertext and matching keys.
For a consistent checkpoint stop the whole `immich` instance, snapshot/export
`garden-immich-state` from `data`, and `garden-immich-database` plus
`garden-immich-secrets` from `local`, all in project `photos`. Check every command
before restarting. Export to encrypted off-host storage and retain the exact
revision, database major version and both consumer ciphertexts.

Restore all three volumes together on an isolated target using the matching
source/keys. Reconcile surviving resources into the owning state, verify mounts,
deploy the matching closure and test actual albums, originals, video playback,
metadata and login. ML cache can be rebuilt. Recreating a volume is not restoration.

Before an upgrade, take a consistent checkpoint and review migrations. A closure
rollback alone cannot reverse database changes. For incompatible migrations,
mask `immich-server` and `immich-machine-learning`, select and verify the recorded
old generation using the guarded rollback workflow, then stop the guest and
restore its matching media/database checkpoint before restarting. Follow the
[WebUI rollback example](recovery.md#webui-checkpoint-and-data-rollback-example)
with Immich's actual units, pools and volumes; do not reuse another root's records.
Validate restoration before reopening traffic.

Sources: [pinned NixOS module](https://github.com/NixOS/nixpkgs/blob/7fd4004d0511991fff3a0524856a9be09e28c5f0/nixos/modules/services/web-apps/immich.nix),
[Immich requirements](https://docs.immich.app/install/requirements/),
[OIDC](https://github.com/immich-app/immich/blob/v3.3.1/docs/docs/administration/oauth.md),
[backup and restore](https://docs.immich.app/administration/backup-and-restore/).
