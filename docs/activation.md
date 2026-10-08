# Native NixOS activation and rollback

Run in fish on the workstation in the repository shell. The milestone sets
`GARDEN_GUEST` (`edge` or `open-webui`), `GARDEN_PROJECT` (`default` for edge,
`ai` for WebUI), and `GARDEN_CONFIG` (`edge-ingress`, `edge`, or `open-webui`). Before activating, confirm the guest's required volume mounts;
edge requires Caddy state, full edge additionally requires Authelia state and its
machine key; WebUI requires application state and its machine key. Ciphertext must
be staged in Git so flake source includes it. Never build plaintext into a flake.

## 1. Check target and retain the previous generation

Verify the three target variables match the milestone. Complete [guest readiness](readiness.md)
and its mount prerequisites. Then record the previous path:

```fish
set -l GARDEN_PREVIOUS (incus exec "$GARDEN_REMOTE:$GARDEN_GUEST" --project "$GARDEN_PROJECT" -- readlink -f /nix/var/nix/profiles/system)
```

Stop if this fails or does not return one `/nix/store/` path. Save it privately.

## 2. Select the built closure

Each milestone builds `result-$GARDEN_CONFIG-system` on the workstation. Reuse it:

```fish
set -l GARDEN_CLOSURE (readlink -f "result-$GARDEN_CONFIG-system")
test -x "$GARDEN_CLOSURE/bin/switch-to-configuration"
```

Require an existing `/nix/store/` path and test exit 0. If the link is missing,
finish the milestone build first; do not substitute `image_directory` here.

## 3. Transfer the closure

Use native Nix export/import; fish collects each requisite store path:

```fish
set -l GARDEN_PATHS (nix-store --query --requisites "$GARDEN_CLOSURE")
nix-store --export $GARDEN_PATHS | incus exec "$GARDEN_REMOTE:$GARDEN_GUEST" --project "$GARDEN_PROJECT" -T -- nix-store --import
echo $pipestatus
```

Check both entries of fish's `$pipestatus` are zero before continuing. The import
output contains store paths only. Stop unless both statuses are 0.

## 4. Activate guest services

Run the profile update and switch separately, checking each exit status:

```fish
incus exec "$GARDEN_REMOTE:$GARDEN_GUEST" --project "$GARDEN_PROJECT" -- nix-env --profile /nix/var/nix/profiles/system --set "$GARDEN_CLOSURE"
incus exec "$GARDEN_REMOTE:$GARDEN_GUEST" --project "$GARDEN_PROJECT" -- "$GARDEN_CLOSURE/bin/switch-to-configuration" switch
incus exec "$GARDEN_REMOTE:$GARDEN_GUEST" --project "$GARDEN_PROJECT" -T -- env TERM=xterm systemctl --failed --no-pager
```

Stop on a failed command. A failed activation can leave the profile and running
services different. Inspect journals and mounts, repair the prerequisite and
repeat activation of the same closure; export/import is safe to repeat. Do not
advance merely because the profile points at the new system.

## 5. Verify and record acceptance

Complete [guest readiness](readiness.md), then run the milestone's service/health,
external, authorization and restart gates. No failed units are expected. An
inactive/missing service requires diagnostics; successful profile selection alone
is not acceptance. Preserve the previous generation until these gates pass.

## Rollback

If the new generation fails, restore the recorded previous profile and activate
it with these commands (in the same session, where `GARDEN_PREVIOUS` is recorded):

```fish
incus exec "$GARDEN_REMOTE:$GARDEN_GUEST" --project "$GARDEN_PROJECT" -- nix-env --profile /nix/var/nix/profiles/system --set "$GARDEN_PREVIOUS"
incus exec "$GARDEN_REMOTE:$GARDEN_GUEST" --project "$GARDEN_PROJECT" -- "$GARDEN_PREVIOUS/bin/switch-to-configuration" switch
```

If returning in a new session, load the previously recorded path into
`GARDEN_PREVIOUS` first. Restore matching database backups if the upgrade changed
its schema. Leave volumes and machine identities intact. Restore previous manual
DNS/router rules if ingress changed. Reconcile repository configuration with the
accepted running generation before resuming; an OpenTofu no-change plan cannot
detect a NixOS rollback. Do not garbage-collect the needed previous generation.
