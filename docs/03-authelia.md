# Milestone 3: Authelia identity

Prerequisite: trusted Caddy ingress passed, auth.archaic.work manually routed to
edge, reachable SMTP with valid credentials, persistent machine key and all three
consumer ciphertext files prepared through [secrets](secrets.md). Preparing OIDC
now does not require starting WebUI. Keep protected local WebUI key for stage 4.

Authelia listens only on 127.0.0.1:9091 behind Caddy. Its SQLite state and TOTP
registrations persist at `/var/lib/authelia-main`; stable keys use sops-nix runtime
files. The private bridge resolver remains available alongside LAN DNS.

On the workstation:

```fish
git add .sops.yaml secrets/edge.yaml secrets/edge-oidc.yaml secrets/open-webui.yaml
jq '.stage = 3' tofu/site.auto.tfvars.json > tofu/site.auto.tfvars.json.tmp
mv tofu/site.auto.tfvars.json.tmp tofu/site.auto.tfvars.json
nix build .#checks.x86_64-linux.authelia-config .#checks.x86_64-linux.caddy-config --no-link
nix build .#nixosConfigurations.edge.config.system.build.toplevel --out-link result-edge-system
incus exec "$GARDEN_REMOTE:edge" --project default -- mountpoint /var/lib/authelia-main
incus exec "$GARDEN_REMOTE:edge" --project default -- mountpoint /var/lib/garden-secrets
incus exec "$GARDEN_REMOTE:edge" --project default -- test -s /var/lib/garden-secrets/age.key
set -gx GARDEN_PROJECT default
set -gx GARDEN_GUEST edge
set -gx GARDEN_CONFIG edge
```

Run the [whole plan](runbook.md#native-planapply-and-activation): expect no resource
changes. Then [activate](activation.md). The synthetic config validator proves
settings structure only; live SMTP, credentials and decryption are separate gates.

```fish
incus exec "$GARDEN_REMOTE:edge" --project default -- systemctl is-active authelia-main
incus exec "$GARDEN_REMOTE:edge" --project default -- test -s /run/secrets/authelia-storage
incus exec "$GARDEN_REMOTE:edge" --project default -- curl --fail --retry 10 --retry-connrefused --retry-delay 2 http://127.0.0.1:9091/api/health
curl --fail https://auth.archaic.work/.well-known/openid-configuration
```

Gate: discovery issuer is `https://auth.archaic.work`, login works, SMTP enrollment
email actually arrives, TOTP enrollment and a second-factor login work. Restart
edge; repeat login using the existing TOTP registration and verify the same user
identity. Confirm Authelia is loopback-only with `ss -lntp` inside edge, and the
sops-nix unit/services have no failures. Machine-only successful decryption is
shown by runtime secret creation/service activation, without printing secrets.

Failure/resume: inspect sops-nix and Authelia journals, mounts/key permissions,
recipient metadata, SMTP DNS/TLS and clock synchronization. Do not print runtime
secrets or post verification links/tokens in logs. Fix ciphertext via SOPS and
reactivate the same guest. Never regenerate the storage encryption key to fix a
decryption problem. Rollback uses the [previous generation](activation.md) and
matching database backup if schema changed; retain identity and state volumes.
Next: [WebUI authorization](04-open-webui.md) only after this identity gate passes.
