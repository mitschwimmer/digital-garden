# Protect identities and deliver encrypted inputs

- [Scope and inputs](#scope-and-inputs)
- [Secret delivery for a new service](#secret-delivery-for-a-new-service)
- [Reuse encrypted identities](#reuse-encrypted-identities)
- [Machine identities for a fresh host](#machine-identities-for-a-fresh-host)
- [Intentionally create all-new identities](#intentionally-create-all-new-identities)
- [Check the result consumer interfaces and rotation](#check-the-result-consumer-interfaces-and-rotation)
- [Resume and rollback](#resume-and-rollback)

## Scope and inputs

Preserve stable secret values and recoverable identities. Use the fish
workstation, `.sops.yaml`, consumer ciphertext and persistent machine-key mounts;
select recovery, recipient replacement or deliberate initialization before
executing any key or secret generation.

Keep stable managed secrets as SOPS + age ciphertext in Git. Public recipient
policy belongs in `.sops.yaml`; operator and machine private keys stay outside
Git and on securely backed-up persistent storage. Never put plaintext secrets
in the Nix store, OpenTofu inputs/state, normal logs or documentation.

The procedures below run on the fish workstation before activating a secret-consuming service. Existing
ciphertext is kept in this repository. A rebuild restores its operator key and
machine keys or updates recipients while preserving secret values. Losing all
recipient private keys makes existing ciphertext unrecoverable. Restore matching
application data when stable encryption keys and databases are coupled.

## Secret delivery for a new service

Organize encrypted files by consumer and lifecycle. Retain an operator recovery
recipient and add the consuming guest's public recipient to `.sops.yaml`.

For NixOS, use sops-nix runtime files with narrow owner/group/mode settings. Feed
services secret-file paths, systemd credentials or an environment file, rather
than interpolating plaintext into Nix expressions. Keep the consumer's machine
age key on a persistent secret volume across guest replacement. The edge and
WebUI Nix configurations are examples of secret-file and environment-file wiring.

For OCI, prefer application-supported secret files mounted read-only. If delivery
requires a runtime transfer, specify a protected volume, narrow permissions and
readiness/restart behavior; keep plaintext out of provider attributes and state.
Choose a NixOS guest when environment-only or numerous secrets would otherwise
require bespoke secret infrastructure. Public OCI config-file delivery described
in [OCI configuration](oci-configuration.md) must not be used for secret plaintext.

Treat rotation as an explicit change: generate material privately, re-encrypt,
update both integration endpoints, deploy, verify authentication and revoke
superseded credentials when supported. Understand session/data consequences
before rotating storage or signing keys. Recipient replacement during recovery
preserves the encrypted values; it is not secret rotation.

## Reuse encrypted identities

Restore the existing operator key to `SOPS_AGE_KEY_FILE` outside the checkout with
mode 0600. Restore backed-up machine keys to the persistent secret volumes. If
machine keys were lost but operator access survives, generate replacements using
the next section, edit `.sops.yaml` to retain the operator recipient and replace
only each consumer's machine recipient, then run:

```fish
sops updatekeys secrets/edge.yaml
sops updatekeys secrets/edge-oidc.yaml
sops updatekeys secrets/open-webui.yaml
sops --decrypt secrets/edge.yaml > /dev/null
sops --decrypt secrets/edge-oidc.yaml > /dev/null
sops --decrypt secrets/open-webui.yaml > /dev/null
```

Each consumer must independently decrypt after deployment; operator decryption
alone is insufficient. Recipient changes preserve storage/session/signing/client
values. Restore matching application databases when recovering encrypted state.
Do not casually edit stable cryptographic fields with SOPS.

## Machine identities for a fresh host

Use a protected directory outside the checkout; never reuse an existing key path
as an initialization target. The key generator refuses to overwrite existing keys.
For a full fresh installation create an operator recovery key only if none exists:

```fish
umask 077
mkdir -p "$HOME/.config/digital-garden"
chmod 0700 "$HOME/.config/digital-garden"
# Only on first creation; otherwise restore/reuse the existing key.
age-keygen -o "$SOPS_AGE_KEY_FILE"
```

Generate machine keys locally only when creating or replacing the consumer identity. WebUI need not
exist yet; its key is securely retained locally until the consuming guest exists:

```fish
set -gx GARDEN_SECRET_WORK (mktemp -d)
age-keygen -o "$GARDEN_SECRET_WORK/edge.agekey"
age-keygen -o "$GARDEN_SECRET_WORK/webui.agekey"
age-keygen -y "$SOPS_AGE_KEY_FILE"
age-keygen -y "$GARDEN_SECRET_WORK/edge.agekey"
age-keygen -y "$GARDEN_SECRET_WORK/webui.agekey"
```

Only public recipients print. Update `.sops.yaml`: `edge.yaml` and `edge-oidc.yaml`
use operator + edge; `open-webui.yaml` uses operator + WebUI. For existing
ciphertext run the `updatekeys` commands above before deployment. Back up the
machine keys securely outside this temp directory before it is removed.

Install edge's key only after confirming the persistent mount and that the
runtime key path is absent. For an existing key, restore/reuse it instead:

```fish
incus exec "$GARDEN_REMOTE:edge" --project default -- mountpoint /var/lib/garden-secrets
incus exec "$GARDEN_REMOTE:edge" --project default -- test ! -e /var/lib/garden-secrets/age.key
```

Require mount-check and absence-test exit 0 before this separate transfer. If
there is already a key, verify/reuse the intended identity and skip this command:

```fish
incus file push "$GARDEN_SECRET_WORK/edge.agekey" "$GARDEN_REMOTE:edge/var/lib/garden-secrets/age.key" --project default --uid 0 --gid 0 --mode 0600
```

Stop on a failed check; these are separate guarded operator steps. Native file
transfer does not carry keys through OpenTofu or the Nix store. The analogous
WebUI key delivery is documented in [its service reference](open-webui.md). Keep operator and machine-key backups apart
from the host, with protected/encrypted backup access.

## Intentionally create all-new identities

This path is for an empty application installation only. First save existing
ciphertext, `.sops.yaml`, keys and matching application data to secure backups.
Move the three existing consumer ciphertext files out of the checkout, preserving
them in the backup. Do not overwrite recoverable secrets or use new encryption
keys with an old Authelia database. Keep `.sops.yaml` with the new public recipients.
If recovery is intended, use the reuse path instead.

In `GARDEN_SECRET_WORK`, copy the two **placeholder** examples, then edit them
with your local editor (no cloud/editor backup/swap files). All placeholders
must be replaced. The user file contains an Argon2id password digest and an
`admins` group; SMTP uses your real submission endpoint and app password.

```fish
cp secrets/examples/users.json "$GARDEN_SECRET_WORK/users.json"
cp secrets/examples/smtp.json "$GARDEN_SECRET_WORK/smtp.json"
authelia crypto hash generate argon2 > "$GARDEN_SECRET_WORK/password-hash.txt"
```

The interactive prompt accepts the human password without command-line history.
Copy just the resulting digest into the protected users file using the editor.
Generate stable keys and a client secret into protected files, not terminal output:

```fish
openssl rand -hex 32 > "$GARDEN_SECRET_WORK/jwt"
openssl rand -hex 32 > "$GARDEN_SECRET_WORK/session"
openssl rand -hex 32 > "$GARDEN_SECRET_WORK/storage"
openssl rand -hex 32 > "$GARDEN_SECRET_WORK/hmac"
openssl rand -hex 32 > "$GARDEN_SECRET_WORK/client"
openssl rand -hex 32 > "$GARDEN_SECRET_WORK/webui"
openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:3072 -out "$GARDEN_SECRET_WORK/signing.pem"
authelia crypto hash generate argon2 > "$GARDEN_SECRET_WORK/client-hash.txt"
```

For the second interactive hash prompt, use the exact hex client value from the
protected `client` file. Store only the `Digest: ` value, without that prefix,
in a new protected `client.digest` file via the editor. The plaintext client goes
to WebUI; Authelia uses this corresponding hash. Do not paste either into chat.

Use native `jq` to assemble consumer documents. Users and SMTP are string values
holding their complete JSON files (JSON is valid YAML for Authelia):

```fish
jq -n --rawfile jwt "$GARDEN_SECRET_WORK/jwt" --rawfile session "$GARDEN_SECRET_WORK/session" --rawfile storage "$GARDEN_SECRET_WORK/storage" --rawfile users "$GARDEN_SECRET_WORK/users.json" --rawfile smtp "$GARDEN_SECRET_WORK/smtp.json" '{jwt: ($jwt | rtrimstr("\n")), session: ($session | rtrimstr("\n")), storage: ($storage | rtrimstr("\n")), users: $users, smtp: $smtp}' > "$GARDEN_SECRET_WORK/edge.json"
jq -n --rawfile hmac "$GARDEN_SECRET_WORK/hmac" --rawfile signing "$GARDEN_SECRET_WORK/signing.pem" --rawfile client "$GARDEN_SECRET_WORK/client.digest" '{hmac: ($hmac | rtrimstr("\n")), signing: $signing, client: ($client | rtrimstr("\n"))}' > "$GARDEN_SECRET_WORK/edge-oidc.json"
jq -n --rawfile webui "$GARDEN_SECRET_WORK/webui" --rawfile client "$GARDEN_SECRET_WORK/client" '{environment: ("WEBUI_SECRET_KEY=" + ($webui | rtrimstr("\n")) + "\nOAUTH_CLIENT_SECRET=" + ($client | rtrimstr("\n")) + "\n")}' > "$GARDEN_SECRET_WORK/open-webui.json"
sops --encrypt --input-type json --output-type yaml --filename-override secrets/edge.yaml "$GARDEN_SECRET_WORK/edge.json" > secrets/edge.yaml
sops --encrypt --input-type json --output-type yaml --filename-override secrets/edge-oidc.yaml "$GARDEN_SECRET_WORK/edge-oidc.json" > secrets/edge-oidc.yaml
sops --encrypt --input-type json --output-type yaml --filename-override secrets/open-webui.yaml "$GARDEN_SECRET_WORK/open-webui.json" > secrets/open-webui.yaml
```

Only run the last three commands when the output paths are absent. Check each
exit status before continuing; on encryption failure remove only the incomplete
new output and retry. Verify operator decryption to `/dev/null`. Stage only the
three ciphertext files and public `.sops.yaml`, then build the consumers. Restore
backups of machine keys before deleting this temporary directory. Remove it after
successful deployment and separately verified backups; do not rely on secure erase
on SSDs. Plaintext temp files are never committed or used as flake inputs.

## Check the result consumer interfaces and rotation

| Consumer | Encrypted source | Runtime interface |
|---|---|---|
| Authelia | `edge.yaml`: jwt, session, storage, users, smtp | Narrow 0400 files owned by authelia-main |
| Authelia OIDC | `edge-oidc.yaml`: hmac, signing, client hash | Module secret-file options and templated client file |
| WebUI | `open-webui.yaml`: environment | Root-only environment file read by systemd |

OIDC URLs/scopes/client ID live in ordinary Nix; no credential belongs in HCL.
The signing key uses the module's native JWKS template. For intentional rotations,
edit ciphertext with SOPS, coordinate both sides of the client integration,
activate both guests, verify login/denial, then revoke obsolete credentials.
Storage/signing-key rotation needs application-specific consequences reviewed.

## Resume and rollback

On a failed recipient update or transfer, retain the original ciphertext and
keys, repair the failed step and repeat private decryption before activation.
For intentional rotation, restore the matching previous credentials and
application data when required; follow [recovery](recovery.md). Never regenerate
storage encryption or signing material as a service retry.

Sources: [Authelia secure values](https://www.authelia.com/reference/guides/generating-secure-values/),
[pinned NixOS Authelia module](https://github.com/NixOS/nixpkgs/blob/0d9e9b832d03ac387417e16ce1febf73b2e631e1/nixos/modules/services/security/authelia.nix).
