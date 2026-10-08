# Milestone 2: Caddy ingress

Prerequisite: milestone 1 passed; inspected IncusOS instances bridge, stable LAN
MAC and unused DHCP reservation. Record existing DNS/router rules for rollback.
NixOS configures eth0 private DHCP with high route metric and eth1 LAN DHCP/IPv6
RA. Only TCP 80/443 is allowed inbound on eth1. HTTP/3 is disabled; Caddy admin
and local health remain loopback. Certificate state uses the protected volume.

## 1. Build guest configuration on the workstation

```fish
jq --arg parent "$GARDEN_LAN_PARENT" --arg mac "$GARDEN_LAN_MAC" '.stage = 2 | .edge_lan_parent = $parent | .edge_lan_mac = $mac' tofu/site.auto.tfvars.json > tofu/site.auto.tfvars.json.tmp
mv tofu/site.auto.tfvars.json.tmp tofu/site.auto.tfvars.json
set -gx GARDEN_PROJECT default
set -gx GARDEN_GUEST edge
set -gx GARDEN_CONFIG edge-ingress
nix build .#nixosConfigurations.edge-ingress.config.system.build.toplevel --out-link result-edge-ingress-system
nix build .#checks.x86_64-linux.caddy-config --no-link
```

The Caddy check validates the final edge config with synthetic/non-secret inputs;
it does not issue certificates. Stop if either build fails.

## 2. Apply the LAN device and inspect prerequisites

Run the [whole plan/apply](runbook.md#native-planapply-and-activation): expect one
edge NIC update, no additions, replacement or deletion. Applying this plan only
attaches the LAN NIC; it does not install or start Caddy.

```fish
incus exec "$GARDEN_REMOTE:edge" --project default -T -- mountpoint /var/lib/caddy
incus exec "$GARDEN_REMOTE:edge" --project default -T -- ip link show eth1
```

Both must succeed. LAN DHCP/route policy is completed by the next activation.

## 3. Transfer and activate edge-ingress (required)

Complete **every step** of [native activation](activation.md), using the three
variables set above and the already-built `result-edge-ingress-system` closure.
That procedure exports/imports the closure, sets the guest system profile, and
runs `switch-to-configuration switch`. A successful build or OpenTofu apply does
not substitute for this activation. Stop on transfer or activation failure.

## 4. Verify local service health

Complete [guest readiness](readiness.md) for edge/default before these checks.

```fish
incus exec "$GARDEN_REMOTE:edge" --project default -- mountpoint /var/lib/caddy
incus exec "$GARDEN_REMOTE:edge" --project default -- ip address show eth1
incus exec "$GARDEN_REMOTE:edge" --project default -T -- env TERM=xterm systemctl is-active caddy
incus exec "$GARDEN_REMOTE:edge" --project default -- curl --connect-timeout 5 --max-time 30 --fail http://127.0.0.1:8080/healthz
```

Expect the mount check to succeed, a DHCP IPv4 address on eth1, `active`, and
`ok` from local health. If Caddy is inactive, use diagnostics below; do not advance.

## 5. Configure and verify external ingress

Reserve edge's IPv4 for its MAC and forward public TCP 80/443 to it. Manual A
records for test/auth/ai (or wildcard A) must point at your public IPv4. A published
AAAA must reach edge's actual publicly routable IPv6 (normally in 2000::/3), with router firewall allowing only TCP
80/443 to it. If unavailable, remove/suppress the applicable AAAA including
wildcard inheritance. Addresses in `fc00::/7` (including `fd79:...`) are private
ULAs, and `fe80::/10` addresses are link-local; neither is a public AAAA target.
IPv4 NAT does not protect IPv6. No backend/management port
forwarding is intended. Do not expose the host Incus API through Caddy.

From outside the home network:

```fish
curl --max-time 30 -I http://test.archaic.work
curl --max-time 30 -4 --fail https://test.archaic.work
curl --max-time 30 -6 --fail https://test.archaic.work
```

Expect HTTP redirect and trusted HTTPS with `Digital Garden edge is ready.`;
Run the IPv6 command only when AAAA is published; then it is mandatory. Never
use `-k`. ACME challenge requests receiving HTTP 200 prove reachability for the
challenge, not completed certificate issuance or trusted HTTPS.

## 6. Restart and verify persistence

```fish
incus restart "$GARDEN_REMOTE:edge" --project default
```

Repeat [guest readiness](readiness.md), all local checks in step 4 and external
checks in step 5. Inspect `/var/lib/caddy` as a mount point again; certificate state
must persist rather than be recreated on the disposable root. Renewals are normal;
missing storage is not. Record the accepted revision and results.

## Failure and resume

```fish
incus exec "$GARDEN_REMOTE:edge" --project default -T -- env TERM=xterm systemctl status caddy --no-pager -l
incus exec "$GARDEN_REMOTE:edge" --project default -T -- journalctl -u caddy -b --no-pager -n 80
incus exec "$GARDEN_REMOTE:edge" --project default -T -- env TERM=xterm networkctl status eth1 --no-pager
```

A missing Caddy unit suggests the minimal seed is still active; finish step 3.
A skipped mount condition requires repairing the persistent mount. A failed unit
requires its journal. If local health passes but public HTTPS fails, inspect
DNS A/AAAA, router forwards/firewall and ACME messages before changing the guest.

Failure/resume: inspect `journalctl -u caddy`, `networkctl status eth1`, DNS,
routes, DHCP reservation, ACME outbound HTTPS and external inbound rules. Check
mounts before retrying activation; Caddy refuses to run on disposable root state.
Never weaken the guest firewall to bypass routing issues. Rollback: restore
recorded DNS/router rules and the [previous NixOS generation](activation.md),
retaining the LAN attachment and state volume until verified. Removing LAN later
is a separately reviewed plan. Gate: trusted intended IPv4/IPv6 ingress and restart
persistence. Next: [identity](03-authelia.md).
