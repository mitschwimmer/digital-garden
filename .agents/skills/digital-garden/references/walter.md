# Run Walter as a direct OCI application

- [Integrations and exposure](#integrations-and-exposure)
- [Prepare, deliver the secret, then start](#prepare-deliver-the-secret-then-start)
- [Fast development updates](#fast-development-updates)
- [Acceptance, updates and recovery](#acceptance-updates-and-recovery)

`systems/walter` owns one linux/amd64 OCI process and protected data/secret
volumes in the existing `ai` project. No seed, NixOS configuration or closure
deployment is involved. The image lock records the tested upstream publication
and source revision; image acceptance still requires live checks below.
The image has no shell or diagnostic utilities. Use edge or a trusted backend
for HTTP checks, and Incus console logs for startup/storage/discovery errors.

## Integrations and exposure

Edge publishes `https://walter.archaic.work`, progressively flushing SSE with a
7205-second header timeout around Walter's two-hour generation budget. Configure
public DNS for edge. There is no identity proxy. Walter enforces native OIDC,
exact Origin/CSRF checks and the `ai-users@auth.archaic.work` group SPN on every login. This reuses the
existing AI audience; membership remains owned by `directory.nix`.

`systems/identity/walter.nix` declares the confidential client only when its real
SOPS ciphertext is staged. Callback is exactly
`https://walter.archaic.work/auth/callback`. PKCE remains required; scopes are
openid/profile/groups. Kanidm's native `groups` claim contains group UUIDs and
SPNs, including `ai-users@auth.archaic.work`; match that exact SPN in Walter.
Do not map a custom `groups` claim: the native scope overwrites it.
Verify discovery at
`https://auth.archaic.work/oauth2/openid/walter/.well-known/openid-configuration`
returns the exact issuer configured in Walter. Deploy identity before starting
Walter; startup requires successful HTTPS discovery.

Walter calls the separately operated Strata LAN inference endpoint at
`http://192.168.1.28:8080/v1/chat/completions`, as declared in
`systems/walter/main.tf`. Caddy does not publish the model endpoint.
Walter has one private NIC, without a proxy device or public port mapping.
The intended HTTP caller for Walter is edge; trusted host administrators and
routable garden guests can also reach its backend. Project `ai` and gardenbr0
do not enforce caller isolation. Walter listens on IPv4 only; gardenbr0 has
no IPv6 subnet and must remain private. Verify lack of direct public IPv4/IPv6
access to Walter. Stronger separation from trusted guests needs a separate
network-policy change.

## Prepare, deliver the secret, then start

Run the shared [setup](lifecycle.md#setup) and
[infrastructure](infrastructure.md) workflow. Platform must already provide `ai`
and gardenbr0. Give this root its own inspected remote/pool inputs and state.
Initial whole-plan apply uses the default `start = false`: it creates a stopped
container and both volumes, with autostart/restart disabled.

For a new installation, follow [secret creation](secrets.md#create-and-encrypt)
with the identity/recovery recipients. `systems/identity/walter-secrets.yaml`
contains `walter-client`, the raw client secret also delivered to Walter. Preserve
existing identity inputs. For an existing installation reuse its ciphertext;
rotation is a coordinated change. Deploy identity before Walter startup.

Walter needs both its OIDC client secret and the Strata upstream API key at
startup. Native Incus custom-volume file transfer avoids a new guest or secret
controller and keeps plaintext outside OpenTofu state. In the private operator
terminal, from the repository root:

```bash
umask 077
secret_work="$(mktemp -d)"
sops --decrypt --extract '["walter-client"]' systems/identity/walter-secrets.yaml > "$secret_work/oidc-client"
sops --decrypt --extract '["strata-api-key"]' systems/walter/secrets.yaml > "$secret_work/strata-api-key"
```

Require success and both nonempty files before transfer; never print them. Inspect
`systems/walter/site.auto.tfvars.json`, applied state, remote inventory and volume
identity first. Load only this root's inputs:

```bash
WALTER_REMOTE="$(jq -r .incus_remote systems/walter/site.auto.tfvars.json)"
WALTER_POOL="$(jq -r .storage_pool systems/walter/site.auto.tfvars.json)"
incus storage volume file push "$secret_work/oidc-client" "$WALTER_REMOTE:$WALTER_POOL" walter-secrets/oidc-client --project ai --uid 65532 --gid 65532 --mode 0400
incus storage volume file push "$secret_work/strata-api-key" "$WALTER_REMOTE:$WALTER_POOL" walter-secrets/strata-api-key --project ai --uid 65532 --gid 65532 --mode 0400
```

Require a host/client supporting custom-volume file transfer. Verify both files
appear in the container at `/run/secrets/oidc-client` and
`/run/secrets/strata-api-key` with mapped UID/GID 65532 and mode 0400,
and the directory is 0700; do not chown raw host paths. The secret volume
is read-only in Walter. Transfer failure keeps startup disabled. Do not
use a provider `file`, environment value or local-exec provisioner for plaintext.
Remove only the operation's temporary plaintext after successful delivery and
verification; retain encrypted recovery material privately.

Inspect the endpoint, model and profiles in `systems/walter/main.tf` against the
runtime contract at the revision in `image.lock.json`. This deployment selects
Walter's `openai` backend. It does not send llama.cpp's `reasoning_format`,
template flags or progress/timing requests. Verify provider-supported reasoning
controls and clean answer content; do not assume the two modes toggle thinking.
Treat context/output limits as provider configuration until verified live.

The current HCL has a configuration mismatch: `quick_profile` and
`thoughtful_profile` inputs gate `start`, but the runtime JSON profiles are
hard-coded instead of consuming those inputs. Changing local inputs therefore
does not change model settings. Resolve that mismatch in source before a new
startup or profile change; do not fill dummy inputs merely to pass the gate.
The pinned Walter documentation recommends portable OpenAI profiles unless
provider-specific controls have been verified.

After secret/discovery/model verification, set `start = true`, review a new whole
plan and apply it. The plan enables running/autostart/restart. OpenTofu owns this
state; do not start manually to bypass the preparation gates.

## Fast development updates

For disposable development chats, per-update backups are intentionally skipped.
Persistent volumes remain protected. In the repository's development shell,
authenticate GitHub CLI once with `gh auth login`. Then run:

```bash
python operations/watch_walter_image.py
```

The helper waits for a successful main-push `oci.yml` publication with a digest
different from the current lock. It prints the digest to stdout and progress to
stderr; Ctrl-C cancels. It validates the artifact's run, revision, repository and
platform, but does not edit or deploy anything or prove runtime compatibility.
Missing or expired artifacts need a new successful publication.

Use `--json` to print the complete published lock when updating the pin, keeping
revision and publication metadata accurate:

```bash
python operations/watch_walter_image.py --json > systems/walter/image.lock.json.tmp &&
  mv systems/walter/image.lock.json.tmp systems/walter/image.lock.json
```

Review and commit the lock diff, then use [infrastructure](infrastructure.md)
from `systems/walter` to review and apply the exact saved whole plan. An image
replacement must retain both protected volumes. No preliminary stop/start cycle
or integration-owner deployment is needed for an image-only update. Verify
readiness, re-login, streaming and an existing conversation afterward. Use the
full backup/restore workflow below for valuable data.

## Acceptance, updates and recovery

From edge, require bounded private readiness before browser tests:

```bash
incus exec "$WALTER_REMOTE:edge" --project default -- curl --fail --retry 15 --retry-connrefused --retry-delay 2 --connect-timeout 5 --max-time 10 --retry-max-time 90 http://walter.garden.internal:8080/healthz
incus console "$WALTER_REMOTE:walter" --project ai --show-log
```

Health proves the process only. Through public HTTPS test allowed AI-group login,
denied unrelated/missing groups, logout, secure cookies and CSRF rejection.
Verify incremental SSE, answer quality in both modes, cancellation on stop
and browser disconnect, upstream errors and two-user conversation isolation.
Restart and verify chat persistence, failed interrupted placeholders and renewed
login. Require actual offline restoration and intended network exposure before
accepting the service. Keep observations private with revision/date/environment.

For normal updates/rotation with valuable data, first set `start = false` and apply a reviewed whole plan;
require clean shutdown before touching volumes. Walter handles SIGTERM with a
20-second shutdown budget; the host timeout is 30 seconds. Retain previous image,
source/inputs and a consistent data checkpoint. Rotate both client consumers in
dependency order, transfer with the same ownership, then enable startup through
a fresh whole plan and repeat acceptance. Image changes can replace the guest;
the protected volumes must survive and remain mapped to UID/GID 65532.

`/data` is the consistency group: one writer, per-user JSON conversations, private
content. Stop cleanly before snapshot/export/copy; encrypt off-host backups and
preserve 0700/ownership. Sessions are memory-only and disposable. Preserve the
matching client ciphertext/recovery key separately; the secret volume contains
plaintext and any export must also be encrypted. A local protected volume is not
a backup. Restore data with the writer stopped, use a compatible pinned image,
restore secret delivery, then verify real conversations, user isolation and
restart persistence. An image rollback cannot undo a future data-format change.

Decommission through the shared [retirement procedure](retirement.md), including
the provisioner check before client deletion; retain required ciphertext/data.
Do not remove shared ai-users or the ai project.

Upstream runtime contract:
read `.agents/skills/walter/references/operations.md` and `configuration.md`
in the Walter source revision recorded by `systems/walter/image.lock.json`.
