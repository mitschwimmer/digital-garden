# Configure ingress exclusively through Nix

`systems/edge/configuration.nix` owns every Caddy route and option. There is one
complete edge configuration; no partial edge-ingress/full-edge modes. Caddy's
admin API is off, config persistence is off, resume is false, and enableReload
is false. NixOS restarts Caddy on configuration changes. Do not edit Caddyfiles,
use an admin API, import dynamic route files or persist API-generated config.
Certificate/ACME state alone belongs on `/var/lib/caddy`.

Caddy performs no user authentication. Publish user applications only when they
implement native OIDC with Kanidm and enforce allowed groups. No forward-auth,
authentication proxy or trusted identity-header fallback is supported. The auth
portal, ACME challenge endpoint and static readiness response are infrastructure
endpoints, not exceptions for unauthenticated user applications.

## Apply the change

Provision edge's LAN device using [infrastructure](infrastructure.md). Its Nix
configuration uses eth0 backend DHCP and eth1 LAN DHCP/IPv6 RA. Only LAN TCP
80/443 is open; HTTP/3 is disabled. Backend admin/health ports are not public.
Build the native Caddy validator from the checkout:

```fish
nix build .#checks.x86_64-linux.caddy-config --no-link
```

Activate from systems/edge. Its routes do not require identity to be running,
so edge can start first and solve the identity guest's ACME bootstrap dependency.

Configure manual DNS for test/auth/ai/identity.archaic.work (or wildcard DNS)
and route public TCP 80/443 to edge. `identity.archaic.work` exposes only HTTP
ACME challenges; edge proxies them to identity:8081. Its HTTPS certificate is
owned by the identity guest, for Caddy-to-Kanidm TLS on private port 8443.
Caddy verifies the public CA chain and uses identity.archaic.work as TLS SNI.
There is no insecure TLS mode or private key shared across guests.

Publish AAAA only when it reaches edge's real public IPv6, with explicit router
firewall rules. Private ULA/link-local addresses are not public AAAA targets.
IPv4 NAT does not protect IPv6. Never forward Kanidm 8443/8081, WebUI 8080,
inference, or the Incus API. Backend bridge workloads are trusted.

## Check the result

Use the applied remote in place of YOUR_REMOTE:

```fish
incus exec YOUR_REMOTE:edge --project default -- systemctl is-active caddy
incus exec YOUR_REMOTE:edge --project default -- curl --fail --max-time 30 http://127.0.0.1:8080/healthz
curl --fail --max-time 30 -4 https://test.archaic.work
curl --fail --max-time 30 -4 https://auth.archaic.work
```

Test -6 too if AAAA is published. Require trusted TLS without -k; auth becomes
available after identity activation. An arbitrary path on
http://identity.archaic.work must return 404. Check port 2019 is not listening.
Restart edge, repeat readiness and HTTPS checks, and confirm certificate state
remains mounted. For failures inspect Caddy journal, LAN addresses, DNS/router
rules and upstream TLS. Roll back via [activation](activation.md) and restore
recorded DNS/router changes separately.
