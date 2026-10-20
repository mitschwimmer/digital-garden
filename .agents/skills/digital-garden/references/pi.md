# Pi development sandbox

`systems/pi` owns an unprivileged NixOS Incus system container in the
`agent-sandbox` project. Its only NIC joins the unnumbered agent bridge. The
workstation builds and transfers NixOS closures through the existing deployment
entry point. Pi runs as uid 1000 without sudo; no host paths, management sockets,
SSH agent or upstream credentials are shared. CPU, memory, root and persistent
workspace capacity are bounded in HCL. The root can be rebuilt independently of
the protected home volume, which contains workspaces, Pi sessions and caches.

The native release archive is pinned in `nix/packages/pi.nix`, including its
bundled Bun runtime, themes and native helpers. Go, Node/npm, Git, `gh`, compiler
tools and fish come from the shared Nix pin. Project devShells and Nix builds
can download dependencies through the vault using the staged proxy-only session.
NixOS owns the base tools and daemon configuration; project flakes own their
pinned tool versions.

## Bundled Agent Vault skill

NixOS installs the matching Agent Vault CLI and its unmodified upstream
`cmd/skill_cli.md`, pinned by version and SHA-256 in the Pi configuration.
The managed `~/.pi/agent/skills/agent-vault-cli` link makes it available in every
workspace after deployment, without a runtime download or `pi install`.
Use `/reload` in an existing session, then `/skill:agent-vault-cli` to load it.

The skill describes upstream capabilities beyond this sandbox's current access.
Its proposal/discovery/credential commands require the vault management API and
an authenticated CLI environment; `garden-agent` currently supplies only proxy
variables. The management API remains unreachable from Pi and no operator login
is installed. For authentication failures, ask the operator to configure access
locally in the vault guest using [Agent Vault](agent-vault.md). Do not attempt to
read upstream credentials into Pi. Bundling the skill does not enable its proposal
workflow; that needs a separately reviewed management API access design.

When upgrading Agent Vault, update the skill hash with its version and review
the skill before deployment. After deployment, verify `agent-vault version`,
the managed skill link and Pi's startup skill diagnostics from an actual session.

## Boundary

`agent-network.json` supplies the static address. There is no default route or
DNS resolver. Host-enforced ACLs on the instance NIC allow only TCP to the vault
proxy and deny unmatched ingress/egress, independently of Pi's environment and
guest firewall. Apply the ACL directly to the NIC: a bridge-wide ACL alone does
not filter peer traffic. The dedicated bridge has no host IP/DHCP/DNS services,
avoiding Incus baseline service exceptions. IPv6 is disabled in NixOS and has no
ACL allow rule. No other guest may join this bridge.

The dual-homed vault drops forwarding and has a separate private-upstream guard.
All public HTTP/HTTPS destinations may be accessed through it without credentials;
only selected GitHub/model destinations receive real credentials. DNS resolution
happens at the vault. Other protocols have no direct fallback.

Incus nesting is enabled for Nix's sandbox namespaces while the guest remains
unprivileged. This relaxes container confinement to permit nested namespace/mount
operations; host NIC ACLs still constrain all guest and nested-build egress. Keep
Nix sandboxing enabled and verify it with an actual uncached build after restart.

The two guests share a host kernel. Pi's packages and extensions execute with
the same sandbox authority as Pi itself. Credential brokering does not constrain
what it can send to permitted public destinations or model providers.

## Setup and sessions

Bootstrap [Agent Vault](agent-vault.md) first and install its real public CA.
Then follow [setup](lifecycle.md#setup) for this root's own seed and protected home
mount. Its static network configuration is included in both seed and full guest.
CA absence permits source/seed builds but `garden-agent` refuses to launch.

Edit `systems/pi/models.json` with actual OpenAI-compatible provider definitions:
base URL, supported API type (`openai-completions` or `openai-responses`), model
IDs/capabilities, and a dummy `apiKey`. Pair each provider with an exact vault
credential rule. Do not put real keys or credential-reading commands here.
`settings.json` selects SSE and disables install telemetry. These files are
declaratively linked into Pi's home; change them in source and redeploy.

Enroll the sandbox with a seven-day proxy-only token, then rotate it before
expiry or when access should change. Pinned Agent Vault v0.40.0 permits at most
604800 seconds (seven days); this is a fixed lifetime, not renewed by use.
The token remains revocable and cannot mint replacements or administer the vault.
A copied token can use the vault's permitted upstream services until revoked or
expired. Keep upstream API keys and the operator login in the vault guest.

From a private terminal in the workstation development shell, replace `REMOTE`
with the inspected alias and mint using the operator's local login:

```fish
umask 077
set -l session_work (mktemp -d)
incus exec REMOTE:agent-vault --project agent-vault -T -- agent-vault vault token --vault pi-agent --ttl 604800 > "$session_work/token"
```

Check success and nonempty output before transferring; never print its content.
The token command defaults to proxy role; do not substitute a user login token,
which uses the same prefix and cannot be distinguished locally by the launcher.
Verify the recipient's identity against this root's applied deployment output,
then transfer the token to its persistent, root-owned directory. Deploy the
updated Pi closure first so this directory exists. Stage to a separate file and
rename only after a successful transfer, leaving the current token intact if
transfer fails:

```fish
incus file push "$session_work/token" REMOTE:pi/var/lib/garden-agent/token.new --project agent-sandbox --uid 0 --gid 1000 --mode 0640
# Continue only after a successful transfer, with no active Nix builds.
incus exec REMOTE:pi --project agent-sandbox -- mv -f /var/lib/garden-agent/token.new /var/lib/garden-agent/token
incus exec REMOTE:pi --project agent-sandbox -- systemctl restart nix-daemon.service
rm -r "$session_work"
```

The directory is root-owned with mode 0750 and the token is root:pi 0640.
It survives process restarts, closure deployments and container reboots on the
existing root disk. Recreating the guest requires enrollment again; the token
is deliberately outside the protected home volume and its backups.

Start an interactive session:

```fish
incus exec REMOTE:pi --project agent-sandbox --user 1000 --group 1000 --cwd /home/pi/workspace --env HOME=/home/pi -- garden-agent
```

Use `garden-agent -- fish` for a shell with the same proxy environment. The launcher
reads the token from a file, supplies proxy variables in both cases and CA-bundle
variables to Pi/Node, Git, Go and npm, then execs the command. It never fetches a
CA, logs a token or passes the token in process arguments. Session tokens are
still available in that process environment; they are bearer authority to proxy,
not upstream secrets. NixOS installs the reviewed CA alongside normal roots.

Keep this token between work sessions; closing Pi does not require revocation.
After rotation, restart Pi and any shells launched through `garden-agent`;
`/reload` does not replace their inherited proxy environment. Verify a model
request and a daemon dependency download before revoking the previous token
through the operator's vault token-management UI/API. Remove the temporary
workstation file after staging. Deleting a file does not revoke a token already
read by a process. Revoke the token when retiring the sandbox or after suspected
compromise. No automatic token issuer or scheduler is introduced.

When upgrading from the former four-hour session setup, mint a fresh seven-day
token at the new path after deploying, restart the daemon and Pi, then revoke
the old session and remove `/run/garden-agent/token`. Existing tokens do not gain
a longer lifetime from deployment. If rolling back to the old closure, its launcher
reads the old path and needs a separately staged valid token there.

HTTPS Git is required. The vault injects Basic authentication for the selected
Git owner/path and Bearer authentication for the GitHub API; `gh` receives only a
dummy token. Add Git LFS/submodule hosts and authentication rules only when needed.

## Project Nix builds

The Nix daemon uses `garden-agent --allow-missing-session -- nix-daemon --daemon`
to read the persisted token into its own environment. Shell proxy variables alone
do not configure the daemon. Without a staged token it starts offline so local
store/activation operations remain available; host ACLs still deny direct egress.
Stage a token and restart it through operator Incus exec. Restart after every token replacement,
waiting for active builds to finish first. Existing daemon connections/builds may
retain the previous session until they exit; its expiry/revocation remains effective
at the vault. Removing the token file alone does not revoke that session.

The shared launcher sets `NIX_SSL_CERT_FILE` to the reviewed NixOS CA bundle's
store path. Its containing store output is explicitly available inside build sandboxes. Mount
that whole output, not the certificate subfile: a derivation may already include
the output as a read-only input, and Nix cannot create a nested file mount there.
Nixpkgs fixed-output fetchers inherit proxy variables and `NIX_SSL_CERT_FILE`
from the daemon; ordinary builds retain Nix's network sandbox. Custom fetchers
must honor those interfaces too. No proxy URL/token is serialized into Nix source,
derivations, OpenTofu state or command arguments. Keep build logs free of proxy
environment dumps. Do not grant Pi Nix trusted-user privileges.

After applying this root's nesting change, restart the container before testing.
The persisted token survives; check it has not expired. Deploy the updated closure,
enroll or rotate if needed, start the daemon as above, then run inside the actual
project checkout:

```fish
nix develop --command true
nix develop --command ./scripts/check.sh
nix flake check --no-write-lock-file
```

Use the project's actual check entry points; inspect its CI to choose equivalent
package/check builds. Require a real uncached sandboxed build as well as cache
downloads: a fully substituted devShell does not prove namespace support. Test
a fixed-output dependency download using the custom CA. A cached tool suite
passing does not establish complete CI parity. Track root-disk use for the Nix
store and reclaim unneeded project roots/caches through normal Nix GC.

## Recovery and updates

Checkpoint the home volume off-host according to [recovery](recovery.md), quiescing
Pi and build processes first. It includes unpushed work and private transcripts;
dependency caches may be discarded. Preserve ownership uid/gid 1000. Restore home
into a freshly provisioned isolated guest, install the same reviewed public CA,
and stage a newly issued session. Do not back up the proxy token from
`/var/lib/garden-agent`.

Upgrade Pi independently of the vault and verify their proxy/client interfaces.
Use the garden's closure rollback procedure; rollback does not revert home/session
data. Decommission by revoking sessions, preserving required unpushed work, and
following [retirement](retirement.md).

## Acceptance

Run [source checks](validation.md) for platform, both new roots and both guest
closures/seeds. The Python launcher tests cover environment/credential handling,
not Incus firewall enforcement. The following checks require the actual host:

- Confirm only one sandbox NIC, no default route/resolver, no IPv6 allow rules,
  correct NIC ACL/default actions, and no bridge host address or DNS/DHCP listener.
- Verify direct TCP to a public IP, garden/backend/LAN hosts, metadata and the
  vault management port fails with proxy variables unset. Check IPv6, direct DNS
  packets and a deliberately altered guest route/firewall as root on a disposable
  sandbox. Inspect host traffic/ACL logs; a missing route alone is not proof that
  the host ACL enforces the boundary. Keep these tests separate from real work.
- Verify `nix develop`, binary-cache downloads and an uncached sandboxed Nix build,
  including a fixed-output Go dependency fetch through the vault. Restart after
  token rotation and verify the old session's revocation/expiry denies downloads.
- Verify public dependency downloads through `garden-agent -- fish`: use a throwaway
  Go module/cache and npm project/cache, then run real repository tests/builds.
- Verify trusted HTTPS clone/fetch/push on a disposable branch, `gh` API/PR work,
  streamed Pi output and tool execution for every configured model endpoint.
- Verify forbidden private upstreams via the vault and expiry/revocation of an
  active session. Stop the vault: public requests must fail without a direct fallback.
- Reboot Pi and verify workspace/session persistence, root:pi 0640 token permissions
  and successful model/daemon requests with the same unexpired token. Separately
  revoke or expire a disposable token and verify requests are rejected; an absent
  token must prevent Pi launch while the daemon can start offline. Verify both
  trust and expected failure after a deliberate CA mismatch in an isolated test.

Do not declare the network boundary accepted from static configuration or green CI.
Record actual results privately with revision, date and host environment.

Pinned upstream interfaces:
[Pi binary layout](https://github.com/earendil-works/pi/blob/v1.3.0/scripts/build-binaries.sh),
[Pi models](https://github.com/earendil-works/pi/blob/v1.3.0/packages/coding-agent/docs/models.md),
[vault proxy environment](https://github.com/Infisical/agent-vault/blob/v0.40.0/internal/isolation/env.go).

Token lifetime interface:
[CLI TTL](https://github.com/Infisical/agent-vault/blob/v0.40.0/cmd/token.go),
[server bounds](https://github.com/Infisical/agent-vault/blob/v0.40.0/internal/server/server.go).
