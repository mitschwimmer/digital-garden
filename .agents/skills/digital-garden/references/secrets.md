# Prepare fresh identities and runtime secrets

## Secret delivery for a new service

Each consumer has its own `systems/<name>/secrets.yaml` encrypted to the operator
recovery recipient plus that guest's age recipient. Identity and WebUI must never
share a machine key. Edge has no SOPS credentials; Caddy owns its ACME state.
No plaintext belongs in Git, the Nix store, OpenTofu inputs/state or logs.

The old installation's ciphertext/recipients are deliberately removed from the
active tree; history is not a backup of private keys. This is a fresh-install
procedure, not a data/credential migration. Do not combine new keys with old
application databases. Back up anything to retain before an operator host wipe.

## Create and encrypt

Use a secured workstation directory outside the checkout and an existing or newly
created operator recovery key. Set SOPS_AGE_KEY_FILE to that private key. Generate
identity and WebUI age keys separately, refusing to overwrite existing files.
Back them up securely off-host before cleanup. Only public recipients belong in
`.sops.yaml`. Fill its creation_rules before encryption:

```yaml
creation_rules:
  - path_regex: ^systems/identity/secrets\.yaml$
    age: OPERATOR_PUBLIC_RECIPIENT,IDENTITY_PUBLIC_RECIPIENT
  - path_regex: ^systems/open-webui/secrets\.yaml$
    age: OPERATOR_PUBLIC_RECIPIENT,WEBUI_PUBLIC_RECIPIENT
```

Replace all placeholders with actual public age recipients. In fish, establish
an absent/new protected temporary directory (never a shared task directory):

```fish
umask 077
set -l secret_work (mktemp -d)
age-keygen -o "$secret_work/identity.agekey"
age-keygen -o "$secret_work/open-webui.agekey"
openssl rand -hex 32 > "$secret_work/admin"
openssl rand -hex 32 > "$secret_work/idm-admin"
openssl rand -hex 32 > "$secret_work/client"
openssl rand -hex 32 > "$secret_work/webui"
```

Store these outside the checkout; do not print or paste their contents. The same
raw client value is encrypted separately to identity and WebUI, with independent
recipients. Kanidm takes a raw basic secret, not an Authelia password digest.
From the repository root assemble and encrypt without printing plaintext:

```fish
jq -n --rawfile a "$secret_work/admin" --rawfile i "$secret_work/idm-admin" --rawfile c "$secret_work/client" '{admin: ($a|rtrimstr("\n")), "idm-admin": ($i|rtrimstr("\n")), "webui-client": ($c|rtrimstr("\n"))}' > "$secret_work/identity.json"
jq -n --rawfile w "$secret_work/webui" --rawfile c "$secret_work/client" '{environment: ("WEBUI_SECRET_KEY=" + ($w|rtrimstr("\n")) + "\nOAUTH_CLIENT_SECRET=" + ($c|rtrimstr("\n")) + "\n")}' > "$secret_work/webui.json"
sops --encrypt --input-type json --output-type yaml --filename-override systems/identity/secrets.yaml "$secret_work/identity.json" > systems/identity/secrets.yaml
sops --encrypt --input-type json --output-type yaml --filename-override systems/open-webui/secrets.yaml "$secret_work/webui.json" > systems/open-webui/secrets.yaml
```

Require output paths to be absent before encryption. Check every command's exit
status; remove only a failed new output before retrying. Verify operator
decryption to /dev/null. Stage only ciphertext, public recipient policy and
ordinary configuration. Never use temporary plaintext as a flake input.

## Install each machine key

After seed provisioning and readiness, read the target from the selected root.
Verify Incus metadata and `/var/lib/garden-secrets` is a mount point. For identity:

```fish
incus config get YOUR_REMOTE:identity user.garden.system --project identity
incus exec YOUR_REMOTE:identity --project identity -- mountpoint /var/lib/garden-secrets
incus exec YOUR_REMOTE:identity --project identity -- test ! -e /var/lib/garden-secrets/age.key
```

Require identity metadata and both successful checks before a separate transfer:

```fish
incus file push "$secret_work/identity.agekey" YOUR_REMOTE:identity/var/lib/garden-secrets/age.key --project identity --uid 0 --gid 0 --mode 0600
```

For WebUI repeat against YOUR_REMOTE:open-webui in project ai, using only
open-webui.agekey. Stop if a key already exists; restore/reuse its intended
identity instead of overwriting it. Verify consumer decryption during activation.
Back up keys/ciphertext, then remove the protected temporary directory after
successful deployment. Do not rely on secure erase on SSDs.

## Runtime interfaces and rotation

| Consumer | Ciphertext keys | Runtime interface |
|---|---|---|
| Kanidm | admin, idm-admin, webui-client | 0400 files owned by kanidm; native provision options |
| WebUI | environment | Root-only EnvironmentFile consumed by systemd |

ACME keys live only in their owning guest's persistent state. User passkeys,
passwords and Kanidm signing/database identity are application state.
For recipient replacement preserve secret values and run sops updatekeys on only
the affected ciphertext; verify both operator and consumer decryption. For
intentional client rotation change the raw value on both consumers, activate
identity and WebUI, verify allowed/denied login, then retire old material.
Rollback requires matching secrets and application data where coupled.
