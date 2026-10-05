# Iteration 2: Caddy on a new LAN identity

Goal: serve test.archaic.work with Caddy, persistent ACME state and a separate LAN address.
Acceptance: local health response is ok, external HTTPS returns the test message with a valid certificate,
and service/certificate state survives an edge restart.

## Scope

NixOS configures Caddy, dual-interface DHCP, IPv6 RA, and a firewall permitting only TCP 80/443 on eth1.
eth0 retains private backend networking; no inbound backend service ports are opened.
HTTP/3 is disabled for now. Caddy's administration API remains loopback-only.
OpenTofu adds one protected custom volume and attaches it plus an optional macvlan LAN NIC to edge.
No old resource is removed. Moving router forwarding to edge will make old public routes unavailable:
this edge currently serves only the test site.

NixOS updates use a built closure streamed through authenticated Incus, without guest SSH or
OpenTofu guest provisioners. The bootstrap seed image is now separate from ongoing guest configuration.
Keep the existing image_directory input for this deployed host; do not run prepare-edge.sh in this iteration.
Updating that input would replace the seed image and may replace edge.

Caddy refuses to start unless /var/lib/caddy is a mount point. The volume survives guest replacement.
NixOS creates the Caddy user and systemd sets ownership/permissions on the mounted directory.
ACME account and certificate keys are Caddy runtime state, not SOPS inputs.

## Manual prerequisites

Choose an unused new LAN DHCP reservation for the generated MAC. Confirm the actual LAN parent interface;
you can inspect the former Caddy's expanded NIC configuration from your workstation:

```fish
incus config show "$GARDEN_REMOTE:caddy" --project default --expanded
```

Use its macvlan parent for the same LAN; do not copy its MAC or address.
Macvlan prevents host-to-LAN-guest communication, so management continues through Incus and eth0.

Public HTTPS is blocked until DNS and router routing deliver traffic to this new edge:
- Reserve the new IPv4 for the generated MAC; forward public TCP 80/443 to that reservation.
- If test.archaic.work has an AAAA record, it must route to edge's actual global IPv6 address,
  with the router allowing only TCP 80/443 to that address. A ULA or link-local address is not public.
- Do not assume IPv4 NAT also protects IPv6 or routes an existing AAAA to a new MAC.
- Keep DNS manual. Verify A/AAAA and router rules before testing certificate issuance.
- If public IPv6 is unavailable, remove the test hostname's AAAA record before expecting HTTPS.
  If wildcard AAAA exists, add an explicit test hostname record arrangement that suppresses that wildcard.

Record existing router/DNS settings locally before changing them, for rollback.

## Apply

From the workstation checkout, using fish:

```fish
git fetch origin
git switch homelab/caddy-ingress
nix develop --command fish
set -gx GARDEN_REMOTE YOUR_REMOTE

# Replace YOUR_LAN_PARENT with the actual host interface identified above.
python3 scripts/configure-edge-lan.py YOUR_LAN_PARENT
tofu -chdir=tofu fmt -check
tofu -chdir=tofu init -input=false
tofu -chdir=tofu validate
tofu -chdir=tofu plan -out=caddy.tfplan
```

Expected on the already deployed bootstrap: one volume addition, one edge update, zero destroys/replacements.
Neither the old image nor edge may be replaced. Inspect the complete plan, then:

```fish
tofu -chdir=tofu apply caddy.tfplan
bash scripts/deploy-edge.sh "$GARDEN_REMOTE"
incus exec "$GARDEN_REMOTE:edge" --project default -- ip address show eth1
```

Record the printed previous-system path for rollback.
Reserve the new LAN address and set the DNS/router routing prerequisites above.
The script verifies local health before any router changes; certificate issuance may be pending until routing is ready.

## Verify

```fish
incus exec "$GARDEN_REMOTE:edge" --project default -- systemctl is-active caddy
incus exec "$GARDEN_REMOTE:edge" --project default -- mountpoint /var/lib/caddy
incus exec "$GARDEN_REMOTE:edge" --project default -- curl --fail http://127.0.0.1:8080/healthz
incus exec "$GARDEN_REMOTE:edge" --project default -- journalctl -u caddy -n 50 --no-pager
```

From a device outside the home network:

```fish
curl -4 --fail https://test.archaic.work
curl -6 --fail https://test.archaic.work
```

Expected: Digital Garden edge is ready. IPv6 is required only if the hostname publishes AAAA.
Do not use -k: that would bypass the certificate acceptance check.
HTTP should redirect to HTTPS. Then:

```fish
incus restart "$GARDEN_REMOTE:edge" --project default
incus exec "$GARDEN_REMOTE:edge" --project default -- systemctl is-active caddy
tofu -chdir=tofu plan -detailed-exitcode
```

Repeat external HTTPS after restart. Expected: same certificate, working site, and plan exit 0.
The seed image is not changed by guest activation; a no-change infrastructure plan does not validate guest content.

## Roll back

Restore the recorded router and manual DNS settings first.
Set the NixOS system profile back to the previous path printed by deploy-edge.sh:

```fish
set -l PREVIOUS_SYSTEM /nix/store/YOUR_PREVIOUS_SYSTEM
incus exec "$GARDEN_REMOTE:edge" --project default -- nix-env --profile /nix/var/nix/profiles/system --set "$PREVIOUS_SYSTEM"
incus exec "$GARDEN_REMOTE:edge" --project default -- "$PREVIOUS_SYSTEM/bin/switch-to-configuration" switch
```

Leave the attached protected volume and LAN device present until rollback is verified.
The previous guest configuration closes inbound service ports.
Do not run tofu destroy: the volume intentionally prevents deletion.
Removing LAN attachment later is an explicit infrastructure change; retain the Caddy volume.

## Validation and next iteration

CI builds the seed image and new edge closure, validates Caddy configuration, checks provider schema,
and runs the existing mocked plan/output regressions. Live mount, activation and public routing still require these checks.
After success, merge this iteration; next add Authelia independently.
