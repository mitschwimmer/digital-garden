# Operate LAN-only WebDAV behind shared Caddy

`systems/webdav/` owns a NixOS container in project webdav, with a native
`services.webdav` service pinned through nixpkgs (hacdias/webdav). It serves the
accounts henner, claudi and elmo at `https://webdav.archaic.work/`. Each account has
CRUD access only to its own filesystem root, `/var/lib/webdav/<username>`, with
no default permissions. All three use independent credentials.
This is an explicit LAN-only exception to the native-OIDC publication policy:
WebDAV authenticates clients itself; Caddy performs only source-address filtering.

## Exposure and certificate ownership

The shared edge owns the hostname, public certificate and ACME state. HTTP-01
uses the existing public port 80; TLS-ALPN validation is disabled for this site.
There are no DNS API credentials, shared certificate keys or guest-owned TLS.
Caddy handles active ACME challenges itself, independently of application routes.
Ordinary HTTP requests may receive its automatic HTTPS redirect.

The HTTPS listener is publicly reachable. Non-LAN application requests receive
403 before proxying; this is application access restriction, not a private
listener. Caddy's TCP/TLS/HTTP stack remains exposed. Its IP matcher uses the
immediate peer (`remote_ip`), ignoring forged forwarding headers. A router that
SNATs internet traffic into an allowed LAN address defeats this restriction.
Compromised LAN devices pass the network filter but still need WebDAV credentials.

The WebDAV container has only eth0 on gardenbr0, with IPv6 disabled. Its nftables
firewall permits TCP 6065 only from edge's reserved backend IPv4. No backend port
is forwarded on the router. The trusted shared bridge is not tenant isolation.
Local host processes and a compromised edge remain within the trust boundary.

## Set the network policy

Inspect measerve's applied gardenbr0 subnet, edge address, LAN subnet and router
behavior before editing the tracked `network-policy.json`. Set:

- `webdavLanCidrs`: currently `["192.168.1.0/24"]`, the accepted IPv4 LAN.
  Empty means deny everyone. Do not use `private_ranges`,
  the entire backend bridge, loopback, or `0.0.0.0/0` / `::/0`.
- `edgeBackendIPv4`: an unused/reserved address inside gardenbr0, preferably
  edge's current address after confirming it can be retained. Edge's OpenTofu
  NIC declaration reserves this address; WebDAV uses the same source in its
  firewall. Null leaves existing edge DHCP behavior intact and blocks a full
  WebDAV closure build.

Keep these non-secret network declarations under version control. Review edge's
whole infrastructure plan before applying the NIC reservation. Do not reuse an
address assigned to another instance. The reservation takes effect only after
reconciliation and DHCP lease acquisition; verify the actual address before
deploying WebDAV. Changing it later requires reconciling edge and deploying the
WebDAV firewall together.

Publish an A record for webdav.archaic.work pointing to the existing public edge
address; retain port 80 forwarding for HTTP-01 renewal. Configure local DNS to
resolve the same hostname to edge's LAN address, avoiding hairpin NAT. Without
local DNS, hairpin NAT must be verified to preserve the intended client identity.
Publish AAAA only if edge's public IPv6 and router rules are correct. IPv6 client
requests are denied unless their exact LAN prefix is explicitly listed. Do not
broaden the allowlist to compensate for changing IPv6 prefixes.

## Provision and deliver the credential

Reconcile platform to create the webdav project, then follow
[seed creation](nixos-guests.md) and [infrastructure reconciliation](infrastructure.md)
from systems/webdav. Its local inputs contain the inspected measerve remote,
root/secrets storage pool and its own immutable webdav-image directory. The
existing larger pool `data` must also be present. It owns protected
`garden-webdav-state` on `data` and `garden-webdav-secrets` on the configured
`storage_pool`; the root disk uses `storage_pool` as well. The mounted data path
is `/var/lib/webdav`, with separate henner, claudi and elmo directories.
Changing pools for an already provisioned volume requires a reviewed data
migration; `prevent_destroy` blocks accidental replacement. No application service
or credentials are present in the seed.

Following [secret delivery](secrets.md), generate a distinct WebDAV machine age
key on the secured workstation. Add a creation rule for
`^systems/webdav/secrets\.yaml$` to `.sops.yaml` using the existing operator
recovery recipient and this new guest's actual public recipient. Do not reuse
another guest's private key. Encrypt a YAML input with one key, `environment`,
whose string value is an EnvironmentFile containing these three variables and
a trailing newline:

| Account | Password variable | Filesystem root |
|---|---|---|
| henner | `WEBDAV_HENNER_PASSWORD` | `/var/lib/webdav/henner` |
| claudi | `WEBDAV_CLAUDI_PASSWORD` | `/var/lib/webdav/claudi` |
| elmo | `WEBDAV_ELMO_PASSWORD` | `/var/lib/webdav/elmo` |

Generate each password independently (for example, three separate
`openssl rand -hex 32` invocations into protected files). Never reuse a value.
`operations/check_webdav_credentials.py` runs before WebDAV starts and rejects
missing, blank or duplicate values without printing them. This small helper is
needed because the native module does not enforce distinct account passwords.
Tests use synthetic credentials only; real ciphertext remains an operator input.
Assemble and encrypt in a protected directory; never put plaintext in the
checkout, shell arguments, Tofu inputs/state or Nix store. Stage only ciphertext
and real public recipients; no placeholder ciphertext is supplied by this change.

After seed readiness, verify `user.garden.system=webdav` and that
`/var/lib/garden-secrets` is a mount point. Install only this guest's machine key
at `/var/lib/garden-secrets/age.key`, root-owned with mode 0600, refusing to
overwrite an existing key. Verify operator decryption to `/dev/null`. Then build
and deploy from systems/webdav using [deployment](deployment.md).
The runtime environment is owned by webdav with mode 0400; credential updates
restart the service. Both persistent mounts are required for service startup.

Deploy edge's reviewed route only after the backend is ready. Enter
`https://webdav.archaic.work/`, the person's username (henner, claudi or elmo),
and that account's dedicated password into Enpass or another WebDAV client.
The URL is the same for all three; each authenticated root exposes only that
account's directory. Other applications' data must not be mounted beneath it.

## Check the result

Source/build gates from the repository root:

```fish
nix build .#webdav-image --no-link
nix build .#checks.x86_64-linux.caddy-config .#checks.x86_64-linux.webdav-ingress .#checks.x86_64-linux.webdav-accounts --no-link
nix build .#nixosConfigurations.edge.config.system.build.toplevel --no-link
nix build .#nixosConfigurations.webdav.config.system.build.toplevel --no-link
```

The full WebDAV closure requires the real staged ciphertext and reserved edge
address. CI evaluates public service settings and builds the credential-free
seed and routing checks. The routing regression uses Nix-generated route text,
with only TLS transport and the backend dial address replaced for an offline
test. It checks deny-all defaults, admitted IPv4 clients, denied clients,
forwarded-header forgery, WebDAV methods and paths, and denied IPv6 when available.
The account regression runs the pinned WebDAV server with Nix-generated public
settings, temporary directories and synthetic passwords, testing separate file
roots, traversal rejection, CRUD and cross-account password rejection. Neither
regression proves certificate renewal or the live router's source-address behavior.

Require these live checks before accepting the service:

1. Verify guest mounts, `systemctl is-active webdav`, and edge's actual reserved
   backend IPv4. Verify TCP 6065 can be reached from edge but not another backend
   guest or the LAN directly.
2. From the LAN, HTTPS must validate without `-k`. An unauthenticated request
   must reach WebDAV and return 401; wrong credentials must also be rejected.
   For each of the three accounts, exercise PROPFIND, create/upload, read, rename,
   lock/unlock where supported, and deletion in a disposable test directory.
   Verify files created by one account are absent from the other accounts' roots,
   including traversal attempts. Confirm each password fails for the other
   usernames. Finish with real synchronization from the intended clients.
3. From an actual internet connection, require 403 for GET, PROPFIND and PUT,
   even with valid WebDAV credentials and forged `X-Forwarded-For`, `X-Real-IP`
   and `Forwarded` headers. The backend must receive no such requests. Do not
   accept 401 as evidence of filtering: that means the backend was reached.
4. Repeat for public IPv6 if AAAA exists, and for excluded guest/VPN networks.
   Confirm an inactive ACME challenge path cannot reach WebDAV. Verify HTTP-01
   issuance and subsequent renewal without temporarily opening WebDAV access.
5. Restart both guests, repeat access checks and confirm the synchronized data
   and Caddy certificate state survive. Record revision/environment/results
   privately. Never include credentials or vault contents in logs or PRs.

## Recovery and rollback

Use [recovery](recovery.md) to checkpoint/export the webdav project's two volumes
while the WebDAV instance is stopped. Export `garden-webdav-state` from pool
`data`, and `garden-webdav-secrets` from its configured root/secrets pool; both
are in project webdav. Preserve its own root state, local
inputs, seed, ciphertext, recipient policy and machine key. Caddy's certificate
state stays with edge's backup. Retained volumes are not off-host backups.
Restore independently on an isolated target and verify actual Enpass data,
credentials, TLS and allowed/denied access before relying on the backup.

For upgrades, use the guarded guest rollback procedure; restore matching data
if a version changes its on-disk expectations. Roll back edge independently for
route changes. To close access immediately, deploy edge with an empty
`webdavLanCidrs` list; keep the backend data and identity intact.

Sources: [pinned NixOS module](https://github.com/NixOS/nixpkgs/blob/0d9e9b832d03ac387417e16ce1febf73b2e631e1/nixos/modules/services/network-filesystems/webdav.nix),
[WebDAV configuration](https://github.com/hacdias/webdav/blob/v5.11.9/README.md),
[Caddy IP matchers](https://caddyserver.com/docs/caddyfile/matchers#remote-ip),
[ACME challenges](https://letsencrypt.org/docs/challenge-types/).
