# Iteration 3: Authelia portal with SMTP and SOPS

Goal: log into https://auth.archaic.work, receive a verification email, enroll TOTP,
and retain the account's second factor through a guest restart.

## Scope and prerequisites

Authelia listens only on 127.0.0.1:9091 behind Caddy. Guest ingress remains TCP 80/443 on eth1.
The test site stays public; no application is protected or integrated via OIDC yet.
Authelia access-control defaults to deny, with an explicit two-factor rule for *.archaic.work. Public auth DNS/routing is manual, just as for test.
Publish AAAA only if edge has working global IPv6 and the router permits that traffic.

Use an SMTP provider with authenticated TLS submission (587/STARTTLS or 465/TLS),
an authorized sender and a working inbox. The helper prompts locally for these details.
SMTP connectivity and credentials are checked by Authelia at startup; checks are not disabled.

Two new protected volumes hold the SQLite database/TOTP records and the machine age key.
No application data or secret enters OpenTofu state. Nix builds contain ciphertext only;
sops-nix decrypts five runtime files owned by authelia-main, mode 0400.
Operator recovery uses a separate private age key outside the repository.
Back it up securely before depending on this deployment.
Caddy continues to own its existing persistent certificate state.

The user database is encrypted and read-only at runtime. Password reset is disabled.
Use explicit SOPS edits to change passwords or users; do not rerun initialization to rotate
storage encryption keys. The prepare helper refuses existing ciphertext or policy.

## Apply

From your NixOS workstation, in fish:

```fish
git fetch origin
git switch homelab/authelia
nix develop --command fish
# Keep your existing GARDEN_REMOTE and tofu/site.auto.tfvars.json.
tofu -chdir=tofu init -input=false
tofu -chdir=tofu validate
tofu -chdir=tofu plan -out=auth.tfplan
```

Expected: 2 volume additions, 1 edge update, 0 destroys/replacements. Parent, MAC, image and
Caddy volume must be unchanged. Do not run prepare-edge.sh. Apply the reviewed plan:

```fish
tofu -chdir=tofu apply auth.tfplan
python3 scripts/prepare-auth.py "$GARDEN_REMOTE"
git add secrets/edge.yaml .sops.yaml
nix build .#checks.x86_64-linux.authelia-config .#checks.x86_64-linux.caddy-config --no-link
bash scripts/deploy-edge.sh "$GARDEN_REMOTE"
```

The helper prompts for username, password, email and SMTP details. No plaintext is written
to the checkout. It verifies operator decryption without printing any recovered fields.
Encrypted files must be staged so Git-backed Nix flakes include them. Review/stage only those
two generated files; commit the ciphertext and public policy after successful verification.
Never commit private keys. The default operator key is ~/.config/digital-garden/operator.agekey.

Record the previous-system path printed by deployment. Activation/health failures automatically
restore that system. The helper-created machine identity survives a failed deployment;
retry with existing encrypted inputs rather than generating new cryptographic material.
Missing SMTP credentials/provider access is the only external prerequisite besides DNS/routing.

## Verify

```fish
incus exec "$GARDEN_REMOTE:edge" --project default -- systemctl is-active authelia-main caddy
incus exec "$GARDEN_REMOTE:edge" --project default -- curl --fail http://127.0.0.1:9091/api/health
incus exec "$GARDEN_REMOTE:edge" --project default -- mountpoint /var/lib/authelia-main
incus exec "$GARDEN_REMOTE:edge" --project default -- mountpoint /var/lib/garden-secrets
incus exec "$GARDEN_REMOTE:edge" --project default -- ss -lnt
incus exec "$GARDEN_REMOTE:edge" --project default -- journalctl -u authelia-main -n 50 --no-pager
```

Expected: both services active, health status OK, mounted state/key directories and port 9091
bound to loopback only. Do not share secret files, recovery links or full debug logs.

Outside the home LAN, open https://auth.archaic.work with a normally trusted certificate.
Log in, choose TOTP enrollment, receive the SMTP verification message, follow its link
and enroll an authenticator. Verify a valid code succeeds and an invalid code is rejected.
The portal currently has no downstream applications; default deny is intentional.

```fish
incus restart "$GARDEN_REMOTE:edge" --project default
incus exec "$GARDEN_REMOTE:edge" --project default -- systemctl is-active authelia-main caddy
tofu -chdir=tofu plan -detailed-exitcode
```

Log in again and confirm the enrolled TOTP still works. Sessions may be invalidated by restart
because this slice uses in-memory sessions; persistent TOTP/account storage must survive.
Expected infrastructure plan exit 0. Confirm test.archaic.work still serves its original response.

After verification, commit secrets/edge.yaml and .sops.yaml locally and push them on this branch
before merging the PR. They contain ciphertext and public recipients; SMTP values and personal
user details are encrypted. Securely back up the operator private key and OpenTofu state.

## Roll back

Restore the previous guest configuration:

```fish
set -l PREVIOUS_SYSTEM /nix/store/YOUR_RECORDED_PREVIOUS_SYSTEM
incus exec "$GARDEN_REMOTE:edge" --project default -- nix-env --profile /nix/var/nix/profiles/system --set "$PREVIOUS_SYSTEM"
incus exec "$GARDEN_REMOTE:edge" --project default -- "$PREVIOUS_SYSTEM/bin/switch-to-configuration" switch
```

The old Caddy configuration removes the auth route. Restore manual auth DNS if changed.
Retain both protected volumes, ciphertext and operator key. Do not run tofu destroy or delete
the SQLite database/machine identity. Reverting Git alone does not revert the running guest.
This new database has no prior schema to roll back; take a database backup before later upgrades.

## Validation and next iteration

CI builds the guest and image, checks Caddy and Authelia configuration using synthetic test
secrets without network calls, validates OpenTofu and runs mocked plan regressions.
Real SOPS decryption, SMTP delivery, public HTTPS and enrollment require the live checks above.
Next: add one application and its native OIDC integration in its own iteration.
