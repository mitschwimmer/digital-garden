# Open WebUI with Authelia OIDC

Acceptance: `https://ai.archaic.work` offers Authelia login, requires TOTP, and gives
the existing `admins` user WebUI admin access. Accounts in `ai-users` receive normal
access; accounts with neither group are rejected. Password login and public signup
are disabled. A version-checked patch removes upstream first/sole-user admin
promotion when OIDC roles are enabled; no account bypasses its Authelia group
assignment. Callback URL access logging is also disabled. Models remain empty until the next llama.cpp iteration.

OpenTofu adds one private NixOS container and two protected volumes. It reuses the
existing immutable seed image; do not rerun `prepare-edge.sh` or change
`image_directory`. NixOS manages WebUI 0.11.4, its runtime environment file, and
the edge's OIDC configuration. The existing `secrets/edge.yaml` is preserved.
New files separate OIDC signing/client material from WebUI credentials. The
operator can recover both; each machine can decrypt only its own file.

WebUI reaches Authelia at its public HTTPS discovery URL. The router must support
that connection from the private bridge through host NAT (hairpin NAT or equivalent
local DNS). The deploy script checks this before changing WebUI's system profile.
Wildcard DNS and the existing Caddy port forwards must cover `ai.archaic.work`.
Keep IPv6 exposure consistent with the already verified edge ingress.

## Apply

Run on the NixOS workstation, in fish, from this checkout:

```fish
git fetch origin
git switch homelab/open-webui
nix develop
tofu -chdir=tofu init
tofu -chdir=tofu validate
tofu -chdir=tofu plan -out=webui.tfplan
```

Expected for the existing deployment: **3 additions, 0 changes, 0 deletions**
(WebUI instance plus its state and machine-key volumes). Stop if the plan replaces
edge, changes the seed image, or removes anything. Apply the reviewed saved plan:

```fish
tofu -chdir=tofu apply webui.tfplan
python3 scripts/prepare-webui.py "$GARDEN_REMOTE"
git add .sops.yaml secrets/edge-oidc.yaml secrets/open-webui.yaml
bash scripts/deploy-edge.sh "$GARDEN_REMOTE"
bash scripts/deploy-webui.sh "$GARDEN_REMOTE"
```

The helper requires the existing operator identity at
`~/.config/digital-garden/operator.agekey` (or `--operator-key PATH`). It creates
the new guest identity once on its protected volume, checks encrypted operator
recovery, and refuses to overwrite existing OIDC/WebUI ciphertext. No credentials
are passed through OpenTofu. Store printed previous-system paths for rollback.
WebUI's closure is larger than edge; the first build/import can take longer.

## Verify

```fish
incus exec "$GARDEN_REMOTE:edge" --project default -- getent hosts open-webui.garden.internal
incus exec "$GARDEN_REMOTE:edge" --project default -- curl --fail http://open-webui.garden.internal:8080/health
incus exec "$GARDEN_REMOTE:open-webui" --project default -- systemctl is-active open-webui
incus exec "$GARDEN_REMOTE:open-webui" --project default -- curl --fail https://auth.archaic.work/.well-known/openid-configuration
curl --fail https://ai.archaic.work/health
```

Expected: DNS resolves the private guest address, the service is active, WebUI
health returns success, and OIDC discovery advertises issuer
`https://auth.archaic.work`. Open `https://ai.archaic.work`, choose Authelia, sign in
with TOTP, and check Admin Panel access. No local password or signup form should
be available. Native OIDC handles login; there is no second forward-auth gate.

Restart and verify persistence:

```fish
incus restart "$GARDEN_REMOTE:open-webui" --project default
incus exec "$GARDEN_REMOTE:open-webui" --project default -- curl --fail --retry 30 --retry-connrefused --retry-delay 2 http://127.0.0.1:8080/health
```

Sign in again; the same account and its settings should remain. A private browser
window must still require login. To test role rejection, create a separate test
identity without `admins`/`ai-users` using SOPS; do not remove your own admin group.
If something fails, inspect `journalctl -u open-webui -n 80 --no-pager` in WebUI or
`journalctl -u authelia-main -n 80 --no-pager` in edge. Never publish decrypted
environment files, cookies, callback URLs, or private keys.

After verification, commit and push the encrypted configuration and public policy:

```fish
git commit -m "Configure encrypted Open WebUI OIDC identities"
git push
```

Back up the operator key securely. Future edits use
`set -gx SOPS_AGE_KEY_FILE "$HOME/.config/digital-garden/operator.agekey"` and SOPS.
Keep signing/session keys stable unless performing an intentional rotation.

## Roll back

Each deployment automatically restores its own previous system on failed health
checks. If manual rollback is needed, use the paths printed by that deployment:

```fish
set PREVIOUS_EDGE /nix/store/PASTE_PREVIOUS_EDGE_SYSTEM
incus exec "$GARDEN_REMOTE:edge" --project default -- nix-env --profile /nix/var/nix/profiles/system --set "$PREVIOUS_EDGE"
incus exec "$GARDEN_REMOTE:edge" --project default -- "$PREVIOUS_EDGE/bin/switch-to-configuration" switch
incus stop "$GARDEN_REMOTE:open-webui" --project default
```

Restoring the previous edge generation removes the new public route and OIDC
configuration; WebUI's volumes and ciphertext remain intact. Do not use
`tofu destroy`: persistent volumes are deliberately protected. Before later WebUI
upgrades, snapshot its database volume; system rollback does not undo database
migrations.

## Next iteration

Add pinned llama.cpp OCI with AMD GPU access and persistent model storage, then
connect its private OpenAI-compatible API to WebUI.

References: [Authelia's versioned integration](https://github.com/authelia/authelia/blob/v4.39.20/docs/content/integration/openid-connect/clients/open-webui/index.md),
[WebUI SSO](https://docs.openwebui.com/features/authentication-access/auth/sso/),
and the [pinned NixOS service module](https://github.com/NixOS/nixpkgs/blob/0d9e9b832d03ac387417e16ce1febf73b2e631e1/nixos/modules/services/misc/open-webui.nix).
