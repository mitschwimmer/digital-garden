# Milestone 4: Open WebUI native OIDC

Prerequisite: identity gate passed, ai.archaic.work manually routed to edge,
private/public DNS and trusted HTTPS discovery reachable from the WebUI guest,
WebUI ciphertext with matching client secret, and its machine key. Edge already
contains the Caddy route and two-factor OIDC client. No forward-auth layer is added.

WebUI and its state/secrets belong to project `ai`. The shared edge remains in
`default`. WebUI uses a private NixOS system container because native environment-file
secrets and sops-nix simplify this workload. It accepts TCP 8080 on eth0 for
trusted host/backend callers. There is no LAN NIC, public forward or SSH listener.
All workloads/clients able to route to the private bridge are trusted infrastructure;
WebUI additionally requires OIDC. A separate bridge alone does not enforce caller
isolation. Do not attach untrusted guests without adding a reviewed network policy.

```fish
jq '.stage = 4' tofu/site.auto.tfvars.json > tofu/site.auto.tfvars.json.tmp
mv tofu/site.auto.tfvars.json.tmp tofu/site.auto.tfvars.json
nix build .#nixosConfigurations.open-webui.config.system.build.toplevel --out-link result-open-webui-system
```

This builds the complete package with the [pinned authorization patch](../nix/patches/README.md).
Run [plan/apply](runbook.md#native-planapply-and-activation): one guest addition,
no deletion/replacement, existing volumes unchanged. Install only the restored or
new prepared key after confirming it is absent (skip transfer if the existing
correct key is already present):

```fish
incus exec "$GARDEN_REMOTE:open-webui" --project ai -- mountpoint /var/lib/open-webui
incus exec "$GARDEN_REMOTE:open-webui" --project ai -- mountpoint /var/lib/garden-secrets
incus exec "$GARDEN_REMOTE:open-webui" --project ai -- test ! -e /var/lib/garden-secrets/age.key
incus file push "$GARDEN_SECRET_WORK/webui.agekey" "$GARDEN_REMOTE:open-webui/var/lib/garden-secrets/age.key" --project ai --uid 0 --gid 0 --mode 0600
incus exec "$GARDEN_REMOTE:open-webui" --project ai -- curl --fail https://auth.archaic.work/.well-known/openid-configuration
set -gx GARDEN_PROJECT ai
set -gx GARDEN_GUEST open-webui
set -gx GARDEN_CONFIG open-webui
```

Stop for failed mount/path/discovery checks. [Activate](activation.md) and verify:

```fish
incus exec "$GARDEN_REMOTE:edge" --project ai -- getent hosts open-webui.garden.internal
incus exec "$GARDEN_REMOTE:open-webui" --project ai -- systemctl is-active open-webui
incus exec "$GARDEN_REMOTE:open-webui" --project ai -- test -s /run/secrets/environment
incus exec "$GARDEN_REMOTE:open-webui" --project ai -- curl --fail --retry 30 --retry-connrefused --retry-delay 2 http://127.0.0.1:8080/health
curl --fail https://ai.archaic.work/health
```

Browser gate in a private window: only Authelia login, TOTP required, admins receive
admin role, ai-users receive user role, unrelated or absent groups are denied.
Test with separate identities through encrypted users configuration; retain your
operator admin. For an **empty** WebUI database, try denied and ai-users identities
before the first admin: denied identities must not create/promote the initial user;
first ai-users must remain a user. Test sole-user subsequent login and missing
claims as well. Use a disposable backed-up test state if a populated production
database cannot exercise bootstrap behavior; never delete its database to test.
If the IdP always supplies groups, test absent groups with a separate user with no
groups and verify no claim from another source silently grants access.

Restart WebUI and edge, then log in again; the account/settings remain and a new
private window requires login. Inference is expected to be unavailable until stage
5. Gate: both permitted-role behavior and denial/first-user behavior passed,
matching identity and state persist. Login alone is insufficient.

Failure/resume: inspect service/sops-nix journals, ownership of the mounted state,
DNS/hairpin routing, issuer/callback URL, client hash/plaintext pairing, PKCE and
IdP groups. Correct declared config/ciphertext and reactivate; do not enable local
signup as a workaround. Rollback uses the recorded previous generation plus a
matching data backup for migrations, retaining state and keys. Next: [inference](05-inference.md).

Source: [pinned NixOS WebUI module](https://github.com/NixOS/nixpkgs/blob/0d9e9b832d03ac387417e16ce1febf73b2e631e1/nixos/modules/services/misc/open-webui.nix).
