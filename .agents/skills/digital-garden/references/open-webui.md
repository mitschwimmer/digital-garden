# Compose Open WebUI with native OIDC

- [Scope and inputs](#scope-and-inputs)
- [Apply the change](#apply-the-change)
- [Check the result](#check-the-result)
- [Resume and rollback](#resume-and-rollback)

## Scope and inputs

| Field | Requirement |
|---|---|
| Goal | Provide a private AI application with public HTTPS and enforced IdP roles. |
| Prerequisites | Working [OIDC identity](identity.md); ai hostname routed, discovery reachable, matching client secret and machine key prepared. |
| Sources | `tofu/open-webui.tf`, `nix/hosts/open-webui.nix`, `nix/patches/`, `secrets/open-webui.yaml`. |
| Execution and inputs | Workstation and browser; WebUI closure and machine key. |
| Expected infrastructure effects | One guest addition; existing volumes retained; no deletion or replacement. |

Reuse the edge Caddy route and two-factor OIDC client. Use native OIDC without
a forward-auth layer.

WebUI and its state/secrets belong to project `ai`. The shared edge remains in
`default`. WebUI uses a private NixOS system container because native environment-file
secrets and sops-nix simplify this workload. It accepts TCP 8080 on eth0 for
trusted host/backend callers. There is no LAN NIC, public forward or SSH listener.
All workloads/clients able to route to the private bridge are trusted infrastructure;
WebUI additionally requires OIDC. A separate bridge alone does not enforce caller
isolation. Do not attach untrusted guests without adding a reviewed network policy.

## Apply the change

### 1. Build the WebUI configuration

```fish
jq '.stage = ([.stage, 4] | max)' tofu/site.auto.tfvars.json > tofu/site.auto.tfvars.json.tmp
mv tofu/site.auto.tfvars.json.tmp tofu/site.auto.tfvars.json
nix build .#nixosConfigurations.open-webui.config.system.build.toplevel --out-link result-open-webui-system
```

This builds the complete package with the [pinned authorization patch](../../../../nix/patches/README.md).

### 2. Create the guest and install its machine key

Run [plan/apply](infrastructure.md#review-and-apply-the-whole-plan): one guest addition,
no deletion/replacement, existing volumes unchanged. Set the target:

```fish
set -gx GARDEN_PROJECT ai
set -gx GARDEN_GUEST open-webui
set -gx GARDEN_CONFIG open-webui
```

Complete [guest readiness](readiness.md) for the seed. Install only the restored or
new prepared key after confirming it is absent (skip transfer if the existing
correct key is already present):

```fish
incus exec "$GARDEN_REMOTE:open-webui" --project ai -- mountpoint /var/lib/open-webui
incus exec "$GARDEN_REMOTE:open-webui" --project ai -- mountpoint /var/lib/garden-secrets
incus exec "$GARDEN_REMOTE:open-webui" --project ai -- test ! -e /var/lib/garden-secrets/age.key
```

Require both mounts and absence-test exit 0 before this separate transfer:

```fish
incus file push "$GARDEN_SECRET_WORK/webui.agekey" "$GARDEN_REMOTE:open-webui/var/lib/garden-secrets/age.key" --project ai --uid 0 --gid 0 --mode 0600
incus exec "$GARDEN_REMOTE:open-webui" --project ai -- curl --connect-timeout 5 --max-time 30 --fail https://auth.archaic.work/.well-known/openid-configuration
```

Stop for failed mount/path/discovery checks. Run the absence test separately;
if the key already exists, verify/reuse the intended identity and skip transfer.
Never continue from a failed absence check into a key overwrite.

### 3. Activate WebUI

Complete every step of [activation](activation.md) with `GARDEN_CONFIG=open-webui`.
A newly created guest is still the minimal seed until this switch. Complete
[guest readiness](readiness.md) again.

## Check the result

### 4. Verify service health

Run:

```fish
incus exec "$GARDEN_REMOTE:edge" --project default -- getent hosts open-webui.garden.internal
incus exec "$GARDEN_REMOTE:open-webui" --project ai -T -- env TERM=xterm systemctl is-active open-webui
incus exec "$GARDEN_REMOTE:open-webui" --project ai -- test -s /run/secrets/environment
incus exec "$GARDEN_REMOTE:open-webui" --project ai -- curl --connect-timeout 5 --max-time 30 --fail --retry 30 --retry-max-time 90 --retry-connrefused --retry-delay 2 http://127.0.0.1:8080/health
curl --connect-timeout 5 --max-time 30 --fail https://ai.archaic.work/health
```

Expect edge DNS to resolve WebUI, `active`, a nonempty runtime secret file,
successful local health and trusted public health. Stop on a failed check.

### 5. Verify authorization and restart persistence

Browser checks in a private window: only Authelia login, TOTP required, admins receive
admin role, ai-users receive user role, unrelated or absent groups are denied.
Test with separate identities through encrypted users configuration; retain your
operator admin. For an **empty** WebUI database, try denied and ai-users identities
before the first admin: denied identities must not create/promote the initial user;
first ai-users must remain a user. Test sole-user subsequent login and missing
claims as well. Use a disposable backed-up test state if a populated production
database cannot exercise bootstrap behavior; never delete its database to test.
If the IdP always supplies groups, test absent groups with a separate user with no
groups and verify no claim from another source silently grants access.

Restart WebUI and edge; complete [guest readiness](readiness.md) for each project
and repeat the step-4 health checks before logging in again; the account/settings remain and a new
private window requires login. Chat inference additionally requires the configured inference backend. Require both permitted-role behavior and denial/first-user behavior passed,
matching identity and state persist. Login alone is insufficient.

## Resume and rollback

```fish
incus exec "$GARDEN_REMOTE:open-webui" --project ai -T -- env TERM=xterm systemctl status open-webui sops-install-secrets --no-pager -l
incus exec "$GARDEN_REMOTE:open-webui" --project ai -T -- journalctl -u open-webui -u sops-install-secrets -b --no-pager -n 80
incus exec "$GARDEN_REMOTE:edge" --project default -T -- getent hosts open-webui.garden.internal
```

Review journals locally before sharing redacted errors. Then inspect service/sops-nix journals, ownership of the mounted state,
DNS/hairpin routing, issuer/callback URL, client hash/plaintext pairing, PKCE and
IdP groups. Correct declared config/ciphertext and reactivate; do not enable local
signup as a workaround. Rollback uses the recorded previous generation plus a
matching data backup for migrations, retaining state and keys.

Source: [pinned NixOS WebUI module](https://github.com/NixOS/nixpkgs/blob/0d9e9b832d03ac387417e16ce1febf73b2e631e1/nixos/modules/services/misc/open-webui.nix).
