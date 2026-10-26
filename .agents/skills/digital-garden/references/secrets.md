# Deliver and preserve runtime secrets

- [Secret contract](#secret-delivery-for-a-new-service)
- [Create and encrypt](#create-and-encrypt)
- [Install each machine key](#install-each-machine-key)
- [Rotation and recovery](#rotation-and-recovery)

## Secret delivery for a new service

Inspect the consuming NixOS module and owning service reference for ciphertext
paths/keys, required recipient sets and runtime interface (credential file,
EnvironmentFile or supported application input). Each secret-consuming guest has
its own machine age key. Encrypt to the operator recovery recipient plus only
the intended consuming guest; never share a machine private key. Shared raw
integration values are encrypted separately for each consumer's recipients.
Additional client ciphertext must not replace existing admin/client credentials.

Declare narrow runtime ownership/modes and required persistent mounts. Never put
plaintext in Git, the Nix store, OpenTofu inputs/state, process arguments or logs.
Public OCI file delivery may enter state and cannot deliver secrets. For a single
supported secret file, the owning service may declare a protected volume and
native Incus transfer from operator-decrypted SOPS input, with startup disabled
until delivery. Keep bytes outside provider attributes and verify guest-mapped
ownership. Use NixOS/sops-nix for automatic or complex secret delivery. ACME keys
remain application state of the certificate-owning guest.

## Create and encrypt

Use a private operator terminal and secured workstation directory outside the
checkout. Set `SOPS_AGE_KEY_FILE` to the intended operator recovery key. For a new
guest only, generate a distinct age key into an absent protected path, back it up
off-host, and put only its public recipient in the appropriate `.sops.yaml` rule.
Inspect the rule's exact path regex and recipient set before encrypting.

Begin a new private workspace:

```bash
umask 077
secret_work="$(mktemp -d)"
age-keygen -o "$secret_work/consumer.agekey"
```

Generate independent random values using native tools into protected files.
Assemble the service's exact JSON/YAML schema there using file input, not secret
values in arguments. Match runtime quoting/newline requirements. For an OIDC
basic client, both consumers need the same raw secret, not a password digest.

From the repository root, encrypt the protected input using its real destination
path for creation-rule selection (replace INPUT_JSON and CIPHERTEXT_PATH):

```bash
sops --encrypt --input-type json --output-type yaml --filename-override CIPHERTEXT_PATH INPUT_JSON > CIPHERTEXT_PATH
```

Require the destination to be absent before this creation command. Check every
exit status; remove only a failed new output before retrying. Verify operator
decryption to `/dev/null`. Stage only ciphertext, real public recipients and
ordinary config; no fabricated ciphertext or temporary plaintext flake inputs.
For existing guests reuse their intended machine keys; creation is not rotation
or recovery. Do not combine newly generated application secrets with old databases.

## Install each machine key

After provisioning the seed and checking readiness, inspect this root's
`target.json` and applied deployment output for remote/project/instance. Verify
`user.garden.system` matches the target, `/var/lib/garden-secrets` is a real
persistent mount, and `/var/lib/garden-secrets/age.key` does not already exist.
Check each result before transferring the intended guest's key separately using
`incus file push` with uid/gid 0 and mode 0600. Never infer the destination from a
previous task or another root's shell variables.

If a key exists, stop and reuse/restore its intended identity rather than
overwriting it. Verify consumer decryption during deployment. Preserve matching
keys/ciphertext securely off-host, then remove only this operation's protected
temporary workspace after acceptance. Do not rely on secure erase on SSDs.

## Rotation and recovery

For recipient replacement preserve secret values and run `sops updatekeys` on
only affected ciphertext. Verify operator and consumer decryption. For intentional
integration-secret rotation coordinate both consumers in dependency order and
verify allowed/denied access before retiring old material. Recipient rotation
and changing the underlying credential are distinct changes.

Keep application signing/encryption keys, databases, user credentials and machine
keys with matching ciphertext as required by the service. Never regenerate values
to work around a missing key. Use [recovery](recovery.md) for matching restoration.
