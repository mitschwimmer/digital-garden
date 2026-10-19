# Standalone Agent Vault

`systems/agent-vault` owns the NixOS credential broker, persistent application
state and its machine-key volume. This is the standalone open-source project,
not the Infisical platform. The native binary is pinned in
`nix/packages/agent-vault.nix` using the upstream release archive's SHA-256.
The single-instance SQLite backend avoids another database service. The guest
uses NixOS for sops-nix, systemd credentials and reproducible guest deployment.

## Callers and boundary

The vault has a DHCP backend NIC (`eth0`, `gardenbr0`) and a static isolated NIC
(`eth1`). `agent-network.json` owns the isolated addresses and proxy port;
platform owns its unnumbered bridge and the two project namespaces. Review the
chosen subnet against host/LAN/VPN networks before creation. Neither the bridge
nor Pi has a gateway, DHCP or DNS service. The vault drops IP forwarding.

Only Pi's isolated address may connect to the proxy port. The management API is
reachable locally through authenticated Incus exec; neither interface permits
remote management connections. No Caddy route, public DNS, OIDC client, SMTP
service or public application is introduced. Operators use the CLI in the vault
guest. Never install operator login sessions in Pi or forward an Incus socket.

The proxy listener uses plain HTTP transport on this private link. Agents trust
the vault CA for intercepted upstream HTTPS; that CA does not encrypt proxy
authentication on the private link. Preserve separation from other workloads.
Both guests share the Incus host kernel; this is not a VM isolation boundary.

## Bootstrap

Follow [setup](lifecycle.md#setup), [platform inputs](platform.md),
[secrets](secrets.md) and [deployment](deployment.md). Ordering:

1. Reconcile platform's new bridge/projects. Build this root's seed, review/apply
   its complete plan, and verify its declared persistent mounts and identity.
2. Generate a distinct machine age key and add a creation rule for
   `^systems/agent-vault/secrets\.yaml$`, using the existing operator recovery
   recipient plus only this new guest's actual public recipient. Create real
   SOPS ciphertext with one `master-password` string containing an independent
   random password. Install the machine key on its verified secret mount.
   Never use passwordless mode or regenerate a password for an existing store.
3. Deploy the full vault closure. sops-nix delivers `/run/secrets/master-password`
   owned by `agent-vault` with mode `0400`; systemd opens that runtime file as stdin
   for `server --password-stdin`. Do not point `StandardInput=file:` at `%d`:
   per-unit credential paths are unavailable when systemd opens stdin
   ([upstream limitation](https://github.com/systemd/systemd/issues/31213)).
   Nothing is passed in process arguments or OpenTofu state. Missing ciphertext
   does not prevent source builds, but missing runtime credentials prevent startup.
4. Before provisioning Pi's session, register the first owner locally and enable
   invite-only registration. For example, from a private operator terminal
   (replace `REMOTE` with the inspected alias):

   ```fish
   incus exec REMOTE:agent-vault --project agent-vault -- agent-vault auth register
   incus exec REMOTE:agent-vault --project agent-vault -- agent-vault owner config set --invite-only
   incus exec REMOTE:agent-vault --project agent-vault -- agent-vault vault create pi-agent
   ```

5. Set only the required upstream credentials privately through the vault CLI.
   Inspect `agent-vault vault credential set --help` and use interactive/file
   inputs, never literal secret values in arguments. A fine-grained GitHub PAT
   must restrict repository access and permissions upstream; API path filtering
   cannot express GraphQL repository permissions. Store the GitHub login as
   `GITHUB_USERNAME` and PAT as `GITHUB_PAT`. Apply the reviewed public
   `systems/agent-vault/services.yaml` through `vault service set --vault pi-agent --file` after
   transferring that file to the guest. Narrow its Git owner/path if needed.
6. Leave `unmatched_host_policy` at its upstream default, passthrough, so public
   Go/npm dependencies and source archives work without receiving credentials.
   Verify that setting explicitly during acceptance. Private/reserved upstream
   ranges remain blocked by netguard. For an approved internal model endpoint,
   add only its specific address to `AGENT_VAULT_NETWORK_ALLOWLIST` in Nix and
   add an exact host/port/path credential rule. Do not enable all private ranges.
7. Extract the real CA over the authenticated management channel:

   ```fish
   incus exec REMOTE:agent-vault --project agent-vault -T -- agent-vault ca fetch > systems/agent-vault/ca.pem
   openssl x509 -in systems/agent-vault/ca.pem -noout -subject -fingerprint -sha256
   ```

   Check command success and compare the fingerprint with a second extraction
   directly inside the vault guest. Commit only the public certificate, then
   rebuild/deploy [Pi](pi.md). Never fetch-and-trust it inside the sandbox.

## Configuration and versions

The service owns its SQLite store beneath `/var/lib/agent-vault` (including the
encrypted CA key), while Nix owns the process, listeners and network guard.
Vault credentials, users and grants are application state. Public service rules
live in `services.yaml`; edit and apply those deliberately rather than introducing
another synchronization controller. Add actual model rules and Pi's actual
`models.json` together; no endpoint URLs or model IDs are assumed here.

The `pi-agent` vault permits general public web access. It protects brokered credentials
but does not prevent workspace exfiltration or abuse of permitted upstream APIs.
Use repository permissions/branch protection and provider spend limits.
Disable telemetry through `AGENT_VAULT_TELEMETRY=false`.

Upgrades must preserve the database, password and CA identity. Review migrations
and the pinned server/client interfaces before changing the release hash. A NixOS
generation rollback does not roll back database migrations. Keep a matching
pre-upgrade backup and old binary. Upstream is preview software.

## Backup, restore and retirement

The whole `/var/lib/agent-vault` tree and the matching master password, machine key
and ciphertext form the consistency group. Stop the service before copying its
entire state tree (including SQLite WAL/SHM and any CA files), then restart and
verify. Follow [off-host recovery](recovery.md); local volumes are not backups.
Restore the matching group with the compatible pinned version, verify the CA
fingerprint and proxy a real authenticated request before reopening Pi access.
Do not generate a replacement CA on restore. Exclude Pi's staged runtime tokens
from backups; issue new sessions after recovery.

On retirement revoke all vault sessions and upstream credentials before removing
routes/resources, retain required audit/recovery data, and follow
[retirement](retirement.md). The shared platform bridge survives a leaf removal.

## Acceptance and diagnostics

- Verify both `/health` and `/v1/mitm/ca.pem` locally: the management API can be
  healthy even if the proxy/CA failed to initialize. Check the proxy listener.
- From Pi, test public Go module and npm package downloads, HTTPS Git clone/fetch
  and an authenticated `gh api` call, then a real Pi tool-call round trip with
  streamed output through each selected model endpoint.
- Verify denied private/metadata requests through the proxy, correct credentials
  only on exact intended services, expired/revoked sessions failing, and rejected
  administrative calls by a proxy session. Use disposable test credentials and
  a controlled upstream to check headers without logging real secrets.
- Verify the API and proxy cannot be reached from backend neighbours; Pi may reach
  only the proxy. Run the host isolation checks in [Pi](pi.md#acceptance).
- Restart the vault and confirm real credentials, grants and CA fingerprint persist.
  Prove an isolated restore with actual backed-up data before relying on recovery.

Use `journalctl -u agent-vault` locally. Keep ordinary logs at info level; inspect
request-log retention and storage use before enabling verbose diagnostics.

Pinned upstream interfaces:
[server flags](https://github.com/Infisical/agent-vault/blob/v0.40.0/cmd/server.go),
[services](https://github.com/Infisical/agent-vault/blob/v0.40.0/docs/learn/services.mdx),
[network guard](https://github.com/Infisical/agent-vault/blob/v0.40.0/internal/netguard/netguard.go).
