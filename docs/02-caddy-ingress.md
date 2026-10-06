# Milestone 2: Caddy ingress

Prerequisite: milestone 1 passed; inspected IncusOS instances bridge, stable LAN
MAC and unused DHCP reservation. Record existing DNS/router rules for rollback.
NixOS configures eth0 private DHCP with high route metric and eth1 LAN DHCP/IPv6
RA. Only TCP 80/443 is allowed inbound on eth1. HTTP/3 is disabled; Caddy admin
and local health remain loopback. Certificate state uses the protected volume.

On the workstation:

```fish
jq --arg parent "$GARDEN_LAN_PARENT" --arg mac "$GARDEN_LAN_MAC" '.stage = 2 | .edge_lan_parent = $parent | .edge_lan_mac = $mac' tofu/site.auto.tfvars.json > tofu/site.auto.tfvars.json.tmp
mv tofu/site.auto.tfvars.json.tmp tofu/site.auto.tfvars.json
set -gx GARDEN_GUEST edge
set -gx GARDEN_CONFIG edge-ingress
nix build .#nixosConfigurations.edge-ingress.config.system.build.toplevel --out-link result-edge-ingress-system
nix build .#checks.x86_64-linux.caddy-config --no-link
```

The Caddy check validates the final edge config with synthetic/non-secret inputs;
it does not issue certificates. Run the [whole plan/apply](runbook.md#native-planapply-and-activation):
expect one edge NIC update, no additions, replacement or deletion. Confirm
`/var/lib/caddy` is a mount point, then [activate](activation.md).

```fish
incus exec "$GARDEN_REMOTE:edge" --project default -- mountpoint /var/lib/caddy
incus exec "$GARDEN_REMOTE:edge" --project default -- ip address show eth1
incus exec "$GARDEN_REMOTE:edge" --project default -- systemctl is-active caddy
incus exec "$GARDEN_REMOTE:edge" --project default -- curl --fail http://127.0.0.1:8080/healthz
```

Reserve edge's IPv4 for its MAC and forward public TCP 80/443 to it. Manual A
records for test/auth/ai (or wildcard A) must point at your public IPv4. A published
AAAA must reach edge's actual global IPv6, with router firewall allowing only TCP
80/443 to it. If unavailable, remove/suppress the applicable AAAA including
wildcard inheritance. IPv4 NAT does not protect IPv6. No backend/management port
forwarding is intended. Do not expose the host Incus API through Caddy.

From outside the home network:

```fish
curl -I http://test.archaic.work
curl -4 --fail https://test.archaic.work
curl -6 --fail https://test.archaic.work
```

Expect HTTP redirect and trusted HTTPS with `Digital Garden edge is ready.`;
IPv6 check is mandatory when AAAA is published. Never use `-k`. Restart edge,
repeat health/external checks and inspect persistent certificate state; certificate
identity should be retained rather than reissued due to missing storage.

Failure/resume: inspect `journalctl -u caddy`, `networkctl status eth1`, DNS,
routes, DHCP reservation, ACME outbound HTTPS and external inbound rules. Check
mounts before retrying activation; Caddy refuses to run on disposable root state.
Never weaken the guest firewall to bypass routing issues. Rollback: restore
recorded DNS/router rules and the [previous NixOS generation](activation.md),
retaining the LAN attachment and state volume until verified. Removing LAN later
is a separately reviewed plan. Gate: trusted intended IPv4/IPv6 ingress and restart
persistence. Next: [identity](03-authelia.md).
