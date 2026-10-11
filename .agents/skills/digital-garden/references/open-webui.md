# Compose Open WebUI with native OIDC

- [Scope and inputs](#scope-and-inputs)
- [Apply the change](#apply-the-change)
- [Check the result](#check-the-result)
- [Resume and rollback](#resume-and-rollback)

## Scope and inputs

| Field | Requirement |
|---|---|
| Goal | Provide a private AI application with public HTTPS, native OIDC and an operator admin. |
| Prerequisites | Working [OIDC identity](identity.md); ai hostname routed, discovery reachable, matching client secret and machine key prepared. |
| Sources | `tofu/open-webui.tf`, `nix/hosts/open-webui.nix`, `nix/packages/open-webui.nix`, `secrets/open-webui.yaml`. |
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
jq '.enable_webui = true' tofu/site.auto.tfvars.json > tofu/site.auto.tfvars.json.tmp
mv tofu/site.auto.tfvars.json.tmp tofu/site.auto.tfvars.json
nix build .#nixosConfigurations.open-webui.config.system.build.toplevel --out-link result-open-webui-system
```

This builds Open WebUI 0.12.0 using the [package backport](../../../../nix/packages/README.md).
Back up application data before upgrading an existing guest, preserve service
selection and skip guest creation/key transfer when the existing guest and key
are already correct. Use the activation workflow to switch its closure.

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

Initialize an empty database with the operator admin account first. Upstream
promotes the first/sole user to admin; this is an intentional installation
assumption, not a guarantee that IdP groups gate bootstrap. Native OIDC remains
the login path, with Authelia TOTP required. Verify the operator remains admin
on subsequent login. If additional users are admitted, verify ai-users receive
user role and unrelated groups are denied after bootstrap. Missing-claim handling
follows upstream and must be reviewed before extending access.

Restart WebUI and edge; complete [guest readiness](readiness.md) for each project
and repeat the step-4 health checks before logging in again; the account/settings remain and a new
private window requires login. Chat inference additionally requires the configured inference backend. Require operator-admin behavior and, when additional users are admitted, permitted/denied-group checks passed,
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
