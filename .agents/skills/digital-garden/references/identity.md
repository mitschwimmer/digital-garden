# Provide Authelia identity

## Scope and inputs

| Field | Requirement |
|---|---|
| Goal | Provide discovery, SMTP enrollment, TOTP and persistent identity through Caddy. |
| Prerequisites | Trusted [HTTPS ingress](ingress.md); auth hostname routed, SMTP credentials and [encrypted identities](secrets.md) prepared. |
| Sources | `nix/modules/edge-auth.nix`, `nix/modules/oidc-client.nix`, `nix/hosts/edge.nix`, consumer ciphertext. |
| Execution and inputs | Workstation and browser; full edge closure, edge machine key. |
| Expected infrastructure effects | No infrastructure change; NixOS activation enables identity services. |

Prepare all three consumer ciphertext files through [secrets](secrets.md).
Preparing OIDC does not require starting WebUI. Retain its protected machine key
until WebUI key delivery.

Authelia listens only on 127.0.0.1:9091 behind Caddy. Its SQLite state and TOTP
registrations persist at `/var/lib/authelia-main`; stable keys use sops-nix runtime
files. The private bridge resolver remains available alongside LAN DNS.

## Apply the change

### 1. Prepare identities and build on the workstation

Choose exactly one [secrets path](secrets.md): reuse existing encrypted identities,
or intentionally create new ones for an empty application database. Do not run
key generation against an existing key or silently replace repository ciphertext.
Complete edge key delivery and operator decryption checks before these builds.

```fish
git add .sops.yaml secrets/edge.yaml secrets/edge-oidc.yaml secrets/open-webui.yaml
nix build .#checks.x86_64-linux.authelia-config .#checks.x86_64-linux.caddy-config --no-link
nix build .#nixosConfigurations.edge.config.system.build.toplevel --out-link result-edge-system
incus exec "$GARDEN_REMOTE:edge" --project default -- mountpoint /var/lib/authelia-main
incus exec "$GARDEN_REMOTE:edge" --project default -- mountpoint /var/lib/garden-secrets
incus exec "$GARDEN_REMOTE:edge" --project default -- test -s /var/lib/garden-secrets/age.key
set -gx GARDEN_PROJECT default
set -gx GARDEN_GUEST edge
set -gx GARDEN_CONFIG edge
```

### 2. Review infrastructure and activate the full edge

Run the [whole plan](infrastructure.md#review-and-apply-the-whole-plan): expect no resource
changes. Then complete all steps of [activation](activation.md) with `GARDEN_CONFIG=edge`,
including transfer and switching the guest configuration. This enables Authelia;
infrastructure selection alone does not start it. The synthetic config validator proves
settings structure only; live SMTP, credentials and decryption are separate checks.

## Check the result

### 3. Verify services and identity

Complete [guest readiness](readiness.md) for edge/default first. Then run:

```fish
incus exec "$GARDEN_REMOTE:edge" --project default -T -- env TERM=xterm systemctl is-active authelia-main
incus exec "$GARDEN_REMOTE:edge" --project default -- test -s /run/secrets/authelia-storage
incus exec "$GARDEN_REMOTE:edge" --project default -- curl --connect-timeout 5 --max-time 30 --fail --retry 10 --retry-max-time 90 --retry-connrefused --retry-delay 2 http://127.0.0.1:9091/api/health
curl --connect-timeout 5 --max-time 30 --fail https://auth.archaic.work/.well-known/openid-configuration
```

Expect `active`, a successful secret-file existence check, successful local health
and a discovery document. Stop at any failure; never print secret-file contents.

Require discovery issuer is `https://auth.archaic.work`, login works, SMTP enrollment
email actually arrives, TOTP enrollment and a second-factor login work. Restart
edge; complete [guest readiness](readiness.md), repeat the service/health/discovery
checks above, and repeat login using the existing TOTP registration and verify the same user
identity. Confirm Authelia is loopback-only with `ss -lntp` inside edge, and the
sops-nix unit/services have no failures. Machine-only successful decryption is
shown by runtime secret creation/service activation, without printing secrets.

## Resume and rollback

```fish
incus exec "$GARDEN_REMOTE:edge" --project default -T -- env TERM=xterm systemctl status authelia-main sops-install-secrets --no-pager -l
incus exec "$GARDEN_REMOTE:edge" --project default -T -- journalctl -u authelia-main -u sops-install-secrets -b --no-pager -n 80
incus exec "$GARDEN_REMOTE:edge" --project default -T -- ss -lntp
```

Review journals locally; share redacted errors only. Then inspect sops-nix and Authelia journals, mounts/key permissions,
recipient metadata, SMTP DNS/TLS and clock synchronization. Do not print runtime
secrets or post verification links/tokens in logs. Fix ciphertext via SOPS and
reactivate the same guest. Never regenerate the storage encryption key to fix a
decryption problem. Rollback uses the [previous generation](activation.md) and
matching database backup if schema changed; retain identity and state volumes.
